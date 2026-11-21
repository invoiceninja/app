import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/login_response_api_model.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/data/repositories/user_repository.dart';
import 'package:admin/data/repositories/user_settings_sync_dispatcher.dart';
import 'package:admin/data/repositories/user_sync_dispatcher.dart';
import 'package:admin/data/services/user_settings_api.dart';
import 'package:admin/domain/appearance_sync.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/sync/mutation.dart';
import 'package:admin/domain/sync/sync_dispatcher.dart';

/// This app's synced preferences live in `company_user.settings`, the object
/// the previous Flutter app uses (`docs/user-settings-storage.md`). The server
/// REPLACES it on a write, so every test here is about not wiping a key this
/// app didn't set — and about never writing React's `react_settings`.
class _RecordingApi implements UserSettingsApi {
  final calls = <({String userId, Map<String, dynamic> body})>[];

  @override
  Future<Map<String, dynamic>?> update({
    required String userId,
    required Map<String, dynamic> body,
    required String idempotencyKey,
  }) async {
    calls.add((userId: userId, body: body));
    return null;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late UserSettingsRepository repo;
  const companyId = 'co1';

  Future<void> seedRow({
    Map<String, Object?> extra = const {},
    Map<String, Object?> columns = const {},
  }) => db.userSettingsDao.upsert(
    UserSettingsCompanion(
      companyId: const Value(companyId),
      userId: const Value('u1'),
      updatedAt: const Value(0),
      extraJson: Value(jsonEncode(extra)),
      tableColumnsJson: Value(jsonEncode(columns)),
    ),
  );

  Future<List<OutboxRow>> rows() => db.select(db.outbox).get();

  UserSettingsChange changeOf(OutboxRow row) =>
      UserSettingsChange.tryDecode(row.payload)!;

  Future<void> capture(Map<String, dynamic> settings) => applyServerSettings(
    db,
    companyId: companyId,
    userId: 'u1',
    settings: settings,
    nowMs: 1,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = UserSettingsRepository(db: db);
  });
  tearDown(() async => db.close());

  test('a patch before a login stored the row writes nothing', () async {
    final changed = await repo.patchSettings(
      companyId: companyId,
      patch: {'flutter_dashboard.cards': <String>[]},
    );
    expect(changed, isFalse);
    expect(await repo.getSettings(companyId), isNull);
    expect(await rows(), isEmpty);
  });

  test('a patch sets dotted paths, keeps the old app\'s keys, and queues '
      'only the change', () async {
    await seedRow(
      extra: {
        'accent_color': '#fff',
        'flutter_dashboard': {
          'panels': ['a|1'],
        },
      },
    );
    await repo.patchSettings(
      companyId: companyId,
      patch: {'flutter_dashboard.grouping': 'week'},
    );
    expect(await repo.getSettings(companyId), {
      'accent_color': '#fff',
      'flutter_dashboard': {
        'panels': ['a|1'],
        'grouping': 'week',
      },
    });
    final queued = await rows();
    expect(queued, hasLength(1));
    expect(queued.single.entityType, kUserSettingsWireName);
    expect(queued.single.entityId, 'u1');
    expect(changeOf(queued.single).patch, {
      'flutter_dashboard.grouping': 'week',
    });
    expect(changeOf(queued.single).columns, isEmpty);
  });

