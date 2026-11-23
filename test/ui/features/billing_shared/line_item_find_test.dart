import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/domain/billing/line_item_find.dart';
import 'package:admin/ui/core/detail/detail_find_navigator.dart';
import 'package:admin/ui/core/detail/entity_detail_scaffold.dart';
import 'package:admin/ui/core/detail/generic_detail_view_model.dart';
import 'package:admin/ui/features/billing_shared/line_item_find.dart';
import 'package:admin/ui/features/billing_shared/line_items_readonly_table.dart';

import '../../../_localization_helper.dart';

/// Find in line items (`docs/find-in-line-items.md`): the bar, the table's
/// highlights, and the scaffold's ⌘F / Ctrl+F.

LineItem _item(String productKey, {String notes = '', String cost = '10'}) =>
    emptyLineItem().copyWith(
      productKey: productKey,
      notes: notes,
      cost: Decimal.parse(cost),
      quantity: Decimal.one,
    );

Future<LineItemFindController> _pump(
  WidgetTester tester,
  List<LineItem> items, {
  double width = 900,
}) async {
  final find = LineItemFindController();
  addTearDown(find.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: find,
              builder: (context, _) => find.isOpen
                  ? LineItemFindBar(controller: find)
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: SingleChildScrollView(
                // Aligned, or the scroll view's tight width overrides [width]
                // and nothing is ever laid out stacked.
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: SizedBox(
                    width: width,
                    child: LineItemsReadonlyTable(items: items, find: find),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return find;
}

/// Opens the bar and types [query] into it.
Future<void> _search(
  WidgetTester tester,
  LineItemFindController find,
  String query,
) async {
  find.open();
  await tester.pump();
  await tester.pump();
  await tester.enterText(_field(), query);
  await tester.pump();
  await tester.pump();
}

Finder _field() => find.descendant(
  of: find.byType(LineItemFindBar),
  matching: find.byType(TextField),
);

/// The `RichText` drawing exactly [text].
RichText _rich(WidgetTester tester, String text) => tester
    .widgetList<RichText>(find.byType(RichText))
    .firstWhere((r) => r.text.toPlainText() == text);

/// The spans of [text] that are marked as a hit.
List<String> _marked(WidgetTester tester, String text) {
  final marked = <String>[];
  _rich(tester, text).text.visitChildren((span) {
    if (span is TextSpan && span.style?.backgroundColor != null) {
      marked.add(span.text ?? '');
    }
    return true;
  });
  return marked;
}

void main() {
  final items = [
    _item('Widget A', notes: 'Blue widget'),
    _item('Gadget'),
    _item('widget'),
  ];

  testWidgets('counts every hit, marks each, and starts on the first', (
    tester,
  ) async {
    final find_ = await _pump(tester, items);
    await _search(tester, find_, 'WIDGET');

    expect(find.text('1 of 3'), findsOneWidget);
    expect(_marked(tester, 'Widget A'), ['Widget']);
    expect(_marked(tester, 'Blue widget'), ['widget']);
    expect(_marked(tester, 'Gadget'), isEmpty);
    // The current hit's line is the one the page scrolls to.
    expect(
      find.descendant(
        of: find.byKey(find_.rowKey(find_.active!.row)),
        matching: find.text('Widget A', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Enter steps forward and wraps; Shift+Enter steps back', (
    tester,
  ) async {
    final find_ = await _pump(tester, items);
    await _search(tester, find_, 'widget');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(find_.rowKey(find_.active!.row)),
        matching: find.text('widget', findRichText: true),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);
    // The field kept focus throughout, so the next Enter still steps.
    expect(find_.field.hasFocus, isTrue);
  });

  testWidgets('says so when nothing matches, and the arrows are disabled', (
    tester,
  ) async {
    final find_ = await _pump(tester, items);
    await _search(tester, find_, 'sprocket');

    expect(find.text('No matches'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('Esc closes the bar, and a closed bar marks nothing', (
    tester,
  ) async {
    final find_ = await _pump(tester, items);
    await _search(tester, find_, 'widget');
    expect(_marked(tester, 'Gadget'), isEmpty);
    expect(_marked(tester, 'Blue widget'), ['widget']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find_.isOpen, isFalse);
    expect(find.byType(LineItemFindBar), findsNothing);
    expect(find.text('Blue widget'), findsOneWidget);
    // Kept for the next open, as a browser keeps it.
    expect(find_.query.text, 'widget');
  });

  testWidgets('a hit past the third line of a description lifts the cap', (
    tester,
  ) async {
    const notes = 'one\ntwo\nthree\nfour\nfive needle';
    final find_ = await _pump(tester, [_item('Long', notes: notes)]);
    expect(_rich(tester, notes).maxLines, 3);

    await _search(tester, find_, 'needle');
    expect(_rich(tester, notes).maxLines, isNull);
    expect(_marked(tester, notes), ['needle']);
  });

  testWidgets('the stacked layout marks the same hits as the table', (
    tester,
  ) async {
    final find_ = await _pump(tester, items, width: 360);
    await _search(tester, find_, 'widget');
    expect(find.text('1 of 3'), findsOneWidget);
    expect(_marked(tester, 'Blue widget'), ['widget']);
  });

  testWidgets('a figure is searchable, as it is with a browser find', (
    tester,
  ) async {
    final find_ = await _pump(tester, [
      _item('A', cost: '12.5'),
      _item('B', cost: '7'),
    ]);
    await _search(tester, find_, '12.5');
    // The unit cost and the line total (quantity one) both read 12.5.
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('an Enter the engine also reports as the field\'s action '
      'steps once', (tester) async {
    // The web engine sends every Return to the field as a text-input action
    // too, handled or not: Enter moved two hits, Shift+Enter none.
    final find_ = await _pump(tester, items);
    await _search(tester, find_, 'widget');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('a soft keyboard\'s Search key alone steps to the next hit', (
    tester,
  ) async {
    final find_ = await _pump(tester, items);
    await _search(tester, find_, 'widget');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find_.field.hasFocus, isTrue);
  });

  testWidgets('the stacked layout counts the total second, where it draws it', (
    tester,
  ) async {
    // The phone row puts the total on the title line; counted last, Next
    // jumped from the figures at the foot of the line back up to its top.
    final find_ = await _pump(tester, [
      _item('Item 10', cost: '10'),
    ], width: 360);
    await _search(tester, find_, '10');
    expect(find_.hits.map((h) => h.segment), [
      LineFindSegment.name,
      LineFindSegment.total,
      LineFindSegment.cost,
    ]);
  });

  group('the Find button', () {
    testWidgets('is on a long document, and opens the bar', (tester) async {
      final find_ = await _pump(tester, [
        for (var i = 0; i < kLineItemFindButtonMinLines; i++) _item('Item $i'),
      ]);
      final button = find.byTooltip('Find in items');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      expect(find_.isOpen, isTrue);
      expect(find_.field.hasFocus, isTrue);
    });

    testWidgets('is on a long document in the stacked layout too', (
      tester,
    ) async {
      await _pump(tester, [
        for (var i = 0; i < kLineItemFindButtonMinLines; i++) _item('Item $i'),
      ], width: 360);
      // Its own head, naming the list: proof the layout is the stacked one.
      expect(find.text('ITEMS'), findsOneWidget);
      expect(find.byTooltip('Find in items'), findsOneWidget);
    });

    testWidgets('is not on a short one', (tester) async {
      await _pump(tester, items);
      expect(find.byTooltip('Find in items'), findsNothing);
    });
  });

  group('Ctrl+F on a record screen', () {
    Future<int Function()> pumpScaffold(
      WidgetTester tester, {
      required bool bind,
    }) async {
      var calls = 0;
      final rows = StreamController<String?>();
      addTearDown(rows.close);
      final vm = GenericDetailViewModel<String>.bound(rows.stream);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: EntityDetailScaffold<String>(
            id: 'x',
            vm: vm,
            emptyTitle: 'Not found',
            bodyBuilder: (context, item) =>
                bind ? _FindBinder(onFind: () => calls++) : const Text('body'),
          ),
        ),
      );
      rows.add('record');
      // The focus keeper claims post-frame.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return () => calls;
    }

    Future<bool> ctrlF(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      return handled;
    }

    testWidgets('opens the find the body bound, with no click first', (
      tester,
    ) async {
      final calls = await pumpScaffold(tester, bind: true);
      expect(await ctrlF(tester), isTrue);
      expect(calls(), 1);
    });

    testWidgets('is left alone on a record with nothing to find', (
      tester,
    ) async {
      await pumpScaffold(tester, bind: false);
      expect(await ctrlF(tester), isFalse);
    });

    testWidgets('a bare F is not the chord', (tester) async {
      final calls = await pumpScaffold(tester, bind: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(calls(), 0);
    });
  });
}

/// Binds [onFind] to the scaffold's find channel, as `BillingDocRecordBody`
/// does.
class _FindBinder extends StatefulWidget {
  const _FindBinder({required this.onFind});

  final VoidCallback onFind;

  @override
  State<_FindBinder> createState() => _FindBinderState();
}

class _FindBinderState extends State<_FindBinder> {
  DetailFindNavigator? _navigator;

  void _find() => widget.onFind();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = DetailFindNavigatorScope.maybeOf(context)?..bind(_find);
  }

  @override
  void dispose() {
    _navigator?.unbind(_find);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('body');
}
