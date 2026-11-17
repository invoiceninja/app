import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:logging/logging.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

import 'package:admin/data/db/orphan_store_sweep.dart';
import 'package:admin/data/db/salvage.dart';

final _log = Logger('AppDatabase');

/// Base name of the drift store (the IndexedDB key) for generation 0.
const _kWasmDbBaseName = 'invoiceninja';

/// `localStorage` keys carrying which store is live and which are abandoned.
/// Deliberately versioned, like `invoiceninja.db.key.v1` on native.
const _kGenerationKey = 'invoiceninja.db.generation.v1';
const _kOrphansKey = 'invoiceninja.db.orphans.v1';

/// Abandoned stores we still remember. Each is dead weight in the origin's
/// quota, not a correctness problem, so the list is capped rather than allowed
/// to grow without bound on a browser that never lets us delete anything.
const _kMaxOrphans = 8;

/// Bound on a single `WasmDatabase.open`. The store is held **exclusively per
/// browser context**: an overlapping page reload — e.g. the forced reload
/// Flutter's self-destructing service worker performs after a redeploy — can
/// leave a stale context holding the lock, so the next `open` blocks
/// **indefinitely with no error**, trapping boot on the HTML loader forever.
/// Bounding the open turns that hang into a `TimeoutException`, which
/// `openAppDatabase()`'s reset-and-reopen recovery catches (and, failing even
/// that, the `web/index.html` loader safety-net surfaces a reload prompt).
const _kOpenTimeout = Duration(seconds: 5);

/// These two assets are vendored into `web/` and served from the app root.
/// `sqlite3.wasm` is the plain (unencrypted) build — web does not use
/// SQLCipher (see CLAUDE.md § Web). `drift_worker.js` is generated via
/// `dart run drift_dev make-driftworker`. Both must be version-matched to
/// the resolved `drift` / `sqlite3` packages.
final _sqlite3Uri = Uri.parse('sqlite3.wasm');
final _driftWorkerUri = Uri.parse('drift_worker.js');

/// In-memory fallback for the generation when `localStorage` is unwritable
/// (private mode, blocked site data). A generation that does not survive the
/// reload is still enough to hand *this* page load a clean store.
int? _generationFallback;

String? _readLocal(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void _writeLocal(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Non-fatal: the in-memory fallback still gives this page load a clean
    // store; the orphan is simply never swept.
  }
}

int _generation() =>
    _generationFallback ?? int.tryParse(_readLocal(_kGenerationKey) ?? '') ?? 0;

/// Generation 0 keeps the original name, so an ordinary install is untouched
/// by this mechanism and nothing has to migrate to adopt it.
String _dbName([int? generation]) {
  final gen = generation ?? _generation();
  return gen == 0 ? _kWasmDbBaseName : '${_kWasmDbBaseName}_g$gen';
}

List<String> _orphans() => (_readLocal(_kOrphansKey) ?? '')
    .split(',')
    .where((s) => s.isNotEmpty)
    .toList();

/// Delete [name] and report whether it is **actually gone**.
///
/// Deliberately not drift's `probe.deleteDatabase`. That path re-attaches to
/// the same shared worker (so it can re-block the very delete it is about to
/// attempt), leaks the probe's `SharedWorker` + `Worker` on every call, and
/// bottoms out in a drift 2.33 bug: its `blocked` listener reads
/// `IDBRequest.error` while the request is still pending, which throws
/// `InvalidStateError` *inside the listener*, so the completer is never
/// completed and the future hangs forever
/// (`drift/src/web/wasm_setup/shared.dart`, `CompleteIdbRequest.complete`).
/// `IndexedDbFileSystem.deleteDatabase` carries its own 1s bound instead.
Future<bool> _deleteStore(String name) async {
  var deleted = false;
  try {
    await IndexedDbFileSystem.deleteDatabase(name);
    deleted = true;
  } catch (e) {
    // Almost always the blocked-delete case: something still holds the store
    // open. Not fatal — the caller abandons the store instead.
    _log.warning('Deleting web database store "$name" failed: $e');
  }
  // Never take the delete's word for it. Claiming a reset that did not happen
  // is the exact bug this path exists to prevent: it left the app reopening a
  // corrupt store while reporting `wasReset: true`, so every write failed.
  try {
    final names = await IndexedDbFileSystem.databases();
    if (names != null) return !names.contains(name);
  } catch (_) {
    // `IDBFactory.databases()` is unsupported here; fall back to trusting a
    // delete that at least resolved without throwing.
  }
  return deleted;
}

/// Abandon the current store and point every future open at a brand-new one.
///
/// The web mirror of native's `<name>.broken.<ts>` rename: a store that cannot
/// be *deleted* can always be **left behind**. Without this a browser that
/// refuses the delete has no way back to a working database.
void _abandonCurrentStore() {
  final abandoned = _dbName();
  final next = _generation() + 1;
  _generationFallback = next;
  _writeLocal(_kGenerationKey, '$next');
  final orphans = [..._orphans(), abandoned];
  _writeLocal(
    _kOrphansKey,
    orphans
        .sublist(
          orphans.length > _kMaxOrphans ? orphans.length - _kMaxOrphans : 0,
        )
        .join(','),
  );
  _log.warning(
    'Could not delete web database store "$abandoned"; abandoning it and '
    'opening generation $next instead. It is swept on a later load.',
  );
}

