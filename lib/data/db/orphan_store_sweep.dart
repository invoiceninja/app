import 'package:logging/logging.dart';

import 'package:admin/utils/perf_trace.dart';

final _log = Logger('AppDatabase');

/// What one [OrphanStoreSweep.run] did. [attempted] is zero on an ordinary
/// load (nothing abandoned) and on every native one.
typedef OrphanSweepOutcome = ({int attempted, int swept, int remaining});

const OrphanSweepOutcome kNoOrphanSweep = (
  attempted: 0,
  swept: 0,
  remaining: 0,
);

/// Deletes the web database generations earlier resets abandoned
/// (`invoiceninja_gN`), **off the boot path**.
///
/// Platform-free so it can be tested on the VM: `database_opener_web.dart`
/// hands it `localStorage` and `IndexedDbFileSystem.deleteDatabase`.
///
/// The deletes used to be awaited at the top of the first open, and a store
/// the browser will not release (drift's shared worker, which outlives a
/// reload, still holding it) makes each one wait out sqlite3's own 1 s bound
/// — up to 8 s of boot for nothing the first frame needs. Now:
///
/// - [snapshot] runs in the first open, synchronously, before anything is
///   opened. It fixes this load's candidates: the stores abandoned on an
///   *earlier* load. One this load abandons is held by this page and would
///   only time out, so it waits for the next load.
/// - [run] is started by `main.dart` once the first frame is up, never
///   awaited by boot, and runs once per load.
///
/// Safe against a reset or a sign-out mid-run: the live store is checked
/// before every delete and never touched, and the orphan list is re-read
/// when the run ends, so a store abandoned meanwhile is kept, not overwritten.
/// A sign-out wipes rows, never a store, and nothing here reads the rows.
class OrphanStoreSweep {
  OrphanStoreSweep({
    required List<String> Function() readOrphans,
    required void Function(List<String> names) writeOrphans,
    required String Function() liveName,
    required Future<bool> Function(String name) deleteStore,
  }) : _readOrphans = readOrphans,
       _writeOrphans = writeOrphans,
       _liveName = liveName,
       _deleteStore = deleteStore;

  final List<String> Function() _readOrphans;
  final void Function(List<String> names) _writeOrphans;
  final String Function() _liveName;
  final Future<bool> Function(String name) _deleteStore;

  List<String>? _candidates;
  Future<OrphanSweepOutcome>? _run;

  /// Fix this load's candidates. The first call wins: a reset's reopen calls
  /// the open again, after it may have abandoned the store this page held.
  void snapshot() {
    if (_candidates != null) return;
    try {
      _candidates = List.unmodifiable(_readOrphans());
    } catch (e) {
      _log.warning('Reading abandoned web database stores failed: $e');
      _candidates = const [];
    }
  }

  /// Delete the candidates. Runs once per load (a second call gets the first
  /// call's future) and never throws.
  Future<OrphanSweepOutcome> run() => _run ??= _sweep();

  Future<OrphanSweepOutcome> _sweep() async {
    snapshot();
    final candidates = _candidates!;
    if (candidates.isEmpty) return kNoOrphanSweep;
    try {
      return await traceAsync(
        'db.orphanSweep',
        () => _deleteAll(candidates),
        args: {'stores': candidates.length},
      );
    } catch (e, st) {
      _log.warning('Sweeping abandoned web database stores failed', e, st);
      return (
        attempted: candidates.length,
        swept: 0,
        remaining: candidates.length,
      );
    }
  }

  Future<OrphanSweepOutcome> _deleteAll(List<String> candidates) async {
    final gone = <String>{};
    for (final name in candidates) {
      // Checked per store, not once: a reset during the run moves the live
      // generation. Generations only climb, so this is belt and braces — but
      // deleting the live store is the one outcome this must never have.
      if (name == _liveName()) {
        _log.warning(
          'Abandoned web database store "$name" is the live one; not '
          'deleting it.',
        );
        continue;
      }
      try {
        if (await _deleteStore(name)) {
          gone.add(name);
          _log.info('Swept abandoned web database store "$name"');
        }
      } catch (e) {
        _log.warning('Deleting web database store "$name" failed: $e');
      }
    }
    // Re-read, never write back the snapshot: a reset during the run may have
    // abandoned another store, and the next load has to find it.
    final live = _liveName();
    final current = _readOrphans();
    final next = [
      for (final name in current)
        if (!gone.contains(name) && name != live) name,
    ];
    if (next.length != current.length) _writeOrphans(next);
    return (
      attempted: candidates.length,
      swept: gone.length,
      remaining: next.length,
    );
  }
}
