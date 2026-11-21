import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:drift/drift.dart' show Value;
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/sync/mutation.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/repositories/saved_views_sync.dart';
import 'package:admin/domain/appearance_sync.dart';

final _log = Logger('UserSettingsRepository');

/// `entity_type` value used in the outbox row for user settings updates.
/// `EntityRegistry` routes rows with this wire name to the
/// `UserSettingsSyncDispatcher`.
const String kUserSettingsWireName = kUserSettingsEntityType;

/// `entity_type` of the outbox rows an earlier build queued to write
/// `company_user.react_settings`. Nothing queues one any more — this app
/// keeps nothing in React's blob (`docs/user-settings-storage.md`) — but a row
/// already waiting on a device still routes here, and is moved, not sent.
const String kUserPreferencesWireName = 'user_preferences';

/// Read/write per-(user, company) settings: `company_user.settings`, the
/// object the previous Flutter app keeps its preferences in and the only
/// place this app stores a synced preference.
///
/// `table_columns` is byte-compatible with the old admin-portal's — same map
/// key format (`'$EntityType.<entity>'`) and same snake_case column-id values
/// — so a list customised in either app shows up in the other. Everything
/// else this app adds lives under a `flutter_`-prefixed key ([patchSettings]).
class UserSettingsRepository {
  UserSettingsRepository({
    required this.db,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
    this.onEnqueued,
  }) : _uuid = uuid,
       _now = now ?? DateTime.now;

  final AppDatabase db;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Fire-and-forget hook invoked after an outbox row is written. Wired by
  /// DI to `SyncRepository.drainOnce` so settings updates drain immediately
  /// when online. Same contract as [BaseEntityRepository.onEnqueued].
  final void Function(String companyId)? onEnqueued;

  /// Watch the column id list for [entityType] in [companyId]. Emits the
  /// stored list (possibly empty) — callers fall back to a default list when
  /// nothing has been customised yet.
  Stream<List<String>?> watchColumns({
    required String companyId,
    required EntityType entityType,
  }) {
    final key = _tableColumnsKey(entityType);
    return db.userSettingsDao.watch(companyId).map((row) {
      if (row == null) return null;
      return _extractColumns(row.tableColumnsJson, key);
    });
  }

  Future<List<String>?> getColumns({
    required String companyId,
    required EntityType entityType,
  }) async {
    final row = await db.userSettingsDao.get(companyId);
    if (row == null) return null;
    return _extractColumns(row.tableColumnsJson, _tableColumnsKey(entityType));
  }

  /// Persist the column list locally (so the UI reacts immediately) and
  /// enqueue an outbox row for the server PUT.
  ///
  /// If a pending (non-in-flight) outbox row already exists for this
  /// `(companyId, user_settings)` pair, replace its payload instead of
  /// queueing a second one — settings updates are idempotent and the
  /// outbox should not pile up duplicates while the user is rapidly
  /// toggling columns.
  ///
  /// The read of the stored columns is inside the write's transaction: two
  /// quick toggles read the same row outside it, and the second write lost
  /// the first's change. The drain is kicked after the commit.
  Future<void> setColumns({
    required String companyId,
    required EntityType entityType,
    required List<String> columns,
  }) async {
    final queued = await db.transaction(() async {
      final existing = await db.userSettingsDao.get(companyId);
      if (existing == null) {
        _log.warning(
          'setColumns called before settings hydrated for $companyId; '
          'skipping.',
        );
        return false;
      }

      final key = _tableColumnsKey(entityType);
      final tableColumns = _decodeTableColumns(existing.tableColumnsJson);
      // Idempotent: bail before any local write or outbox enqueue when the
      // column list is unchanged. Without this, applying a saved view (whose
      // snapshot captured the current columns) — or the column picker
      // re-selecting the same set — pushes a no-op `user_settings` PUT into
      // the outbox.
      if (_sameColumns(tableColumns[key], columns)) return false;
      tableColumns[key] = columns;
      await _writeColumnsAndEnqueue(companyId, existing, tableColumns, {
        key: columns,
      });
      return true;
    });
    if (queued) onEnqueued?.call(companyId);
  }

