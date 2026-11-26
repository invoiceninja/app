// invoiceninja/app#217: on a per-kind tab, Move Top / Move Bottom act on the
// whole document — a custom design that prints the lines in their saved order
// needs the only service moved past the products after it. And More Fields
// opens the line's full editor from the desktop table (invoiceninja/app#216:
// a field the table hides is still edited there).

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_column_config.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart';

import '../shell/_shell_test_helpers.dart';

LineItem _line(String key) => emptyLineItem().copyWith(
  productKey: key,
  notes: '$key notes',
  cost: Decimal.fromInt(10),
  quantity: Decimal.one,
);

typedef _MoveCall = ({List<LineItem> items, int index, bool toEnd});

void main() {
  late List<List<LineItem>> emitted;
  late List<_MoveCall> moves;

  // Drift schedules a zero-duration close timer on unsubscribe.
  Future<void> teardownSubtree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pump(
    WidgetTester tester, {
    required List<LineItem> items,
    LineItemDocumentMoves? documentMoves,
  }) async {
    emitted = <List<LineItem>>[];
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        LineItemTableDesktop(
          companyId: 'co1',
          items: items,
          onChanged: emitted.add,
          newItemFactory: emptyLineItem,
          config: const LineItemColumnConfig(),
          documentMoves: documentMoves,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> openMenu(WidgetTester tester, int row) async {
    await tester.tap(find.byIcon(Icons.more_vert).at(row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  LineItemDocumentMoves documentMoves({
    required bool first,
    required bool last,
  }) {
    moves = <_MoveCall>[];
    return LineItemDocumentMoves(
      isFirst: (_) => first,
      isLast: (_) => last,
      move: (items, index, {required toEnd}) =>
          moves.add((items: items, index: index, toEnd: toEnd)),
    );
  }

  testWidgets('the only line of its tab, with lines of another kind after '
      'it, offers Move Bottom and moves it there', (tester) async {
    await pump(
      tester,
      items: [_line('SERVICE')],
      documentMoves: documentMoves(first: true, last: false),
    );
    await openMenu(tester, 0);

    expect(find.text('Move Bottom'), findsOneWidget);
    expect(find.text('Move Top'), findsNothing);
    // Within the tab there is nowhere to go.
    expect(find.text('Move Down'), findsNothing);

    await tester.tap(find.text('Move Bottom'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(moves, hasLength(1));
    expect(moves.single.toEnd, isTrue);
    expect(moves.single.index, 0);
    expect(moves.single.items.single.productKey, 'SERVICE');
    // The document places it, not the per-tab merge-back.
    expect(emitted, isEmpty);
    await teardownSubtree(tester);
  });

  testWidgets('Move Top reorders within the tab, then hands the document the '
      'line at its new slot', (tester) async {
    await pump(
      tester,
      items: [_line('A'), _line('B')],
      documentMoves: documentMoves(first: false, last: false),
    );
    await openMenu(tester, 1);
    await tester.tap(find.text('Move Top'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(moves.single.toEnd, isFalse);
    expect(moves.single.index, 0);
    expect(moves.single.items.map((li) => li.productKey), ['B', 'A']);
    await teardownSubtree(tester);
  });

  testWidgets('a line already last in the document offers no Move Bottom', (
    tester,
  ) async {
    await pump(
      tester,
      items: [_line('SERVICE')],
      documentMoves: documentMoves(first: true, last: true),
    );
    await openMenu(tester, 0);

    expect(find.text('Move Bottom'), findsNothing);
    expect(find.text('Move Top'), findsNothing);
    await teardownSubtree(tester);
  });

  testWidgets('without document moves the table is the document', (
    tester,
  ) async {
    await pump(tester, items: [_line('A'), _line('B')]);
    await openMenu(tester, 0);
    await tester.tap(find.text('Move Bottom'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(emitted.last.map((li) => li.productKey), ['B', 'A']);
    await teardownSubtree(tester);
  });

  testWidgets('More Fields opens the line in the full editor', (tester) async {
    await pump(tester, items: [_line('WARRANTY')]);
    await openMenu(tester, 0);
    await tester.tap(find.text('More Fields'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(emitted, isEmpty);
    await teardownSubtree(tester);
  });
}
