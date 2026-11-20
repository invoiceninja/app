// Beta feedback (2026-11-20): from a client's Invoices tab, tapping a row
// opened the invoice as a pane over EVERY invoice in the company — the client
// scope was gone, so looking through one client's old invoices meant a round
// trip back to the client for each row.
//
// A row tap in an embedded list now carries the tab's scope to the standalone
// list as a `ListFilterIntent` (the dashboard drill-down mechanism), so the
// list beside the record is that client's invoices, as a removable chip:
//
//   * the VM says what its parent scope is, in the STANDALONE list's filter
//     key (`parentScopeFilters`) — a wrong key is silently ignored by both the
//     server and the local mirror, so the real VMs are pinned below;
//   * the embedded scaffold hands that to its rows (`EmbeddedListScope`);
//   * `goEntityRecord` reads it for a jump to the rows' own entity only.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/expense_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/repositories/expense_repository.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/data/repositories/settings_repository.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/data/services/expenses_api.dart';
import 'package:admin/data/services/invoices_api.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/list/deep_link_filter_intent.dart';
import 'package:admin/ui/core/list/embedded_list_scope.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';
import 'package:admin/ui/features/expenses/view_models/expense_list_view_model.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_list_view_model.dart';

import '../../../_localization_helper.dart';
import '../../features/shell/_shell_test_helpers.dart';

class _Row {
  const _Row(this.id);
  final String id;
}

final _cols = <ColumnDefinition<_Row>>[
  ColumnDefinition(id: 'id', labelKey: 'id', cellBuilder: (r, _) => Text(r.id)),
  ColumnDefinition(
    id: 'date',
    labelKey: 'date',
    cellBuilder: (r, _) => Text(r.id),
  ),
];

class _Vm extends GenericListViewModel<_Row> {
  _Vm({
    required super.companyId,
    required super.navStateDao,
    required super.userSettings,
    this.clientId,
  }) : super(
         searchDebounce: const Duration(milliseconds: 1),
         persistDebounce: const Duration(milliseconds: 1),
       );

  final String? clientId;

  @override
  Map<String, Set<String>> get parentScopeFilters => {
    if (clientId != null) 'client_id': {clientId!},
  };

  @override
  EntityType get entityType => EntityType.invoice;
  @override
  List<ColumnDefinition<_Row>> get allColumns => _cols;
  @override
  List<String> get defaultColumnIds => const ['id'];
  @override
  String get defaultSortField => 'id';
  @override
  bool isValidColumnId(String field) => field == 'id' || field == 'date';
  @override
  String idOf(_Row item) => item.id;
  @override
  bool isArchived(_Row item) => false;
  @override
  bool isDeleted(_Row item) => false;
  @override
  Stream<List<_Row>> watchPage() => Stream.value(const [_Row('i1')]);
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

class _FakeInvoicesApi implements InvoicesApi {
  @override
  Future<({InvoiceListApi data, int? cursorUpdatedAt, String? cursorId})> list({
    required int page,
    int perPage = 50,
    String? search,
    int? sinceUpdatedAt,
    String? sinceId,
    Map<String, String> filters = const {},
  }) async => (
    data: const InvoiceListApi(data: []),
    cursorUpdatedAt: null,
    cursorId: null,
  );

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeExpensesApi implements ExpensesApi {
  @override
  Future<({ExpenseListApi data, int? cursorUpdatedAt, String? cursorId})> list({
    required int page,
    int perPage = 50,
    String? search,
    int? sinceUpdatedAt,
    String? sinceId,
    Map<String, String> filters = const {},
  }) async => (
    data: const ExpenseListApi(data: []),
    cursorUpdatedAt: null,
    cursorId: null,
  );

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('standaloneIntent', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    _Vm vmFor({String? clientId}) {
      final vm = _Vm(
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: UserSettingsRepository(db: db),
        clientId: clientId,
      );
      addTearDown(vm.dispose);
      return vm;
    }

    test('is null without a parent scope — the standalone list keeps the '
        'user\'s own filters', () async {
      final vm = vmFor();
      await _settle();
      expect(vm.standaloneIntent(), isNull);
    });

    test('carries the tab as the user sees it, plus the client chip', () async {
      final vm = vmFor(clientId: 'c1');
      await _settle();
      await vm.setExtraFilter(serverKey: 'status_id', values: {'2'});
      await vm.setStates({EntityState.active, EntityState.archived});
      await vm.setSort(field: 'date', ascending: true);
      await _settle();

      final intent = vm.standaloneIntent()!;
      expect(intent.extraFilters, {
        'status_id': {'2'},
        'client_id': {'c1'},
      });
      expect(intent.states, {EntityState.active, EntityState.archived});
      expect(intent.sortField, 'date');
      expect(intent.sortAscending, isTrue);
    });

    test('a fresh token per tap, so reopening re-applies the scope', () async {
      final vm = vmFor(clientId: 'c1');
      await _settle();
      expect(vm.standaloneIntent()!.token, isNot(vm.standaloneIntent()!.token));
    });
  });

