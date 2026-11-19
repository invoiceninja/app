import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/repositories/saved_views_repository.dart';
import 'package:admin/data/repositories/saved_views_sync.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/domain/entity_type.dart';

/// invoiceninja/app#198: saved views sync through
/// `company_user.settings.flutter_saved_views`, so a sign-out (which wipes the
/// `saved_views` table) no longer loses them — and a stale whole-object write
/// from another client (React's User Details save, the old Flutter app) can't
/// delete one on this device.
void main() {
  late AppDatabase db;
  late UserSettingsRepository userSettings;
  late SavedViewsRepository repo;
  var nowMs = 1000;

  Future<void> seedSettingsRow([Map<String, dynamic> extra = const {}]) =>
      db.userSettingsDao.upsert(
        UserSettingsCompanion(
          companyId: const Value('co'),
          userId: const Value('user1'),
          tableColumnsJson: const Value('{}'),
          extraJson: Value(jsonEncode(extra)),
          updatedAt: const Value(0),
        ),
      );

  Future<Map<String, dynamic>> localSettings() async =>
      (await userSettings.getSettings('co'))!;

  Future<Map<String, dynamic>> serverMap() async => Map<String, dynamic>.from(
    (await localSettings())[kSavedViewsSettingsKey] as Map,
  );

  Future<List<Map<String, dynamic>>> queuedPatches() async {
    final rows = await db.outboxDao.activeRowsFor(
      companyId: 'co',
      entityType: kUserSettingsWireName,
    );
    return [
      for (final r in rows)
        Map<String, dynamic>.from(
          (jsonDecode(r.payload) as Map)['patch'] as Map,
        ),
    ];
  }

  Future<void> serverSends(Map<String, dynamic> settings) =>
      applyServerSettings(
        db,
        companyId: 'co',
        userId: 'user1',
        settings: settings,
        nowMs: nowMs,
      );

  Future<void> deliverQueued() async {
    for (final row in await db.select(db.outbox).get()) {
      await db.outboxDao.deleteRow(row.id);
    }
  }

  Map<String, dynamic> entry({
    required String name,
    required int updatedAt,
    String entityType = 'client',
  }) => {
    'entity_type': entityType,
    'name': name,
    'payload': {
      'v': 1,
      'data': {'search': name},
    },
    'created_at': 1,
    'updated_at': updatedAt,
  };

  setUp(() async {
    nowMs = 1000;
    db = AppDatabase(NativeDatabase.memory());
    userSettings = UserSettingsRepository(db: db);
    repo = SavedViewsRepository(
      db: db,
      userSettings: userSettings,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
    );
    await seedSettingsRow();
  });
  tearDown(() => db.close());

  test(
    'create writes the view into flutter_saved_views and queues it',
    () async {
      final view = await repo.create(
        companyId: 'co',
        entityType: EntityType.client,
        name: 'Acme',
        snapshot: {'search': 'acme'},
        iconKey: 'star',
      );

      final stored = (await serverMap())[view.id] as Map;
      expect(stored['entity_type'], 'client');
      expect(stored['name'], 'Acme');
      expect(stored['icon'], 'star');
      expect(stored['payload'], {
        'v': 1,
        'data': {'search': 'acme'},
      });
      expect((await queuedPatches()).single.keys, [
        savedViewSettingsPath(view.id),
      ]);
      // Never React's blob.
      expect((await localSettings()).containsKey('react_settings'), isFalse);
    },
  );

  test('rename, re-snapshot and icon changes are sent', () async {
    final view = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'Acme',
      snapshot: {'search': 'acme'},
    );
    nowMs = 2000;
    await repo.rename(viewId: view.id, newName: 'Acme Corp');
    await repo.updateSnapshot(viewId: view.id, snapshot: {'search': 'corp'});
    await repo.setIcon(viewId: view.id, iconKey: 'flag');

    final stored = (await serverMap())[view.id] as Map;
    expect(stored['name'], 'Acme Corp');
    expect((stored['payload'] as Map)['data'], {'search': 'corp'});
    expect(stored['icon'], 'flag');
    expect(stored['updated_at'], 2000);
  });

  test('a report view syncs too', () async {
    final view = await repo.createReportView(
      companyId: 'co',
      name: 'Q1',
      reportIdentifier: 'invoice',
      state: {'range': 'q1'},
    );
    expect(
      ((await serverMap())[view.id] as Map)['entity_type'],
      kReportSavedViewType,
    );
  });

  test('a delete leaves a tombstone and prunes expired ones', () async {
    await seedSettingsRow({
      kSavedViewsSettingsKey: {
        'old': {'deleted': true, 'updated_at': 1},
      },
    });
    final view = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'Acme',
      snapshot: {'search': 'acme'},
    );
    nowMs = 1000 + kSavedViewTombstoneTtl.inMilliseconds + 10;
    await repo.delete(view.id);

    final map = await serverMap();
    expect(map[view.id], {'deleted': true, 'updated_at': nowMs});
    expect(map.containsKey('old'), isFalse);
  });

  test(
    'the issue: views survive a sign-out wipe and come back at login',
    () async {
      final view = await repo.create(
        companyId: 'co',
        entityType: EntityType.client,
        name: 'By balance',
        snapshot: {'sortField': 'balance', 'sortAscending': false},
      );
      final onServer = await localSettings();

      await db.wipe();
      expect(await db.savedViewsDao.allForCompany('co'), isEmpty);

      await serverSends(onServer);

      final restored = await repo.watchForEntity('co', EntityType.client).first;
      expect(restored.single.id, view.id);
      expect(restored.single.name, 'By balance');
      expect(restored.single.snapshot, {
        'sortField': 'balance',
        'sortAscending': false,
      });
      // Adopting what the server has sends nothing back.
      expect(await queuedPatches(), isEmpty);
    },
  );

  test('a stale whole-object write (React User Details) deletes nothing here '
      'and the view goes back up', () async {
    final view = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'Acme',
      snapshot: {'search': 'acme'},
    );
    await deliverQueued();

    // React saved the settings it loaded before the view existed.
    await serverSends({
      'accent_color': '#ff0000',
      kSavedViewsSettingsKey: <String, dynamic>{},
    });

    expect(await db.savedViewsDao.byId(view.id), isNotNull);
    expect((await queuedPatches()).single.keys, [
      savedViewSettingsPath(view.id),
    ]);
    expect((await serverMap()).containsKey(view.id), isTrue);
    expect((await localSettings())['accent_color'], '#ff0000');
  });

  test('a stale older copy does not revert a newer local edit', () async {
    final view = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'Old',
      snapshot: {'search': 'old'},
    );
    final stale = await localSettings();
    nowMs = 5000;
    await repo.rename(viewId: view.id, newName: 'New');
    await deliverQueued();

    await serverSends(stale);

    expect((await db.savedViewsDao.byId(view.id))!.name, 'New');
    expect(
      ((await queuedPatches()).single[savedViewSettingsPath(view.id)]
          as Map)['name'],
      'New',
    );
  });

  test('a newer server copy from another device is adopted', () async {
    final view = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'Mine',
      snapshot: {'search': 'mine'},
    );
    await deliverQueued();

    await serverSends({
      kSavedViewsSettingsKey: {
        view.id: entry(name: 'Theirs', updatedAt: 9000),
        'other': entry(name: 'Added elsewhere', updatedAt: 9000),
      },
    });

    expect((await db.savedViewsDao.byId(view.id))!.name, 'Theirs');
    expect((await db.savedViewsDao.byId('other'))!.name, 'Added elsewhere');
    expect(await queuedPatches(), isEmpty);
  });

  test('a delete on another device removes the view; an edit made after it '
      'wins', () async {
    final a = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'A',
      snapshot: const {},
    );
    nowMs = 8000;
    final b = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'B',
      snapshot: const {},
    );
    await deliverQueued();

    await serverSends({
      kSavedViewsSettingsKey: {
        a.id: {'deleted': true, 'updated_at': 5000},
        b.id: {'deleted': true, 'updated_at': 5000},
      },
    });

    expect(await db.savedViewsDao.byId(a.id), isNull);
    expect(await db.savedViewsDao.byId(b.id), isNotNull);
    expect((await queuedPatches()).single.keys, [savedViewSettingsPath(b.id)]);
  });

  test('views from an earlier build seed the key when the server has none '
      '(and after the old app erased it)', () async {
    // Rows written before this build synced anything.
    for (final id in ['v1', 'v2']) {
      await db.savedViewsDao.insertView(
        SavedViewsCompanion(
          id: Value(id),
          companyId: const Value('co'),
          entityType: const Value('invoice'),
          name: Value(id),
          payloadJson: const Value('{"v":1,"data":{}}'),
          createdAt: const Value(1),
          updatedAt: const Value(1),
        ),
      );
    }

    await serverSends({'accent_color': '#00ff00'});

    expect((await serverMap()).keys, unorderedEquals(['v1', 'v2']));
    expect(
      (await queuedPatches()).single.keys,
      unorderedEquals([
        savedViewSettingsPath('v1'),
        savedViewSettingsPath('v2'),
      ]),
    );
    expect(await db.savedViewsDao.allForCompany('co'), hasLength(2));
  });

  test('an unreadable entry is skipped, never thrown on', () async {
    await serverSends({
      kSavedViewsSettingsKey: {
        'bad': 'nope',
        'worse': {'name': 3},
        'good': entry(name: 'Good', updatedAt: 2),
      },
    });
    expect((await db.savedViewsDao.allForCompany('co')).map((r) => r.id), [
      'good',
    ]);
  });

  test(
    'a waiting change survives a /refresh that lands before it is sent',
    () async {
      final view = await repo.create(
        companyId: 'co',
        entityType: EntityType.client,
        name: 'Queued',
        snapshot: const {},
      );
      // The server has not seen the create yet.
      await serverSends(<String, dynamic>{});

      expect(await db.savedViewsDao.byId(view.id), isNotNull);
      expect((await serverMap()).containsKey(view.id), isTrue);
    },
  );

  test('without a settings row the view is still saved locally', () async {
    await db.delete(db.userSettings).go();
    final view = await repo.create(
      companyId: 'co',
      entityType: EntityType.client,
      name: 'Local',
      snapshot: const {},
    );
    expect(await db.savedViewsDao.byId(view.id), isNotNull);
    expect(await queuedPatches(), isEmpty);
  });
}