  /// Restore the default column list (i.e. drop the entry from
  /// `table_columns` so the UI falls back to the registry default).
  Future<void> resetColumns({
    required String companyId,
    required EntityType entityType,
  }) async {
    final queued = await db.transaction(() async {
      final existing = await db.userSettingsDao.get(companyId);
      if (existing == null) return false;
      final key = _tableColumnsKey(entityType);
      final tableColumns = _decodeTableColumns(existing.tableColumnsJson)
        ..remove(key);
      await _writeColumnsAndEnqueue(companyId, existing, tableColumns, {
        key: null,
      });
      return true;
    });
    if (queued) onEnqueued?.call(companyId);
  }

  /// Write [tableColumns] locally and queue (or collapse into) the change
  /// that carries [changed]. Inside the caller's transaction.
  Future<void> _writeColumnsAndEnqueue(
    String companyId,
    UserSettingsRow existing,
    Map<String, List<String>> tableColumns,
    Map<String, List<String>?> changed,
  ) async {
    final nowMs = _now().millisecondsSinceEpoch;
    await db.userSettingsDao.writeTableColumns(
      companyId: companyId,
      tableColumnsJson: jsonEncode(tableColumns),
      now: nowMs,
    );
    await _enqueueOrCollapse(
      companyId: companyId,
      userId: existing.userId,
      change: UserSettingsChange(columns: changed),
      nowMs: nowMs,
    );
  }

  /// Watch `company_user.settings` for [companyId], without `table_columns`.
  /// Emits null until a login has stored the row.
  Stream<Map<String, dynamic>?> watchSettings(String companyId) => db
      .userSettingsDao
      .watch(companyId)
      .map((row) => row == null ? null : _decodeAny(row.extraJson))
      .distinct(const DeepCollectionEquality().equals);

  /// Every company's `company_user.settings` (without `table_columns`) that
  /// belongs to [userId], by company id. A row a login stored for another
  /// identity is left out.
  Stream<Map<String, Map<String, dynamic>>> watchAllSettings({
    required String userId,
  }) => db.userSettingsDao
      .watchAll()
      .map(
        (rows) => {
          for (final row in rows)
            if (row.userId == userId) row.companyId: _decodeAny(row.extraJson),
        },
      )
      .distinct(const DeepCollectionEquality().equals);

  Future<Map<String, dynamic>?> getSettings(String companyId) async {
    final row = await db.userSettingsDao.get(companyId);
    return row == null ? null : _decodeAny(row.extraJson);
  }

  /// Set each dotted path in [patch] (`'flutter_dashboard.panels'`) in
  /// `company_user.settings`, locally at once and on the server through the
  /// outbox. Returns whether anything changed. A null value removes its key.
  ///
  /// **Every key this app adds is `flutter_`-prefixed** (asserted): the object
  /// is shared with the previous Flutter app, and the prefix is what keeps
  /// this app's keys from meeting one of its fields.
  ///
  /// The server *replaces* the object, so the outbox row carries only the
  /// change: the dispatcher lays it over the freshest local copy when it
  /// sends ([putBodyFor]), and a login or `/refresh` that lands meanwhile lays
  /// it over the server's ([applyServerSettings]). Rapid changes collapse into
  /// the one pending row. A no-op before a login has stored the row.
  Future<bool> patchSettings({
    required String companyId,
    required Map<String, Object?> patch,
  }) async {
    assert(
      patch.keys.every((k) => k.startsWith(kAppSettingsKeyPrefix)),
      'company_user.settings keys written by this app start with '
      '"$kAppSettingsKeyPrefix": ${patch.keys}',
    );
    final queued = await db.transaction(() async {
      final row = await db.userSettingsDao.get(companyId);
      if (row == null) {
        _log.fine('patchSettings before settings hydrated for $companyId.');
        return false;
      }
      final current = _decodeAny(row.extraJson);
      final next = applySettingsPatch(current, patch);
      if (const DeepCollectionEquality().equals(current, next)) return false;
      final nowMs = _now().millisecondsSinceEpoch;
      await db.userSettingsDao.writeExtra(
        companyId: companyId,
        extraJson: jsonEncode(next),
        now: nowMs,
      );
      await _enqueueOrCollapse(
        companyId: companyId,
        userId: row.userId,
        change: UserSettingsChange(patch: patch),
        nowMs: nowMs,
      );
      return true;
    });
    if (queued) onEnqueued?.call(companyId);
    return queued;
  }