  group('the embedded scaffold hands it to its rows', () {
    Future<ListFilterIntent? Function(EntityType)> pumpEmbedded(
      WidgetTester tester, {
      required bool embedded,
    }) async {
      final fixture = await buildFixture(
        companies: const [FakeCompany(id: 'co1', name: 'Acme', isAdmin: true)],
      );
      addTearDown(fixture.dispose);
      late BuildContext rowContext;
      final list = EntityListScreenScaffold<_Row, _Vm>(
        titleKey: 'invoices',
        newRoute: '/invoices/new',
        newLabelKey: 'new_invoice',
        emptyIcon: Icons.receipt_long_outlined,
        emptyTitleKey: 'no_invoices_yet',
        wantsFormatter: false,
        embedded: embedded,
        buildVm: (services, companyId) => _Vm(
          companyId: companyId,
          navStateDao: services.db.navStateDao,
          userSettings: services.userSettings,
          clientId: 'c1',
        ),
        sortOptions: (_) => const [],
        searchFieldBuilder: (_, _, _) => const SizedBox.shrink(),
        tileBuilder: (context, vm, row, index, options) {
          rowContext = context;
          return ListTile(title: Text(row.id));
        },
        bulkActions: const [],
      );
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          embedded ? SingleChildScrollView(child: list) : list,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('i1'), findsOneWidget);
      return (EntityType type) =>
          EmbeddedListScope.rowIntentOf(rowContext, type);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('a row of an embedded list carries the client scope', (
      tester,
    ) async {
      final intentFor = await pumpEmbedded(tester, embedded: true);
      expect(intentFor(EntityType.invoice)?.extraFilters, {
        'client_id': {'c1'},
      });
      expect(
        intentFor(EntityType.client),
        isNull,
        reason: 'a link to another entity (the client cell) carries nothing',
      );
      await unmount(tester);
    });

    testWidgets('a standalone row carries nothing', (tester) async {
      final intentFor = await pumpEmbedded(tester, embedded: false);
      expect(intentFor(EntityType.invoice), isNull);
      await unmount(tester);
    });
  });

  // The intent rides the route's `extra`, and every list on the route reads
  // it. Only the standalone list it is addressed to may adopt it: a row
  // opened from a client's Projects tab lands on a project whose own Tasks /
  // Invoices / Expenses tabs are on the same route, and each used to take on
  // the client chip and the Projects tab's states and sort.
  group('only the standalone list adopts a route intent', () {
    Future<_Vm> pumpUnderRoute(
      WidgetTester tester, {
      required bool embedded,
    }) async {
      final fixture = await buildFixture(
        companies: const [FakeCompany(id: 'co1', name: 'Acme', isAdmin: true)],
      );
      addTearDown(fixture.dispose);
      late _Vm vm;
      Widget list() => EntityListScreenScaffold<_Row, _Vm>(
        titleKey: 'invoices',
        newRoute: '/invoices/new',
        newLabelKey: 'new_invoice',
        emptyIcon: Icons.receipt_long_outlined,
        emptyTitleKey: 'no_invoices_yet',
        wantsFormatter: false,
        embedded: embedded,
        buildVm: (services, companyId) => vm = _Vm(
          companyId: companyId,
          navStateDao: services.db.navStateDao,
          userSettings: services.userSettings,
        ),
        sortOptions: (_) => const [],
        searchFieldBuilder: (_, _, _) => const SizedBox.shrink(),
        tileBuilder: (context, vm, row, index, options) =>
            ListTile(title: Text(row.id)),
        bulkActions: const [],
      );
      final router = GoRouter(
        initialLocation: '/',
        initialExtra: ListFilterIntent(
          extraFilters: const {
            'client_id': {'c1'},
          },
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: embedded ? SingleChildScrollView(child: list()) : list(),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        Provider<Services>.value(
          value: fixture.services,
          child: MaterialApp.router(
            theme: buildInTheme(InTheme.light),
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: kTestSupportedLocales,
            routerConfig: router,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('i1'), findsOneWidget);
      return vm;
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('the standalone list takes the client chip', (tester) async {
      final vm = await pumpUnderRoute(tester, embedded: false);
      expect(vm.extraFilters, {
        'client_id': {'c1'},
      });
      await unmount(tester);
    });

    testWidgets('an embedded list on the same route leaves it', (tester) async {
      final vm = await pumpUnderRoute(tester, embedded: true);
      expect(vm.extraFilters, isEmpty);
      await unmount(tester);
    });
  });

  // The key has to be the one the standalone list's own filter key writes —
  // `ClientFilterKey` → `client_id`, `ExpenseVendorFilterKey` → `vendor_ids`
  // (the expense FETCH scope is `vendor_id`; the chip is not).
  group('the real view models name the standalone filter key', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('invoices: client_id; a project scope hands nothing', () async {
      InvoiceListViewModel vmFor({String? clientId, String? projectId}) {
        final vm = InvoiceListViewModel(
          repo: InvoiceRepository(
            db: db,
            api: _FakeInvoicesApi(),
            settings: SettingsRepository(db: db),
          ),
          companyId: 'co',
          navStateDao: db.navStateDao,
          userSettings: UserSettingsRepository(db: db),
          clientId: clientId,
          projectId: projectId,
        );
        addTearDown(vm.dispose);
        return vm;
      }

      expect(vmFor(clientId: 'c1').parentScopeFilters, {
        'client_id': {'c1'},
      });
      expect(vmFor(projectId: 'p1').parentScopeFilters, isEmpty);
      expect(vmFor().parentScopeFilters, isEmpty);
      await _settle();
    });

    test('expenses: client_id or vendor_ids', () async {
      ExpenseListViewModel vmFor({String? clientId, String? vendorId}) {
        final vm = ExpenseListViewModel(
          repo: ExpenseRepository(db: db, api: _FakeExpensesApi()),
          companyId: 'co',
          navStateDao: db.navStateDao,
          userSettings: UserSettingsRepository(db: db),
          clientId: clientId,
          vendorId: vendorId,
        );
        addTearDown(vm.dispose);
        return vm;
      }

      expect(vmFor(clientId: 'c1').parentScopeFilters, {
        'client_id': {'c1'},
      });
      expect(vmFor(vendorId: 'v1').parentScopeFilters, {
        'vendor_ids': {'v1'},
      });
      await _settle();
    });
  });
}
