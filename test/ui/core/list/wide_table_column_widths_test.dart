// The wide table's column widths end to end through `_wideTable`: spare width
// stretches the text columns, a dragged edge resizes a column live and saves
// it on release, and a double-click puts the declared width back
// (docs/entity-lists.md § A dragged column width is a device preference).
// Same harness as `wide_table_edge_fade_test.dart`.

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/services.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/app/list_column_widths_controller.dart';
import 'package:admin/ui/core/list/cell_slot.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';
import 'package:admin/ui/core/list/list_column_widths.dart';

import '../../features/shell/_shell_test_helpers.dart';

class _Row {
  const _Row(this.id);
  final String id;
}

ColumnDefinition<_Row> _col(
  String id,
  double w, [
  ColumnAlign a = ColumnAlign.start,
]) => ColumnDefinition<_Row>(
  id: id,
  labelKey: id,
  width: w,
  align: a,
  cellBuilder: (r, _) => Text('${r.id}-$id'),
);

final _cols = <ColumnDefinition<_Row>>[
  _col('number', 130),
  _col('client', 200),
  _col('amount', 130, ColumnAlign.end),
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

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<({Services services, _Vm vm})> pumpList(
    WidgetTester tester, {
    bool embedded = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'co1', name: 'Acme', isAdmin: true)],
    );
    addTearDown(fixture.dispose);
    final services = fixture.services;
    _Vm? vm;
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
    final scaffold = EntityListScreenScaffold<_Row, _Vm>(
      titleKey: 'invoices',
      newRoute: '/invoices/new',
      newLabelKey: 'new_invoice',
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitleKey: 'no_invoices_yet',
      wantsFormatter: false,
      embedded: embedded,
      embeddedNewOverride: embedded ? (_) {} : null,
      buildVm: (services, companyId) => vm = _Vm(
        companyId: companyId,
        navStateDao: services.db.navStateDao,
        userSettings: services.userSettings,
        searchDebounce: const Duration(milliseconds: 1),
        persistDebounce: const Duration(milliseconds: 1),
      ),
      sortOptions: (_) => const [],
      searchFieldBuilder: (_, _, _) => const SizedBox(height: 10),
      tileBuilder: (context, vm, row, index, options) => tile(context, vm, row),
      bulkActions: const [],
    );
    await tester.pumpWidget(
      wrapWithShell(
        services,
        ListColumnWidthsScope(
          controller: services.listColumnWidths,
          child: embedded ? SingleChildScrollView(child: scaffold) : scaffold,
        ),
      ),
    );
    await _frames(tester);
    return (services: services, vm: vm!);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  double cellWidth(WidgetTester tester, String text) => tester
      .getSize(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(CellSlot<_Row>),
        ),
      )
      .width;

  // The client header cell's trailing edge, in the gap after it.
  Offset clientEdge(WidgetTester tester) {
    final cell = find.ancestor(
      of: find.text('i1-client'),
      matching: find.byType(CellSlot<_Row>),
    );
    final header = tester.getCenter(find.text('CLIENT'));
    return Offset(tester.getRect(cell).right + kColCellGap / 2, header.dy);
  }

  testWidgets('spare width widens the client column, not number or amount', (
    tester,
  ) async {
    await pumpList(tester);
    expect(cellWidth(tester, 'i1-client'), greaterThan(400));
    expect(cellWidth(tester, 'i1-number'), 130);
    expect(cellWidth(tester, 'i1-amount'), 130);
    await dispose(tester);
  });

  testWidgets('dragging the edge resizes live and saves on release; a '
      'double-click resets', (tester) async {
    final (:services, vm: _) = await pumpList(tester);
    final before = cellWidth(tester, 'i1-client');

    final mouse = await tester.startGesture(
      clientEdge(tester),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(cellWidth(tester, 'i1-client'), before - 60, reason: 'live');
    expect(services.listColumnWidths.widthsFor('invoice'), isEmpty);

    await mouse.up();
    await _frames(tester);
    expect(services.listColumnWidths.widthsFor('invoice'), {
      'client': (before - 60).roundToDouble(),
    });
    expect(cellWidth(tester, 'i1-client'), (before - 60).roundToDouble());

    await tester.tapAt(clientEdge(tester), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(clientEdge(tester), kind: PointerDeviceKind.mouse);
    await _frames(tester);
    expect(services.listColumnWidths.widthsFor('invoice'), isEmpty);
    expect(cellWidth(tester, 'i1-client'), before);
    await dispose(tester);
  });

  testWidgets('an edge pinned at the narrowest width turns back at once', (
    tester,
  ) async {
    final (:services, vm: _) = await pumpList(tester);
    final before = cellWidth(tester, 'i1-client');
    final mouse = await tester.startGesture(
      clientEdge(tester),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(Offset(-(before + 200), 0));
    await tester.pump();
    expect(cellWidth(tester, 'i1-client'), kListColumnMinWidth);
    await mouse.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(cellWidth(tester, 'i1-client'), kListColumnMinWidth + 30);
    await mouse.up();
    await _frames(tester);
    expect(services.listColumnWidths.widthsFor('invoice'), {
      'client': kListColumnMinWidth + 30,
    });
    await dispose(tester);
  });

  testWidgets('a list inside a record reads the widths but never writes them', (
    tester,
  ) async {
    final (:services, vm: _) = await pumpList(tester, embedded: true);
    final before = cellWidth(tester, 'i1-client');
    await tester.dragFrom(
      clientEdge(tester),
      const Offset(-60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await _frames(tester);
    expect(cellWidth(tester, 'i1-client'), before);
    expect(services.listColumnWidths.widthsFor('invoice'), isEmpty);
    await dispose(tester);
  });

  testWidgets('a tap at the end of an end-aligned label still sorts', (
    tester,
  ) async {
    final (services: _, :vm) = await pumpList(tester);
    expect(vm.sortField, 'number');
    // The last pixels of AMOUNT, next to its edge.
    final label = tester.getRect(find.text('AMOUNT'));
    await tester.tapAt(
      Offset(label.right - 2, label.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await _frames(tester);
    expect(vm.sortField, 'amount');
    await dispose(tester);
  });
}
