import 'dart:convert';

import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:drift/drift.dart' show Value;
import 'package:logging/logging.dart';

import 'package:admin/data/db/app_database.dart';

final _log = Logger('SavedViewsSync');

/// The `company_user.settings` key saved views sync under
/// (invoiceninja/app#198): `{<view id>: <entry>}`, one entry per view —
/// entity and report views alike — so each edit patches only its own path
/// (`flutter_saved_views.<id>`). Never `react_settings`
/// (`docs/user-settings-storage.md`).
///
/// The `saved_views` table is this device's copy: a deliberate sign-out wipes
/// it, and the next login restores it from here.
const String kSavedViewsSettingsKey = 'flutter_saved_views';

/// How long a delete's tombstone stays in `flutter_saved_views`: long enough
/// for every device the user signs in on to see it, short enough that the
/// object does not grow without bound.
const Duration kSavedViewTombstoneTtl = Duration(days: 90);

/// The settings path of one view's entry.
String savedViewSettingsPath(String viewId) =>
    '$kSavedViewsSettingsKey.$viewId';

/// [row] as its `flutter_saved_views` entry. The payload goes up decoded, so
/// the stored object stays readable JSON rather than a string in a string.
Map<String, Object?> savedViewSettingsEntry(SavedViewRow row) {
  Object? payload;
  try {
    payload = jsonDecode(row.payloadJson);
  } on FormatException {
    payload = row.payloadJson;
  }
  return <String, Object?>{
    'entity_type': row.entityType,
    'name': row.name,
    'icon': ?row.icon,
    'payload': payload,
    'created_at': row.createdAt,
    'updated_at': row.updatedAt,
  };
}

/// The entry a delete leaves behind. Without it a view missing from the
/// server's copy could not be told apart from one a stale write dropped.
Map<String, Object?> savedViewTombstone(int nowMs) => <String, Object?>{
  'deleted': true,
  'updated_at': nowMs,
};

/// The patch that removes every tombstone in [settings] older than
/// [kSavedViewTombstoneTtl] — sent along with a delete's own.
Map<String, Object?> expiredSavedViewTombstones(
  Map<String, dynamic> settings,
  int nowMs,
) {
  final raw = settings[kSavedViewsSettingsKey];
  if (raw is! Map) return const {};
  final cutoff = nowMs - kSavedViewTombstoneTtl.inMilliseconds;
  return <String, Object?>{
    for (final MapEntry(:key, :value) in raw.entries)
      if (_isTombstone(value) && _intOf((value as Map)['updated_at']) < cutoff)
        savedViewSettingsPath(key.toString()): null,
  };
}

/// Merge `flutter_saved_views` in [settings] — the server's copy with every
/// waiting change laid over it — with [companyId]'s `saved_views` rows.
/// Drift takes what the server has newer; the returned patch carries what
/// this device has newer, or what the server lacks, back up.
///
/// A merge, never a replace, because the object is written whole by other
/// clients from copies they loaded earlier: React's User Details save sends
/// back `company_user.settings` as it stood when the page loaded, and the old
/// Flutter app sends only the fields it models. Either drops a view made
/// since, and adopting that as the list would delete it here too. A delete
/// travels as a tombstone ([savedViewTombstone]) for the same reason.
///
/// Newest `updated_at` wins; on a tie the server's copy does. An entry this
/// build cannot read is left alone on both sides.
Future<Map<String, Object?>> reconcileSavedViews(
  AppDatabase db, {
  required String companyId,
  required Map<String, dynamic> settings,
}) async {
  final raw = settings[kSavedViewsSettingsKey];
  final server = raw is Map ? raw : const <String, Object?>{};
  final push = <String, Object?>{};
  await db.transaction(() async {
    final local = {
      for (final row in await db.savedViewsDao.allForCompany(companyId))
        row.id: row,
    };
    for (final MapEntry(:key, :value) in server.entries) {
      final id = key.toString();
      if (!_isValidId(id)) continue;
      final mine = local[id];
      if (_isTombstone(value)) {
        if (mine == null) continue;
        if (mine.updatedAt > _intOf((value as Map)['updated_at'])) {
          push[savedViewSettingsPath(id)] = savedViewSettingsEntry(mine);
        } else {
          await db.savedViewsDao.deleteById(id);
        }
        continue;
      }
      final theirs = _rowFromEntry(companyId, id, value);
      if (theirs == null) {
        _log.fine('Skipping unreadable saved view entry $id');
        continue;
      }
      if (mine == null) {
        await db.savedViewsDao.upsertView(theirs);
      } else if (mine.updatedAt > theirs.updatedAt.value) {
        push[savedViewSettingsPath(id)] = savedViewSettingsEntry(mine);
      } else if (!_same(mine, theirs)) {
        await db.savedViewsDao.upsertView(theirs);
      }
    }
    for (final row in local.values) {
      if (!server.containsKey(row.id)) {
        push[savedViewSettingsPath(row.id)] = savedViewSettingsEntry(row);
      }
    }
  });
  return push;
}

bool _isValidId(String id) => id.isNotEmpty && !id.contains('.');

bool _isTombstone(Object? entry) => entry is Map && entry['deleted'] == true;

SavedViewsCompanion? _rowFromEntry(String companyId, String id, Object? entry) {
  if (entry is! Map) return null;
  final entityType = entry['entity_type'];
  final name = entry['name'];
  final payload = entry['payload'];
  final icon = entry['icon'];
  if (entityType is! String || entityType.isEmpty || name is! String) {
    return null;
  }
  final String payloadJson;
  if (payload is Map) {
    payloadJson = jsonEncode(payload);
  } else if (payload is String) {
    payloadJson = payload;
  } else {
    return null;
  }
  final createdAt = _intOf(entry['created_at']);
  final updatedAt = _intOf(entry['updated_at']);
  return SavedViewsCompanion(
    id: Value(id),
    companyId: Value(companyId),
    entityType: Value(entityType),
    name: Value(name),
    payloadJson: Value(payloadJson),
    icon: Value(icon is String && icon.isNotEmpty ? icon : null),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt == 0 ? createdAt : updatedAt),
  );
}

int _intOf(Object? v) => switch (v) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

bool _same(SavedViewRow row, SavedViewsCompanion next) {
  if (row.entityType != next.entityType.value ||
      row.name != next.name.value ||
      row.icon != next.icon.value ||
      row.createdAt != next.createdAt.value ||
      row.updatedAt != next.updatedAt.value) {
    return false;
  }
  try {
    return const DeepCollectionEquality().equals(
      jsonDecode(row.payloadJson),
      jsonDecode(next.payloadJson.value),
    );
  } on FormatException {
    return row.payloadJson == next.payloadJson.value;
  }
}
