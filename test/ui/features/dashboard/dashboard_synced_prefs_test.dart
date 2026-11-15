import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_card_config.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_panel_pref.dart';
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/data/repositories/statics_repository.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/data/services/statics_service.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';

import '_fake_dashboard_repo.dart';

/// The dashboard's cross-device sync through `company_user.settings`: the
/// cards, the grouping, the legend and the panels under `flutter_dashboard`,
/// and nothing in React's `react_settings`. `docs/dashboard-panels.md`.
void main() {
  late AppDatabase db;
  late FakeDashboardRepo repo;
  late UserSettingsRepository settings;
  final vms = <DashboardViewModel>[];

  const activeInvoices = DashboardCardConfig(
    field: 'active_invoices',
    period: CardPeriod.current,
    calculate: CardCalc.sum,
    format: CardFormat.money,
  );
  const overdueTasks = DashboardCardConfig(
    field: 'overdue_tasks',
    period: CardPeriod.total,
    calculate: CardCalc.count,
    format: CardFormat.none,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = FakeDashboardRepo(db);
    settings = UserSettingsRepository(db: db);
  });

  tearDown(() async {
    for (final vm in vms) {
      vm.dispose();
    }
    vms.clear();
    await db.close();
  });

  /// [settings] null leaves the row out: no login has stored it yet.
  Future<void> seedSettings(Map<String, Object?>? settings) async {
    if (settings == null) return;
    await db.userSettingsDao.upsert(
      UserSettingsCompanion(
        companyId: const Value('co'),
        userId: const Value('u1'),
        updatedAt: const Value(0),
        extraJson: Value(jsonEncode(settings)),
      ),
    );
  }

  Future<void> capture(Map<String, dynamic> settings) => applyServerSettings(
    db,
    companyId: 'co',
    userId: 'u1',
    settings: settings,
    nowMs: 2,
  );

  Future<void> seedNavState(Map<String, Object?> dashboard) =>
      db.navStateDao.saveFilters(
        filtersJson: jsonEncode({
          'co': {'dashboard': dashboard},
        }),
        now: 1,
      );

  Future<DashboardViewModel> newVm() async {
    final vm = DashboardViewModel(
      repo: repo,
      companyId: 'co',
      navStateDao: db.navStateDao,
      statics: StaticsRepository(
        db: db,
        service: StaticsService(dummyDashboardClient),
      ),
      userSettings: settings,
      persistDebounce: const Duration(milliseconds: 5),
    );
    vms.add(vm);
    await settle();
    return vm;
  }

  Future<List<OutboxRow>> outbox() => db.select(db.outbox).get();

  test('the synced settings win over this device\'s nav_state', () async {
    // Past-due leads every saved arrangement; the rest reversed.
    final reversed = [
      DashboardKind.pastDue,
      ...DashboardKind.panelKinds.reversed.where(
        (k) => k != DashboardKind.pastDue,
      ),
    ];
    await seedNavState({
      'dashboardCards': [activeInvoices.key],
    });
    await seedSettings({
      'flutter_dashboard': {
        'cards': [overdueTasks.key],
        'grouping': 'week',
        'panels': [for (final k in reversed) '$k|0'],
        'chart_series': ['expenses'],
      },
    });
    final vm = await newVm();
    expect(vm.dashboardCards, [overdueTasks]);
    expect(vm.chartGrouping, ChartGrouping.week);
    expect(vm.visibleChartSeries, {ChartSeriesId.expenses});
    expect(vm.panelPrefs.map((p) => p.kind), reversed);
    expect(vm.panelPrefs.every((p) => !p.visible), isTrue);
    // Adopting another device's choice writes nothing back.
    expect(await outbox(), isEmpty);
  });

  test('a change is written under flutter_dashboard, beside the old app\'s '
      'keys', () async {
    await seedSettings({
      'accent_color': '#fff',
      'dashboard_fields': [
        {'field': 'total_active_invoices'},
      ],
    });
    final vm = await newVm();
    vm.addCard(overdueTasks);
    vm.setChartGrouping(ChartGrouping.day);
    await settle();
    final blob = await settings.getSettings('co');
    expect(blob!['accent_color'], '#fff');
    expect(blob['dashboard_fields'], [
      {'field': 'total_active_invoices'},
    ], reason: 'the old app\'s own cards are neither read nor written');
    expect(blob['flutter_dashboard'], {
      'cards': [overdueTasks.key],
      'grouping': 'day',
    }, reason: 'only what changed is written');
    expect(await outbox(), hasLength(1));
  });

  test('a change sends only its own path — never this device\'s copy of the '
      'rest, which may be older than another device\'s', () async {
    await seedSettings({
      'flutter_dashboard': {
        'cards': [activeInvoices.key],
      },
    });
    final vm = await newVm();
    vm.toggleChartSeries(ChartSeriesId.expenses);
    await settle();
    final queued = await outbox();
    expect(UserSettingsChange.tryDecode(queued.single.payload)!.patch.keys, {
      'flutter_dashboard.chart_series',
    });
  });

  test(
    'the first device to sync seeds the rest with its own choices',
    () async {
      await seedNavState({
        'dashboardCards': [activeInvoices.key],
      });
      await seedSettings({});
      final vm = await newVm();
      expect(vm.dashboardCards, [activeInvoices]);
      final blob = await settings.getSettings('co');
      expect((blob!['flutter_dashboard'] as Map)['cards'], [
        activeInvoices.key,
      ]);
    },
  );

  test('a device with nothing customised writes nothing', () async {
    await seedSettings({});
    await newVm();
    expect(await outbox(), isEmpty);
    expect(await settings.getSettings('co'), isEmpty);
  });

  test(
    'before a login stored the settings the dashboard stays device-local',
    () async {
      await seedSettings(null);
      final vm = await newVm();
      vm.addCard(activeInvoices);
      await settle();
      expect(vm.dashboardCards, [activeInvoices]);
      expect(await outbox(), isEmpty);
      expect(await settings.getSettings('co'), isNull);
    },
  );

  test('a change from another device arriving by /refresh replaces the cards '
      'live: the new one is fetched, the dropped one purged', () async {
    await seedSettings({
      'flutter_dashboard': {
        'cards': [activeInvoices.key],
      },
    });
    final vm = await newVm();
    expect(vm.dashboardCards, [activeInvoices]);
    var notified = 0;
    vm.addListener(() => notified++);

    await capture({
      'flutter_dashboard': {
        'cards': [overdueTasks.key],
      },
    });
    await settle();
    expect(vm.dashboardCards, [overdueTasks]);
    expect(notified, greaterThan(0));
    expect(repo.refreshedCardKeys, contains(overdueTasks.key));
    expect(repo.droppedCardKeys, contains(activeInvoices.key));
  });

  test('a capture landing before a local change is written does not revert '
      'it', () async {
    await seedSettings({});
    final vm = await newVm();
    vm.addCard(activeInvoices);
    // The /refresh still holds the server's pre-change settings.
    await capture({'accent_color': '#000'});
    await settle();
    expect(vm.dashboardCards, [activeInvoices]);
    final blob = await settings.getSettings('co');
    expect(blob!['accent_color'], '#000');
    expect((blob['flutter_dashboard'] as Map)['cards'], [activeInvoices.key]);
  });

  test('a stored panel entry parses', () {
    expect(
      DashboardPanelPref.tryParse('${DashboardKind.pastDue}|1'),
      const DashboardPanelPref(kind: DashboardKind.pastDue, visible: true),
    );
  });
}

/// Lets `_init`, the Drift watch and the 5 ms persist debounce run.
Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
