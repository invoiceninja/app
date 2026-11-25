// "Always show scroll bars" on the app's scroll-heavy surfaces, on a pointer
// platform: an entity list whose wide table scrolls both ways, a record
// screen with pinned tabs, Device Settings, and the Tasks weekly grid. Each
// is scrolled, hovered, re-themed and has the switch flipped under it, and
// none may throw — the failure a theme-level `thumbVisibility` produces
// (docs/scrollbars.md § The pin is decided per bar, never a theme-level
// `thumbVisibility`).

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/always_show_scrollbars_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/task_repository.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/detail/standing_card.dart';
import 'package:admin/ui/core/list/cell_slot.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';
import 'package:admin/ui/core/list/list_column_widths.dart';
import 'package:admin/ui/core/widgets/in_scrollbar.dart';
import 'package:admin/ui/features/clients/views/client_detail_screen.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/basic/device_settings_screen.dart';
import 'package:admin/ui/features/tasks/view_models/task_weekly_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/weekly/weekly_grid.dart';

import '../../../_localization_helper.dart';
import '../../../_support/fake_biometric_service.dart';
import '../../../_support/record_screen_harness.dart';
import '../../features/shell/_shell_test_helpers.dart';

final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

List<ScrollbarPainter> _painters(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.foregroundPainter case final ScrollbarPainter p) p,
];

/// How many thumbs are fully drawn.
int _shown(WidgetTester tester) =>
    _painters(tester).where((p) => p.fadeoutOpacityAnimation.value == 1).length;

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Everything a user does to a scroll bar, with an exception check after
/// each step so a failure names the step.
Future<void> _exercise(
  WidgetTester tester, {
  required AlwaysShowScrollbarsController always,
  required ValueNotifier<bool> dark,
  required Finder scrollable,
  Offset hoverAt = const Offset(-6, 30),
}) async {
  void clean(String step) =>
      expect(tester.takeException(), isNull, reason: step);

  clean('mounted');
  expect(_shown(tester), greaterThan(0), reason: 'no thumb was pinned');

  // The part of the scroll view on screen: a wide table's rows run past the
  // window's right edge.
  Rect visible() => tester
      .getRect(scrollable.first)
      .intersect(Offset.zero & tester.view.physicalSize);

  await tester.dragFrom(visible().center, const Offset(0, -200));
  await _frames(tester);
  clean('a vertical drag');

  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: visible().center,
      scrollDelta: const Offset(0, 300),
    ),
  );
  await _frames(tester);
  clean('a wheel scroll');

  final rect = visible();
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: rect.center);
  await tester.pump();
  await mouse.moveTo(Offset(rect.right + hoverAt.dx, rect.top + hoverAt.dy));
  await _frames(tester);
  await mouse.moveTo(rect.center);
  await _frames(tester);
  await mouse.removePointer();
  clean('hovering the bar');

  dark.value = !dark.value;
  await _frames(tester);
  clean('a theme change');

  unawaited(always.set(false));
  await _frames(tester);
  clean('the switch off');
  unawaited(always.set(true));
  await _frames(tester);
  clean('the switch back on');
  expect(_shown(tester), greaterThan(0), reason: 'no thumb re-pinned');

  final size = tester.view.physicalSize;
  tester.view.physicalSize = Size(size.width - 120, size.height - 80);
  await _frames(tester);
  tester.view.physicalSize = size;
  await _frames(tester);
  clean('a window resize');
}

// ---------------------------------------------------------------------------
// The entity list: a fake view model over the real scaffold, its wide table
// wider than the window so it scrolls sideways under its own InScrollbar.

class _Row {
  const _Row(this.id);
  final String id;
}

final _cols = <ColumnDefinition<_Row>>[
  for (final id in const [
    'number',
    'client',
    'date',
    'due_date',
    'amount',
    'balance',
    'status',
    'po_number',
  ])
    ColumnDefinition<_Row>(
      id: id,
      labelKey: id,
      width: 220,
      cellBuilder: (r, _) => Text('${r.id}-$id'),
    ),
];

class _Vm extends GenericListViewModel<_Row> {
  _Vm({
    required super.companyId,
    required super.navStateDao,
    required super.userSettings,
    required super.searchDebounce,
    required super.persistDebounce,
  });

