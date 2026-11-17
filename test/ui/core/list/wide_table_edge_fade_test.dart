// A wide table that overflows its pane sideways fades the edge with columns
// past it (`_wideTable`'s `ScrollEdgeFades`), gated on the horizontal scroll
// position. Same harness as `embedded_list_selection_test.dart`.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/widgets/scroll_edge_fades.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';

import '../../features/shell/_shell_test_helpers.dart';

class _Row {
  const _Row(this.id);
  final String id;
}

/// Set per test: the columns the table lays out.
var _cols = <ColumnDefinition<_Row>>[];

List<ColumnDefinition<_Row>> _columns(int n, double width) => [
  for (var i = 0; i < n; i++)
    ColumnDefinition<_Row>(
      id: 'c$i',
      labelKey: 'id',
      width: width,
      sortable: false,
      cellBuilder: (r, _) => Text('${r.id}-$i'),
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

  final archived = <String>[];

  @override
  EntityType get entityType => EntityType.invoice;
  @override
  List<ColumnDefinition<_Row>> get allColumns => _cols;
  @override
  List<String> get defaultColumnIds => [for (final c in _cols) c.id];
  @override
  String get defaultSortField => 'id';
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
    BulkAction<_Row>(
      id: 'archive',
      labelKey: 'archive',
      eligible: (_) => true,
      apply: (id) async => archived.add(id),
    ),
  ];
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<void> pumpList(WidgetTester tester) async {
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
                ListTile(title: Text(row.id)),
            bulkActions: const [],
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

  final leading = find.byKey(ScrollEdgeFades.leadingFadeKey);
  final trailing = find.byKey(ScrollEdgeFades.trailingFadeKey);

  // Critique pass 2: a table wider than its pane cut its last column off
  // mid-cell with nothing saying more was there.
  testWidgets('a table wider than its pane fades the edge with columns past '
      'it, and follows the scroll', (tester) async {
    _cols = _columns(8, 300);
    await pumpList(tester);

    expect(trailing, findsOneWidget);
    expect(leading, findsNothing);

    final hScroll = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    final controller = tester
        .widget<SingleChildScrollView>(hScroll)
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await _frames(tester);
    expect(leading, findsOneWidget);
    expect(trailing, findsNothing);

    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await _frames(tester);
    expect(leading, findsOneWidget);
    expect(trailing, findsOneWidget);
    await dispose(tester);
  });

  testWidgets('a table that fits draws no fade', (tester) async {
    _cols = _columns(2, 120);
    await pumpList(tester);
    expect(trailing, findsNothing);
    expect(leading, findsNothing);
    await dispose(tester);
  });
}