  /// The PUT body for [change]: the freshest local settings with the change
  /// laid over them. Null when the settings row is gone (the cache table was
  /// dropped after the change was queued) — sending the change over nothing
  /// would wipe every other setting.
  ///
  /// A non-admin's body also carries `notifications`: the server's non-admin
  /// branch reads that key unguarded (`CompanyUserController::update`), so a
  /// body without it is a 500. It is sent only when the login captured it.
  Future<Map<String, dynamic>?> putBodyFor({
    required String companyId,
    required UserSettingsChange change,
  }) async {
    final row = await db.userSettingsDao.get(companyId);
    if (row == null) return null;
    final settings = <String, dynamic>{
      ...applySettingsPatch(_decodeAny(row.extraJson), change.patch),
      'table_columns': _applyColumns(
        _decodeTableColumns(row.tableColumnsJson),
        change.columns,
      ),
    };
    Map<String, dynamic>? notifications;
    final company = await db.companiesDao.byId(companyId);
    if (company != null && !company.isAdmin) {
      final user = await db.userDao.getByCompanyAndId(
        companyId: companyId,
        id: row.userId,
      );
      final payload = user == null ? null : _decodeAny(user.payload);
      final companyUser = payload?['company_user'];
      final raw = companyUser is Map ? companyUser['notifications'] : null;
      if (raw is Map<String, dynamic>) notifications = raw;
    }
    return <String, dynamic>{
      'id': row.userId,
      'company_user': <String, dynamic>{
        'settings': settings,
        'notifications': ?notifications,
      },
    };
  }

  /// [settings] — the `company_user.settings` a profile save (`PUT
  /// /users/{id}`) is about to send for [userId] — with this app's `flutter_`
  /// keys and `table_columns` taken from the freshest local copy.
  ///
  /// That save replaces the whole object too, from a body built when the
  /// profile was edited: without this it puts back the dashboard and column
  /// choices as they stood then. Returned untouched for any user but this
  /// company's signed-in one.
  Future<Map<String, dynamic>> withFreshAppKeys({
    required String companyId,
    required String userId,
    required Map<String, dynamic> settings,
  }) async {
    final row = await db.userSettingsDao.get(companyId);
    if (row == null || row.userId != userId) return settings;
    return <String, dynamic>{
      for (final e in settings.entries)
        if (!e.key.startsWith(kAppSettingsKeyPrefix)) e.key: e.value,
      for (final e in _decodeAny(row.extraJson).entries)
        if (e.key.startsWith(kAppSettingsKeyPrefix)) e.key: e.value,
      'table_columns': _decodeTableColumns(row.tableColumnsJson),
    };
  }

  /// Store the `company_user.settings` a profile save's reply carried for
  /// [userId], so the next settings PUT does not send the accent colour (or
  /// any other key that save changed) as it stood before. A no-op for any
  /// user but this company's signed-in one.
  Future<void> applyProfileSaveSettings({
    required String companyId,
    required String userId,
    required Map<String, dynamic> settings,
  }) async {
    // The save always sends `table_columns`, so an empty object back is a
    // reply that did not carry the settings — never the settings themselves.
    if (settings.isEmpty) return;
    final row = await db.userSettingsDao.get(companyId);
    if (row == null || row.userId != userId) return;
    await applyServerSettings(
      db,
      companyId: companyId,
      userId: userId,
      settings: settings,
      nowMs: _now().millisecondsSinceEpoch,
    );
  }