  test('a key without the flutter_ prefix is refused', () async {
    await seedRow();
    expect(
      () => repo.patchSettings(
        companyId: companyId,
        patch: {'dashboard_fields': <String>[]},
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('an unchanged patch queues nothing; a patch and a column change '
      'collapse into one row carrying both', () async {
    await seedRow(
      extra: {
        'flutter_dashboard': {
          'cards': ['a'],
        },
      },
    );
    expect(
      await repo.patchSettings(
        companyId: companyId,
        patch: {
          'flutter_dashboard.cards': ['a'],
        },
      ),
      isFalse,
    );
    expect(await rows(), isEmpty);

    await repo.patchSettings(
      companyId: companyId,
      patch: {'flutter_dashboard.cards': <String>[]},
    );
    await repo.patchSettings(
      companyId: companyId,
      patch: {'flutter_welcome.v': 1},
    );
    await repo.setColumns(
      companyId: companyId,
      entityType: EntityType.client,
      columns: ['name'],
    );
    final queued = await rows();
    expect(queued, hasLength(1));
    expect(changeOf(queued.single).patch.keys, {
      'flutter_dashboard.cards',
      'flutter_welcome.v',
    });
    expect(changeOf(queued.single).columns, {
      'EntityType.client': ['name'],
    });
  });

  test('a /refresh capture lays a queued change over the server\'s settings, '
      'so it does not revert and newer server keys still land', () async {
    await seedRow();
    await repo.patchSettings(
      companyId: companyId,
      patch: {
        'flutter_dashboard.cards': ['x'],
      },
    );
    await repo.setColumns(
      companyId: companyId,
      entityType: EntityType.client,
      columns: ['name'],
    );
    await capture({
      'accent_color': '#000',
      'flutter_dashboard': {'cards': <String>[], 'grouping': 'day'},
      'table_columns': {
        'EntityType.client': ['balance'],
        'EntityType.invoice': ['number'],
      },
    });
    expect(await repo.getSettings(companyId), {
      'accent_color': '#000',
      'flutter_dashboard': {
        'cards': ['x'],
        'grouping': 'day',
      },
    });
    expect(
      await repo.getColumns(
        companyId: companyId,
        entityType: EntityType.client,
      ),
      ['name'],
    );
    expect(
      await repo.getColumns(
        companyId: companyId,
        entityType: EntityType.invoice,
      ),
      ['number'],
    );
  });

  test('a capture leaves the local copy alone while a full-body row from an '
      'earlier build waits', () async {
    await seedRow(extra: {'accent_color': '#fff'});
    await db.outboxDao.enqueue(
      OutboxCompanion.insert(
        companyId: companyId,
        entityType: kUserSettingsWireName,
        entityId: 'u1',
        mutationKind: MutationKind.update.wireName,
        payload: jsonEncode({
          'id': 'u1',
          'company_user': {
            'settings': {'table_columns': <String, Object?>{}},
          },
        }),
        idempotencyKey: 'k',
        nextAttemptAt: 0,
        createdAt: 0,
      ),
    );
    await capture({'accent_color': '#000'});
    expect(await repo.getSettings(companyId), {'accent_color': '#fff'});
  });

  test('the dispatcher sends the freshest local settings with the change '
      'over them, and nothing of react_settings', () async {
    await seedRow();
    await repo.patchSettings(
      companyId: companyId,
      patch: {
        'flutter_dashboard.chart_series': ['invoices'],
      },
    );
    // The old app changed something since; a refresh brought it in.
    await capture({'accent_color': '#123'});
    final api = _RecordingApi();
    await UserSettingsSyncDispatcher(
      api: api,
      repo: repo,
    ).dispatch(row: (await rows()).single, kind: MutationKind.update);
    expect(api.calls.single.userId, 'u1');
    expect(api.calls.single.body, {
      'id': 'u1',
      'company_user': {
        'settings': {
          'accent_color': '#123',
          'flutter_dashboard': {
            'chart_series': ['invoices'],
          },
          'table_columns': <String, Object?>{},
        },
      },
    });
  });

  test('a non-admin\'s body carries the notifications the login captured — '
      'the server reads that key unguarded', () async {
    await seedRow();
    await db.companiesDao.upsertAll([
      CompaniesCompanion.insert(
        id: companyId,
        name: 'Co',
        settings: '{}',
        permissions: '',
        token: 't',
        accountId: 'a',
        updatedAt: 0,
        isAdmin: const Value(false),
      ),
    ]);
    await db.userDao.upsert(
      UsersCompanion.insert(
        id: 'u1',
        companyId: companyId,
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        languageId: '',
        signature: '',
        payload: jsonEncode({
          'company_user': {
            'notifications': {
              'email': ['invoice_sent'],
            },
          },
        }),
        updatedAt: 0,
      ),
    );
    final body = await repo.putBodyFor(
      companyId: companyId,
      change: const UserSettingsChange(patch: {'flutter_welcome.v': 1}),
    );
    expect((body!['company_user'] as Map)['notifications'], {
      'email': ['invoice_sent'],
    });
  });

  test('the dispatcher sends nothing when the settings are no longer '
      'known', () async {
    await seedRow();
    await repo.patchSettings(
      companyId: companyId,
      patch: {'flutter_welcome.v': 1},
    );
    final row = (await rows()).single;
    await db.userSettingsDao.deleteFor(companyId);
    final api = _RecordingApi();
    await UserSettingsSyncDispatcher(
      api: api,
      repo: repo,
    ).dispatch(row: row, kind: MutationKind.update);
    expect(api.calls, isEmpty);
  });

  test('a react_settings patch an earlier build queued is moved, not sent: '
      'this app\'s keys go to settings, React\'s are dropped', () async {
    await seedRow();
    await db.outboxDao.enqueue(
      OutboxCompanion.insert(
        companyId: companyId,
        entityType: kUserPreferencesWireName,
        entityId: 'u1',
        mutationKind: MutationKind.update.wireName,
        payload: jsonEncode({
          'patch': {
            'dashboard_fields': ['a|current|sum|money|0'],
            'preferences.dashboard_charts.default_view': 'day',
            'flutter_welcome': {'v': 1},
          },
        }),
        idempotencyKey: 'k',
        nextAttemptAt: 0,
        createdAt: 0,
      ),
    );
    final api = _RecordingApi();
    await UserSettingsSyncDispatcher(
      api: api,
      repo: repo,
    ).dispatch(row: (await rows()).single, kind: MutationKind.update);
    expect(api.calls, isEmpty);
    expect(await repo.getSettings(companyId), {
      'flutter_welcome': {'v': 1},
    });
    final moved = (await rows()).last;
    expect(moved.entityType, kUserSettingsWireName);
    expect(changeOf(moved).patch.keys, {'flutter_welcome'});
  });

  group('a profile save replaces the same object', () {
    test('its body takes this app\'s keys and the columns from the freshest '
        'local copy, and keeps what the profile changed', () async {
      await seedRow(
        extra: {
          'accent_color': '#old',
          'flutter_dashboard': {'grouping': 'day'},
        },
        columns: {
          'EntityType.client': ['name'],
        },
      );
      final sent = await repo.withFreshAppKeys(
        companyId: companyId,
        userId: 'u1',
        // Built when the profile was edited, before the dashboard change.
        settings: {
          'accent_color': '#new',
          'flutter_dashboard': {'grouping': 'month'},
          'flutter_gone': true,
          'table_columns': <String, Object?>{},
        },
      );
      expect(sent, {
        'accent_color': '#new',
        'flutter_dashboard': {'grouping': 'day'},
        'table_columns': {
          'EntityType.client': ['name'],
        },
      });
    });

    test('another user\'s body is left alone', () async {
      await seedRow(extra: {'flutter_welcome': 1});
      final theirs = {'accent_color': '#abc'};
      expect(
        await repo.withFreshAppKeys(
          companyId: companyId,
          userId: 'u2',
          settings: theirs,
        ),
        theirs,
      );
    });

    test('its reply is stored, so the next settings PUT carries the new '
        'accent colour — with a waiting change still laid over it', () async {
      await seedRow(extra: {'accent_color': '#old'});
      await repo.patchSettings(
        companyId: companyId,
        patch: {'flutter_dashboard.grouping': 'week'},
      );
      await repo.applyProfileSaveSettings(
        companyId: companyId,
        userId: 'u1',
        settings: {
          'accent_color': '#new',
          'table_columns': <String, Object?>{},
        },
      );
      expect(await repo.getSettings(companyId), {
        'accent_color': '#new',
        'flutter_dashboard': {'grouping': 'week'},
      });
      // A reply without the settings, or another user's, changes nothing.
      await repo.applyProfileSaveSettings(
        companyId: companyId,
        userId: 'u1',
        settings: const {},
      );
      await repo.applyProfileSaveSettings(
        companyId: companyId,
        userId: 'u2',
        settings: {'accent_color': '#theirs'},
      );
      expect((await repo.getSettings(companyId))!['accent_color'], '#new');
    });
  });

  test('applySettingsPatch: a null removes, a non-map on the way is '
      'replaced, and the base is not mutated', () {
    final base = <String, dynamic>{
      'a': 1,
      'flutter_dashboard': 'oops',
      'keep': {'x': 1},
    };
    final out = applySettingsPatch(base, {
      'a': null,
      'flutter_dashboard.grouping': 'day',
    });
    expect(out, {
      'flutter_dashboard': {'grouping': 'day'},
      'keep': {'x': 1},
    });
    expect(base['a'], 1);
  });

  group('flutter_appearance (invoiceninja/app#199)', () {
    const record = AppearanceRecord(
      themeMode: 'dark',
      lightVariant: 'mist',
      darkVariant: 'carbon',
      custom: {
        'light': {'ink': '#112233'},
        'dark': <String, Object?>{},
      },
      updatedAt: 1234,
    );

    test('a record is patched field by field: a key a newer build added '
        'survives, and the PUT carries every other key', () async {
      await seedRow(
        extra: {
          'accent_color': '#abcdef',
          kAppearanceSettingsKey: {'theme_mode': 'light', 'from_newer': 1},
        },
      );
      await repo.patchSettings(
        companyId: companyId,
        patch: record.toSettingsPatch(),
      );

      final stored = (await repo.getSettings(companyId))!;
      expect(stored['accent_color'], '#abcdef');
      expect(stored[kAppearanceSettingsKey], {
        'theme_mode': 'dark',
        'light_variant': 'mist',
        'dark_variant': 'carbon',
        'custom': {
          'light': {'ink': '#112233'},
          'dark': <String, Object?>{},
        },
        'updated_at': 1234,
        'from_newer': 1,
      });
      expect(AppearanceRecord.fromSettings(stored)?.updatedAt, 1234);

      final body = await repo.putBodyFor(
        companyId: companyId,
        change: changeOf((await rows()).single),
      );
      final settings =
          (body!['company_user'] as Map)['settings'] as Map<String, dynamic>;
      expect(settings['accent_color'], '#abcdef');
      expect(AppearanceRecord.fromSettings(settings)?.sameLook(record), isTrue);
    });

    test(
      'a queued record is laid over a capture, so it does not revert',
      () async {
        await seedRow();
        await repo.patchSettings(
          companyId: companyId,
          patch: record.toSettingsPatch(),
        );
        await capture({
          kAppearanceSettingsKey: {'theme_mode': 'light', 'updated_at': 5},
        });
        final stored = (await repo.getSettings(companyId))!;
        expect(AppearanceRecord.fromSettings(stored)?.updatedAt, 1234);
        expect(AppearanceRecord.fromSettings(stored)?.themeMode, 'dark');
      },
    );

    test('a queued appearance-only change is marked device-derived, and '
        'loses the mark once it carries anything else', () async {
      await seedRow();
      await repo.patchSettings(
        companyId: companyId,
        patch: record.toSettingsPatch(),
      );
      var row = (await rows()).single;
      expect(
        isDeviceDerivedSettingsRow(
          entityType: row.entityType,
          payload: row.payload,
        ),
        isTrue,
      );
      expect(await db.outboxDao.pendingCountForCompany(companyId), 0);

      // A saved view collapses into the same pending row.
      await repo.patchSettings(
        companyId: companyId,
        patch: {
          'flutter_saved_views.v1': {'name': 'Mine'},
        },
      );
      row = (await rows()).single;
      expect(
        isDeviceDerivedSettingsRow(
          entityType: row.entityType,
          payload: row.payload,
        ),
        isFalse,
      );
      expect(await db.outboxDao.pendingCountForCompany(companyId), 1);
      expect(changeOf(row).patch.keys, contains('flutter_saved_views.v1'));
    });

    test('a column change is never device-derived', () {
      expect(
        const UserSettingsChange(
          patch: {'flutter_appearance.theme_mode': 'dark'},
          columns: {
            'EntityType.client': ['name'],
          },
        ).isDeviceDerived,
        isFalse,
      );
      expect(const UserSettingsChange().isDeviceDerived, isFalse);
    });

    test('watchAllSettings holds every company of the signed-in user, and '
        'no one else\'s', () async {
      await seedRow(extra: {'k': 1});
      await db.userSettingsDao.upsert(
        UserSettingsCompanion(
          companyId: const Value('co2'),
          userId: const Value('u1'),
          updatedAt: const Value(0),
          extraJson: Value(jsonEncode({'k': 2})),
          tableColumnsJson: const Value('{"EntityType.client":["name"]}'),
        ),
      );
      await db.userSettingsDao.upsert(
        UserSettingsCompanion(
          companyId: const Value('co3'),
          userId: const Value('someone_else'),
          updatedAt: const Value(0),
          extraJson: Value(jsonEncode({'k': 3})),
          tableColumnsJson: const Value('{}'),
        ),
      );
      final all = await repo.watchAllSettings(userId: 'u1').first;
      expect(all, {
        companyId: {'k': 1},
        'co2': {'k': 2},
      });
      expect(await db.userSettingsDao.all(), hasLength(3));
    });
  });

  group('discarding a preferences row', () {
    Future<void> enqueueUserEdit({required String state}) async {
      await db.outboxDao.enqueue(
        OutboxCompanion.insert(
          companyId: companyId,
          entityType: kUserWireName,
          entityId: 'u1',
          mutationKind: MutationKind.update.wireName,
          payload: '{}',
          idempotencyKey: 'k-$state',
          nextAttemptAt: 0,
          createdAt: 0,
        ),
      );
      await db.customStatement('UPDATE outbox SET state = ?', [state]);
    }

    CompositeUserDispatcher composite(_RecordingDispatcher user) =>
        CompositeUserDispatcher(
          userSettings: _RecordingDispatcher(),
          user: user,
          outbox: db.outboxDao,
        );

    for (final state in ['pending', 'dead']) {
      test('leaves the dirty flag of a $state profile edit alone', () async {
        await enqueueUserEdit(state: state);
        final user = _RecordingDispatcher();
        await composite(user).clearLocalDirty(companyId: companyId, id: 'u1');
        expect(user.cleared, isEmpty);
      });
    }

    test('still clears it when no profile edit is waiting', () async {
      final user = _RecordingDispatcher();
      await composite(user).clearLocalDirty(companyId: companyId, id: 'u1');
      expect(user.cleared, ['u1']);
    });
  });

  group('login model', () {
    Map<String, dynamic> uc(Object? react, {Object? notifications}) => {
      'company': {'id': 'c'},
      'account': {'id': 'a'},
      'react_settings': ?react,
      'notifications': ?notifications,
    };

    test('reads the object, takes PHP\'s [] as empty, and anything else — or '
        'no key — as unknown', () {
      expect(UserCompanyApi.fromJson(uc({'dark_mode': true})).reactSettings, {
        'dark_mode': true,
      });
      expect(UserCompanyApi.fromJson(uc(<Object>[])).reactSettings, isEmpty);
      expect(UserCompanyApi.fromJson(uc('x')).reactSettings, isNull);
      expect(UserCompanyApi.fromJson(uc(null)).reactSettings, isNull);
      expect(
        UserCompanyApi.fromJson(
          uc(null, notifications: {'email': <String>[]}),
        ).notifications,
        {'email': <String>[]},
      );
      expect(UserCompanyApi.fromJson(uc(null)).notifications, isNull);
    });
  });
}

class _RecordingDispatcher implements SyncDispatcher {
  final cleared = <String>[];

  @override
  Future<void> clearLocalDirty({
    required String companyId,
    required String id,
  }) async => cleared.add(id);

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
