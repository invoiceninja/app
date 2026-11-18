// An `onSelection` handler that opens its own picker (Run Template) must be
// able to say the user backed out: the scaffold used to clear the selection
// after every handler, so a cancelled picker threw away the user's
// multi-select — unlike a cancelled `prepare`, which keeps it.
//
// Same harness as `embedded_list_selection_test.dart`: the real scaffold
// against a real `Services` graph, rows from a fake view model.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';

import '../../features/shell/_shell_test_helpers.dart';

class _Row {
  const _Row(this.id);
  final String id;
}

final _cols = <ColumnDefinition<_Row>>[
  ColumnDefinition(id: 'id', labelKey: 'id', cellBuilder: (r, _) => Text(r.id)),
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
  List<String> get defaultColumnIds => const ['id'];
  @override
  String get defaultSortField => 'id';
  @override
  bool isValidColumnId(String field) => field == 'id';
  @override
  String idOf(_Row item) => item.id;
  @override
  bool isArchived(_Row item) => false;
  @override
  bool isDeleted(_Row item) => false;
  @override
  Stream<List<_Row>> watchPage() =>
      Stream.value(const [_Row('i1'), _Row('i2')]);
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
  Iterable<BulkAction<_Row>> get bulkActions => [
    for (final id in const ['run_template', 'download'])
      BulkAction<_Row>(
        id: id,
        labelKey: id,
        eligible: (_) => true,
        apply: (_) async {},
      ),
  ];
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _Vm vm;
  final handled = <String>[];

  Future<void> pumpList(WidgetTester tester) async {
    handled.clear();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'co1', name: 'Acme', isAdmin: true)],
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        SingleChildScrollView(
          child: EntityListScreenScaffold<_Row, _Vm>(
            titleKey: 'invoices',
            newRoute: '/invoices/new',
            newLabelKey: 'new_invoice',
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitleKey: 'no_invoices_yet',
            wantsFormatter: false,
            embedded: true,
            embeddedNewOverride: (_) {},
            buildVm: (services, companyId) => vm = _Vm(
              companyId: companyId,
              navStateDao: services.db.navStateDao,
              userSettings: services.userSettings,
              searchDebounce: const Duration(milliseconds: 1),
              persistDebounce: const Duration(milliseconds: 1),
            ),
            sortOptions: (_) => const [],
            searchFieldBuilder: (_, _, _) => const SizedBox(height: 10),
            tileBuilder: (context, vm, row, index, options) =>
                ListTile(title: Text(row.id)),
            bulkActions: [
              EntityListBulkAction(
                actionId: 'run_template',
                icon: Icons.dashboard_customize_outlined,
                tooltipKey: 'run_template',
                singleSuccessKey: 'run_template',
                pluralSuccessKey: 'run_template',
                nothingKey: 'nothing_to_update',
                onSelection: (_, sel) async {
                  handled.add('run_template:${sel.length}');
                  return SelectionActionOutcome.cancelled;
                },
              ),
              EntityListBulkAction(
                actionId: 'download',
                icon: Icons.download_outlined,
                tooltipKey: 'download',
                singleSuccessKey: 'download',
                pluralSuccessKey: 'download',
                nothingKey: 'nothing_to_update',
                onSelection: (_, sel) async {
                  handled.add('download:${sel.length}');
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await _frames(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a handler that reports cancelled keeps the selection', (
    tester,
  ) async {
    await pumpList(tester);
    vm.toggleSelected('i1');
    vm.toggleSelected('i2');
    await _frames(tester);

    await tester.tap(find.text('Run Template').first);
    await _frames(tester);

    expect(handled, ['run_template:2']);
    expect(vm.isInMultiselect, isTrue);
    expect(vm.isSelected('i1') && vm.isSelected('i2'), isTrue);
    await dispose(tester);
  });

  testWidgets('a handler that completes clears the selection', (tester) async {
    await pumpList(tester);
    vm.toggleSelected('i1');
    await _frames(tester);

    await tester.tap(find.text('Download').first);
    await _frames(tester);

    expect(handled, ['download:1']);
    expect(vm.isInMultiselect, isFalse);
    await dispose(tester);
  });
}