  @override
  EntityType get entityType => EntityType.invoice;
  @override
  List<ColumnDefinition<_Row>> get allColumns => _cols;
  @override
  List<String> get defaultColumnIds => [for (final c in _cols) c.id];
  @override
  String get defaultSortField => 'number';
  @override
  bool isValidColumnId(String field) => _cols.any((c) => c.id == field);
  @override
  String idOf(_Row item) => item.id;
  @override
  bool isArchived(_Row item) => false;
  @override
  bool isDeleted(_Row item) => false;
  @override
  Stream<List<_Row>> watchPage() =>
      Stream.value([for (var i = 0; i < 80; i++) _Row('i$i')]);
  @override
  Future<bool> fetchPage({
    required int page,
    required String? search,
    required Set<EntityState> states,
    required Map<String, Set<String>> extraFilters,
    required bool ignoreCursor,
  }) async => false;
  @override
  Future<void> refreshAll() async {}
  @override
  Iterable<BulkAction<_Row>> get bulkActions => const [];
}

Widget _app({
  required Services? services,
  required AlwaysShowScrollbarsController always,
  required ValueNotifier<bool> dark,
  required Widget child,
}) => MultiProvider(
  providers: [
    if (services != null) Provider<Services>.value(value: services),
    ChangeNotifierProvider<AlwaysShowScrollbarsController>.value(value: always),
  ],
  child: ValueListenableBuilder<bool>(
    valueListenable: dark,
    builder: (context, isDark, _) => MaterialApp(
      theme: buildInTheme(isDark ? InTheme.darkEspresso : InTheme.light),
      scrollBehavior: const InScrollBehavior(),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(body: child),
    ),
  ),
);