  /// Server replied to our PUT with the canonical UserCompany shape — write
  /// it back so the local cache matches.
  Future<void> applyServerResponse({
    required String companyId,
    required Map<String, dynamic> response,
  }) async {
    final data = response['data'];
    if (data is! Map<String, dynamic>) return;
    final settings = data['settings'];
    if (settings is! Map<String, dynamic>) return;
    final user = data['user'];
    var userId = user is Map<String, dynamic>
        ? (user['id']?.toString() ?? '')
        : '';
    // The PUT /user response doesn't always echo the `user` block. `user_id`
    // is a required column, and `upsert` runs through `insertOnConflictUpdate`
    // which validates insert integrity even when the row already exists — an
    // absent userId throws InvalidDataException and parks the sync drain. Fall
    // back to the userId already persisted locally (written at login from
    // `data[N].user`); it's stable for the (user, company) pair.
    if (userId.isEmpty) {
      userId = (await db.userSettingsDao.get(companyId))?.userId ?? '';
    }
    if (userId.isEmpty) {
      _log.warning(
        'Skipping user_settings write for $companyId: no userId in server '
        'response and no local row to fall back to',
      );
      return;
    }
    await applyServerSettings(
      db,
      companyId: companyId,
      userId: userId,
      settings: settings,
      nowMs: _now().millisecondsSinceEpoch,
      // The reply to a full-body row an earlier build queued is that row's
      // own answer, so it is stored.
      deferToFullBodyRows: false,
    );
  }

  /// Queue [change], or fold it into the pending row. A pending row an
  /// earlier build queued holds a whole body rather than a change, so it is
  /// left alone and this one queues behind it.
  Future<void> _enqueueOrCollapse({
    required String companyId,
    required String userId,
    required UserSettingsChange change,
    required int nowMs,
  }) => enqueueUserSettingsChange(
    db,
    companyId: companyId,
    userId: userId,
    change: change,
    nowMs: nowMs,
    uuid: _uuid,
  );

  /// Old admin-portal uses `'$EntityType.client'` (the literal Dart enum
  /// toString) as the map key — must preserve that exactly.
  String _tableColumnsKey(EntityType entityType) =>
      'EntityType.${entityType.name}';

