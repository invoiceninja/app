import 'dart:convert';

import 'package:logging/logging.dart';

import 'package:admin/domain/sync/mutation.dart';
import 'package:admin/domain/sync/sync_dispatcher.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/services/user_settings_api.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';

final _log = Logger('UserSettingsSyncDispatcher');

/// Drains `user_settings` outbox rows by PUTting them to
/// `/api/v1/company_users/{userId}` and writing the canonical response back
/// into the local cache. A `user_preferences` row — a `react_settings` patch
/// an earlier build queued — is moved into `company_user.settings`, never
/// sent: this app writes nothing to React's blob.
class UserSettingsSyncDispatcher implements SyncDispatcher {
  UserSettingsSyncDispatcher({required this.api, required this.repo});

  final UserSettingsApi api;
  final UserSettingsRepository repo;

  // No offline create-with-tmp-id flow → a discarded ghost create can
  // never route here. See SyncDispatcher.deleteLocalRecord.
  @override
  Future<void> deleteLocalRecord({
    required String companyId,
    required String id,
  }) async {}

  // user_settings is a single-row settings table with no `is_dirty` column;
  // its dirtiness is tracked by the outbox row's presence, not a flag, so
  // there is nothing to clear on discard.
  @override
  Future<void> clearLocalDirty({
    required String companyId,
    required String id,
  }) async {}

  @override
  Future<void> dispatch({
    required OutboxRow row,
    required MutationKind kind,
  }) async {
    // User settings only support `update`; the registry never produces other
    // kinds here. Ignore [kind] but assert in debug.
    assert(kind == MutationKind.update);
    if (row.entityType == kUserPreferencesWireName) {
      return _moveLegacyPreferences(row);
    }
    // A row holds only its change; the server replaces the whole object. So
    // the body is the freshest local copy with the change laid over it. A row
    // an earlier build queued holds the body itself.
    final change = UserSettingsChange.tryDecode(row.payload);
    final Map<String, dynamic>? body;
    if (change == null) {
      body = jsonDecode(row.payload) as Map<String, dynamic>;
    } else {
      body = await repo.putBodyFor(companyId: row.companyId, change: change);
      if (body == null) {
        _log.warning(
          'Dropping settings change for ${row.companyId}: the settings are '
          'no longer known locally',
        );
        return;
      }
    }
    final response = await api.update(
      userId: row.entityId,
      body: body,
      idempotencyKey: row.idempotencyKey,
    );
    if (response != null) {
      await repo.applyServerResponse(
        companyId: row.companyId,
        response: response,
      );
    }
  }

  /// This app's own keys in the patch move to `company_user.settings` under
  /// the same names. React's keys in it (`dashboard_fields`, `preferences.…`)
  /// are dropped: the dashboard writes its own copy of those the next time it
  /// opens, from the device's `nav_state`.
  Future<void> _moveLegacyPreferences(OutboxRow row) async {
    final own = {
      for (final e in legacyReactSettingsPatchOf(row.payload).entries)
        if (e.key.startsWith(kAppSettingsKeyPrefix)) e.key: e.value,
    };
    if (own.isEmpty) return;
    await repo.patchSettings(companyId: row.companyId, patch: own);
  }
}