// ---------------------------------------------------------------------------
// The Tasks weekly grid: a fake repository, more task rows than fit.

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Task _task(int i) => Task(
  id: 't$i',
  number: '$i',
  description: 'Task $i',
  rate: Decimal.zero,
  invoiceId: '',
  clientId: '',
  projectId: '',
  statusId: 's1',
  statusOrder: 0,
  assignedUserId: '',
  timeLog: [
    TimeEntry(
      start: DateTime(2026, 6, 8, 9).toUtc(),
      stop: DateTime(2026, 6, 8, 11, 15).toUtc(),
    ),
  ],
  customValue1: '',
  customValue2: '',
  customValue3: '',
  customValue4: '',
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

class _FakeTasks implements TaskRepository {
  _FakeTasks(this.controller);
  final StreamController<List<Task>> controller;

  @override
  Stream<List<Task>> watchAllActive({
    required String companyId,
    states = const {},
  }) => controller.stream;

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  testWidgets('an entity list, its wide table scrolling both ways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'co1', name: 'Acme', isAdmin: true)],
    );
    addTearDown(fixture.dispose);
    final services = fixture.services;
    unawaited(services.alwaysShowScrollbars.set(true));
    final dark = ValueNotifier(false);

    Widget tile(BuildContext context, _Vm vm, _Row row) => Row(
      children: [
        SizedBox(
          width:
              16 +
              colWMoreMenu() +
              kColActionsLeadingGap +
              kColLeadingWidth +
              kColCellGap,
        ),
        for (final c in vm.columns) ...[
          CellSlot<_Row>(
            column: c,
            entity: row,
            child: c.cellBuilder(row, context),
          ),
          const SizedBox(width: kColCellGap),
        ],
      ],
    );
    await tester.pumpWidget(
      _app(
        services: services,
        always: services.alwaysShowScrollbars,
        dark: dark,
        child: ListColumnWidthsScope(
          controller: services.listColumnWidths,
          child: EntityListScreenScaffold<_Row, _Vm>(
            titleKey: 'invoices',
            newRoute: '/invoices/new',
            newLabelKey: 'new_invoice',
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitleKey: 'no_invoices_yet',
            wantsFormatter: false,
            buildVm: (services, companyId) => _Vm(
              companyId: companyId,
              navStateDao: services.db.navStateDao,
              userSettings: services.userSettings,
              searchDebounce: const Duration(milliseconds: 1),
              persistDebounce: const Duration(milliseconds: 1),
            ),
            sortOptions: (_) => const [],
            searchFieldBuilder: (_, _, _) => const SizedBox(height: 10),
            tileBuilder: (context, vm, row, index, options) =>
                tile(context, vm, row),
            bulkActions: const [],
          ),
        ),
      ),
    );
    await _frames(tester);
    expect(find.text('i0-number'), findsOneWidget);

    // Both the rows' vertical bar and the table's horizontal one.
    expect(_shown(tester), greaterThanOrEqualTo(2));
    // The rows' bar is on the card's edge, on screen — not past the last
    // column, where the rows' own bar would be (docs/scrollbars.md).
    final rowsBar = find.byWidgetPredicate(
      (w) => w is InScrollbar && w.notificationPredicate != null,
    );
    expect(rowsBar, findsOneWidget);
    expect(tester.getRect(rowsBar).right, lessThanOrEqualTo(900));
    expect(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(
            find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .right,
      greaterThan(900),
      reason: 'the table really is wider than the window',
    );
    await _exercise(
      tester,
      always: services.alwaysShowScrollbars,
      dark: dark,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );

    // Sideways, by a drag on the horizontal thumb.
    final table = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );
    expect(table, findsWidgets);
    final rect = tester.getRect(table.first);
    final drag = await tester.startGesture(
      Offset(rect.left + 30, rect.bottom - 6),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(200, 0));
    await tester.pump();
    await drag.up();
    await _frames(tester);
    expect(tester.takeException(), isNull, reason: 'dragging the table bar');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }, variant: _desktop);

  final dark = ValueNotifier(false);
  recordScreenTest(
    'a record screen with pinned tabs',
    variant: _desktop,
    size: const Size(1100, 600),
    seed: (services) async {
      await services.alwaysShowScrollbars.set(true);
      await services.clients.applyUpdateResponse(
        companyId: 'co1',
        serverResponse: const ClientApi(
          id: 'c1',
          name: 'Acme Corporation',
          displayName: 'Acme Corporation',
          privateNotes: 'Call before visiting.',
          updatedAt: 1710000000,
          createdAt: 1700000000,
        ),
      );
    },
    screen: () => ClientDetailScreen(id: 'c1'),
    ready: () => find.byType(StandingCard),
    body: (tester, screen) async {
      await screen.quiet();
      // The harness's theme is fixed, so the theme change here is the
      // switch and a resize; a dark flip is covered by the others.
      await _exercise(
        tester,
        always: screen.services.alwaysShowScrollbars,
        dark: dark,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await screen.quiet();
    },
  );

  testWidgets('Device Settings, flipping its own switch', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'co1', name: 'Acme')],
      closeStreamsSynchronously: true,
      biometricService: FakeBiometricService(),
    );
    addTearDown(fixture.dispose);
    final services = fixture.services;
    final dark = ValueNotifier(false);
    final router = GoRouter(
      initialLocation: '/settings/device_settings',
      routes: [
        GoRoute(
          path: '/settings/device_settings',
          builder: (_, _) => const DeviceSettingsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: services),
          ChangeNotifierProvider<SettingsLevelController>(
            create: (_) => SettingsLevelController(),
          ),
          ChangeNotifierProvider<AlwaysShowScrollbarsController>.value(
            value: services.alwaysShowScrollbars,
          ),
        ],
        child: ValueListenableBuilder<bool>(
          valueListenable: dark,
          builder: (context, isDark, _) => MaterialApp.router(
            theme: buildInTheme(isDark ? InTheme.darkEspresso : InTheme.light),
            scrollBehavior: const InScrollBehavior(),
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: kTestSupportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await _frames(tester, 8);

    // The row is there on a pointer platform, and turning it on pins.
    final row = find.text('Always Show Scroll Bars');
    expect(row, findsOneWidget);
    expect(_shown(tester), 0);
    await tester.tap(row);
    await _frames(tester);
    expect(services.alwaysShowScrollbars.value, isTrue);
    expect(_shown(tester), greaterThan(0));

    await _exercise(
      tester,
      always: services.alwaysShowScrollbars,
      dark: dark,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }, variant: _desktop);

  testWidgets('the Tasks weekly grid, wider and taller than its window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final always = AlwaysShowScrollbarsController(
      prefs: DevicePrefsStore(null),
    );
    unawaited(always.set(true));
    final dark = ValueNotifier(false);
    final tasks = StreamController<List<Task>>();
    addTearDown(tasks.close);
    final vm = TaskWeeklyViewModel(
      repo: _FakeTasks(tasks),
      companyId: 'co',
      firstDayOfWeek: 1,
      focus: Date(2026, 6, 10),
    );
    addTearDown(vm.dispose);
    tasks.add([for (var i = 0; i < 30; i++) _task(i)]);

    await tester.pumpWidget(
      _app(
        services: null,
        always: always,
        dark: dark,
        child: ChangeNotifierProvider<TaskWeeklyViewModel>.value(
          value: vm,
          child: const WeeklyGrid(),
        ),
      ),
    );
    await _frames(tester);
    expect(find.text('Task 0'), findsOneWidget);
    // The rows' vertical bar and the grid's horizontal one.
    expect(_shown(tester), 2);

    await _exercise(
      tester,
      always: always,
      dark: dark,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );

    // A sideways scroll, which used to find no controller at all.
    final grid = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );
    await tester.drag(grid.first, const Offset(-300, 0));
    await _frames(tester);
    expect(tester.takeException(), isNull, reason: 'a sideways drag');
  }, variant: _desktop);
}