/// The abandoned stores, swept once per page load **off the boot path**.
///
/// [openDatabaseExecutor] takes the candidates before anything in this page
/// has opened a store: IndexedDB's `deleteDatabase` blocks while any
/// connection is open, and drift's shared worker releases a handle this page
/// opened asynchronously, several message-port hops after `close()` resolved,
/// with no signal back. So a store this load abandons waits for the next one;
/// a store abandoned on an earlier load has no handle from this page.
///
/// The deletes themselves run from `main.dart` once the first frame is up
/// ([sweepAbandonedStores]). Awaiting them in the open cost about a second a
/// store whenever the browser still held one (sqlite3's own bound on
/// `deleteDatabase`), up to [_kMaxOrphans] seconds of boot. Gated on the
/// orphan list being non-empty, so a normal load spawns nothing.
final _orphanSweep = OrphanStoreSweep(
  readOrphans: _orphans,
  writeOrphans: (names) => _writeLocal(_kOrphansKey, names.join(',')),
  liveName: _dbName,
  deleteStore: _deleteStore,
);

/// Delete the stores earlier loads abandoned. Never throws, runs once per
/// load; `main.dart` starts it after the first frame and never awaits it.
Future<OrphanSweepOutcome> sweepAbandonedStores() => _orphanSweep.run();

/// Web executor: drift WASM over the best available browser storage
/// (OPFS where headers allow it, otherwise IndexedDB). No encryption and
/// no `PRAGMA key` — the browser origin sandbox is the trust boundary.
Future<QueryExecutor> openDatabaseExecutor() async {
  _orphanSweep.snapshot();
  final result = await WasmDatabase.open(
    databaseName: _dbName(),
    sqlite3Uri: _sqlite3Uri,
    driftWorkerUri: _driftWorkerUri,
  ).timeout(_kOpenTimeout);
  if (result.missingFeatures.isNotEmpty) {
    // Surfaced so a future Claude session / the developer can see why
    // persistence degraded (e.g. unsafeIndexedDb / inMemory) instead of
    // silently losing data on reload.
    _log.warning(
      'Web DB missing browser features: ${result.missingFeatures}; '
      'storage=${result.chosenImplementation}',
    );
  }
  return result.resolvedExecutor;
}

/// Web recovery: get the caller a clean store, whatever the browser allows.
///
/// Deleting the current store is attempted first; if the browser refuses, the
/// store is **abandoned** and the generation bumped so the next
/// [openDatabaseExecutor] opens an empty one. Either way the next open is
/// clean, which is what the caller is actually asking for.
///
/// Returns whether that guarantee holds. `false` means even abandoning failed,
/// so the caller must not claim the data was reset.
///
/// Known gap: this deletes from IndexedDB, so on an origin that qualifies for
/// OPFS (cross-origin isolated, which the demo's host is not) the delete is a
/// no-op that reports success. `openAppDatabase()` re-checks the reopened
/// database and surfaces an error screen rather than running on a store it
/// failed to clear, so the failure mode there is honest, not silent.
Future<bool> destroyDatabaseStore() async {
  final target = _dbName();
  if (await _deleteStore(target)) return true;
  _abandonCurrentStore();
  return _dbName() != target;
}

/// `localStorage` key naming the store found corrupt after it opened
/// (`StoreCorruptionWatch`). It holds the store's *name*, so a mark naming a
/// store since abandoned — a later generation is live — is stale by
/// construction.
const _kCorruptKey = 'invoiceninja.db.corrupt.v1';

/// Mark the live store for repair at the next open. Returns whether the mark
/// can be read back: with `localStorage` unwritable (private mode, blocked
/// site data) the next load would never see it, and a reload to repair would
/// only find the same store again.
Future<bool> markStoreCorrupt() async {
  final name = _dbName();
  try {
    web.window.localStorage.setItem(_kCorruptKey, name);
  } catch (e) {
    _log.warning('Could not mark web database store "$name" corrupt: $e');
    return false;
  }
  return _readLocal(_kCorruptKey) == name;
}

/// Whether the store the next [openDatabaseExecutor] opens was marked by
/// [markStoreCorrupt]. A mark naming another store is dropped.
Future<bool> storeMarkedCorrupt() async {
  final marked = _readLocal(_kCorruptKey);
  if (marked == null || marked.isEmpty) return false;
  if (marked == _dbName()) return true;
  await clearStoreCorruptMark();
  return false;
}

/// Take the mark [markStoreCorrupt] left.
Future<void> clearStoreCorruptMark() async {
  try {
    web.window.localStorage.removeItem(_kCorruptKey);
  } catch (_) {
    // Unwritable storage never held a mark either.
  }
}

/// Web half of the salvage seam: not yet implemented, so a reset on web
/// still loses unsynced work — `openAppDatabase` reports no recovery (null)
/// rather than claiming one. Reading an abandoned IndexedDB store raw needs
/// drift's on-disk layout inside the `IndexedDbFileSystem` and a browser to
/// test it in.
Future<QuarantinedStore?> readQuarantinedStore() async => null;

/// Web half of [requeueSalvage]: there is no salvage to put off.
Future<bool> requeueSalvage(QuarantinedStore store) async => false;

/// Web half of [readQuarantinedStore]'s retention: nothing to rename.
Future<String> retainQuarantinedStore(String source) async => source;

/// Web keeps no old copies: an abandoned store is swept on a later load, and
/// nothing reads it before then.
Future<List<RetainedStore>> listRetainedStores() async => const [];

/// Web half of [listRetainedStores]: there is nothing to delete.
Future<void> deleteRetainedStore(String path) async {}