  /// Order-sensitive equality for two column-id lists. A missing stored
  /// list (`null`) only matches an empty incoming list.
  bool _sameColumns(List<String>? a, List<String> b) {
    final current = a ?? const <String>[];
    if (current.length != b.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (current[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, List<String>> _decodeTableColumns(String raw) {
    if (raw.isEmpty) return <String, List<String>>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, List<String>>{};
    final out = <String, List<String>>{};
    for (final entry in decoded.entries) {
      final v = entry.value;
      if (v is List) {
        out[entry.key.toString()] = v.map((e) => e.toString()).toList();
      }
    }
    return out;
  }

  Map<String, dynamic> _decodeAny(String raw) {
    if (raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  List<String>? _extractColumns(String raw, String key) {
    final map = _decodeTableColumns(raw);
    return map[key];
  }
}

/// The prefix of every `company_user.settings` key this app adds. The object
/// belongs to the previous Flutter app too; `react_settings` belongs to the
/// React client and is never written (`docs/user-settings-storage.md`).
const String kAppSettingsKeyPrefix = 'flutter_';

/// The settings keys the device holds a copy of and pushes to each company
/// as it becomes active, so a queued write of them alone is re-derivable
/// rather than the user's unsynced work (`UserSettingsChange.isDeviceDerived`).
const Set<String> kDeviceDerivedSettingsKeys = {kAppearanceSettingsKey};

/// What one `user_settings` outbox row changes: dotted paths into the
/// settings object ([patch], a null value removes the key) and whole
/// `table_columns` entries ([columns], null removes one — their keys contain
/// dots, so they cannot be paths).
class UserSettingsChange {
  const UserSettingsChange({this.patch = const {}, this.columns = const {}});

  final Map<String, Object?> patch;
  final Map<String, List<String>?> columns;

  UserSettingsChange merge(UserSettingsChange later) => UserSettingsChange(
    patch: {...patch, ...later.patch},
    columns: {...columns, ...later.columns},
  );

  /// Whether this change writes only keys the device holds and re-derives
  /// ([kDeviceDerivedSettingsKeys]) — no columns, and every patched path under
  /// one of them. Its row is then no unsynced work of the user's
  /// ([isDeviceDerivedSettingsRow]).
  bool get isDeviceDerived =>
      columns.isEmpty &&
      patch.isNotEmpty &&
      patch.keys.every(
        (k) => kDeviceDerivedSettingsKeys.contains(k.split('.').first),
      );

  /// The stored payload. A [isDeviceDerived] change carries
  /// [kDeviceDerivedSettingsJson], recomputed on every encode, so a merge
  /// that adds any other key drops it.
  String encode() => jsonEncode({
    'patch': patch,
    'columns': columns,
    if (isDeviceDerived) 'device_derived': true,
  });

  /// The change [payload] carries, or null for a row an earlier build queued,
  /// whose payload is the whole PUT body (`company_user`).
  static UserSettingsChange? tryDecode(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded.containsKey('company_user')) return null;
      final patch = decoded['patch'];
      final columns = decoded['columns'];
      if (patch is! Map && columns is! Map) return null;
      return UserSettingsChange(
        patch: patch is Map<String, dynamic> ? patch : const {},
        columns: {
          if (columns is Map)
            for (final e in columns.entries)
              e.key.toString(): e.value is List
                  ? [for (final c in e.value as List) c.toString()]
                  : null,
        },
      );
    } on FormatException {
      return null;
    }
  }
}

/// Queue [change], or fold it into the pending row. A pending row an earlier
/// build queued holds a whole body rather than a change, so it is left alone
/// and this one queues behind it.
Future<void> enqueueUserSettingsChange(
  AppDatabase db, {
  required String companyId,
  required String userId,
  required UserSettingsChange change,
  required int nowMs,
  Uuid uuid = const Uuid(),
}) async {
  final existing = await db.outboxDao.findPending(
    companyId: companyId,
    entityType: kUserSettingsWireName,
  );
  final waiting = existing == null
      ? null
      : UserSettingsChange.tryDecode(existing.payload);
  if (existing != null &&
      waiting != null &&
      await db.outboxDao.updatePayload(
        id: existing.id,
        payload: waiting.merge(change).encode(),
      )) {
    return;
  }
  await db.outboxDao.enqueue(
    OutboxCompanion.insert(
      companyId: companyId,
      entityType: kUserSettingsWireName,
      entityId: userId,
      mutationKind: MutationKind.update.wireName,
      payload: change.encode(),
      idempotencyKey: uuid.v4(),
      nextAttemptAt: nowMs,
      createdAt: nowMs,
    ),
  );
}

Map<String, List<String>> _applyColumns(
  Map<String, List<String>> base,
  Map<String, List<String>?> changed,
) {
  final out = Map<String, List<String>>.from(base);
  for (final MapEntry(:key, :value) in changed.entries) {
    value == null ? out.remove(key) : out[key] = value;
  }
  return out;
}

/// Store the server's `company_user.settings` for [companyId] (a login, a
/// `/refresh`, or a PUT's reply), with every change still waiting in the
/// outbox laid over it in queue order — a change the server hasn't taken yet
/// must not visually revert, and the rest of the object must not go stale
/// behind it.
///
/// [deferToFullBodyRows]: a waiting row an earlier build queued carries a
/// whole body, which cannot be laid over anything, so while one waits the
/// local copy is left as it is — the contract that row was queued under.
///
/// [pushLocal]: whether saved views this device has newer, or the server
/// lacks, are queued back up. A login or first `/refresh` answers for every
/// company, but the outbox drains only the active one's rows, so a push for
/// any other company would sit there as "unsynced changes" until the user
/// happened to switch to it — and block a sign-out meanwhile. Those companies
/// only adopt the server's copy; their push happens on the refresh that runs
/// once they are active.
Future<void> applyServerSettings(
  AppDatabase db, {
  required String companyId,
  required String userId,
  required Map<String, dynamic> settings,
  required int nowMs,
  bool deferToFullBodyRows = true,
  bool pushLocal = true,
}) async {
  final waiting = await db.outboxDao.activeRowsFor(
    companyId: companyId,
    entityType: kUserSettingsWireName,
  );
  final changes = [
    for (final row in waiting) UserSettingsChange.tryDecode(row.payload),
  ];
  if (deferToFullBodyRows && changes.contains(null)) return;
  final rawColumns = settings['table_columns'];
  var columns = <String, List<String>>{
    if (rawColumns is Map)
      for (final e in rawColumns.entries)
        if (e.value is List)
          e.key.toString(): [for (final c in e.value as List) c.toString()],
  };
  var extra = Map<String, dynamic>.from(settings)..remove('table_columns');
  for (final change in changes.nonNulls) {
    extra = applySettingsPatch(extra, change.patch);
    columns = _applyColumns(columns, change.columns);
  }
  await db.transaction(() async {
    // Saved views (invoiceninja/app#198): merged, never adopted whole — other
    // clients write this object back from stale copies (`saved_views_sync`).
    // What this device has that the server lacks goes back up — for the
    // active company only ([pushLocal]).
    final reconciled = await reconcileSavedViews(
      db,
      companyId: companyId,
      settings: extra,
    );
    final push = pushLocal ? reconciled : const <String, Object?>{};
    if (push.isNotEmpty) extra = applySettingsPatch(extra, push);
    await db.userSettingsDao.upsert(
      UserSettingsCompanion(
        companyId: Value(companyId),
        userId: Value(userId),
        tableColumnsJson: Value(jsonEncode(columns)),
        extraJson: Value(jsonEncode(extra)),
        updatedAt: Value(nowMs),
      ),
    );
    if (push.isNotEmpty) {
      await enqueueUserSettingsChange(
        db,
        companyId: companyId,
        userId: userId,
        change: UserSettingsChange(patch: push),
        nowMs: nowMs,
      );
    }
  });
}

/// A deep copy of [base] with each dotted path in [patch] set; a null value
/// removes its key. A non-map met on the way is replaced by a map.
Map<String, dynamic> applySettingsPatch(
  Map<String, dynamic> base,
  Map<String, Object?> patch,
) {
  final out = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in patch.entries) {
    final segments = key.split('.');
    var node = out;
    for (final segment in segments.take(segments.length - 1)) {
      final child = node[segment];
      if (child is Map<String, dynamic>) {
        node = child;
      } else {
        node = node[segment] = <String, dynamic>{};
      }
    }
    if (value == null) {
      node.remove(segments.last);
    } else {
      node[segments.last] = jsonDecode(jsonEncode(value));
    }
  }
  return out;
}

/// The patch a [kUserPreferencesWireName] row an earlier build queued carries.
Map<String, Object?> legacyReactSettingsPatchOf(String payload) {
  try {
    final decoded = jsonDecode(payload);
    final patch = decoded is Map ? decoded['patch'] : null;
    if (patch is Map<String, dynamic>) return patch;
  } on FormatException {
    // Fall through.
  }
  return const {};
}
