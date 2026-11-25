import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/billing/line_item_type.dart';
import 'package:admin/ui/features/billing_shared/line_item_find.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

/// Find in line items on the billing-document editor
/// (`docs/find-in-line-items.md` § The editor tints the matching lines):
/// Ctrl+F with no click first, the count, stepping, the tint on the matching
/// lines and the outline on the current one, Esc — on the wide table and the
/// phone's cards — and that the editor's other chords still reach the screen.

LineItem _line(
  String productKey, {
  String notes = '',
  LineItemType type = LineItemType.standard,
}) => emptyLineItem().copyWith(
  productKey: productKey,
  notes: notes,
  cost: Decimal.fromInt(10),
  quantity: Decimal.one,
  typeId: type,
);

final _lines = [
  _line('Widget A', notes: 'Blue widget'),
  _line('Gadget'),
  _line('widget'),
  _line('Sprocket'),
];

const _tokens = InTheme.light;

void main() {
  Future<ShellFixture> mount(
    WidgetTester tester, {
    required double width,
    BillingDoc doc = BillingDoc.invoice,
    List<LineItem>? lines,
    Widget Function(Widget layout)? wrap,
  }) async {
    setWindow(tester, width, height: 1100);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    final mounted = buildLayout(
      doc,
      fixture.services,
      showPdfTab: width >= 600,
    );
    addTearDown(mounted.vm.dispose);
    mounted.vm.replaceLineItems(lines ?? _lines);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        wrap == null ? mounted.layout : wrap(mounted.layout),
      ),
    );
    await settle(tester);
    return fixture;
  }

  Future<bool> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final handled = await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    return handled;
  }

  Finder findField() => find.descendant(
    of: find.byType(LineItemFindBar),
    matching: find.byType(TextField),
  );

  LineItemFindController controller(WidgetTester tester) =>
      tester.widget<LineItemFindBar>(find.byType(LineItemFindBar)).controller;

  /// The mark every drawn line shows, by draft index.
  Map<int, LineItemFindMark> marks(WidgetTester tester) => {
    for (final m in tester.widgetList<LineItemFindRowMarker>(
      find.byType(LineItemFindRowMarker, skipOffstage: false),
    ))
      if (m.row >= 0) m.row: m.controller.markFor(m.row),
  };

  /// The fill painted under (table) or on (card) draft line [row].
  Color? fillOf(WidgetTester tester, int row) {
    final marker = find.byWidgetPredicate(
      (w) => w is LineItemFindRowMarker && w.row == row,
    );
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(of: marker, matching: find.byType(DecoratedBox)),
    );
    for (final box in boxes) {
      final d = box.decoration;
      if (d is BoxDecoration && d.color != null) return d.color;
    }
    return null;
  }

  Color fill(LineItemFindMark mark) =>
      lineItemFindRowFill(_tokens, mark, base: _tokens.surface)!;

  testWidgets('wide: Ctrl+F with no click opens the bar; it counts, steps, '
      'tints and closes', (tester) async {
    final fixture = await mount(tester, width: 1440);
    expect(find.byType(LineItemFindBar), findsNothing);

    // No tap anywhere first: the editor's own focus owner has the focus.
    expect(await chord(tester, LogicalKeyboardKey.keyF), isTrue);
    expect(find.byType(LineItemFindBar), findsOneWidget);
    final find_ = controller(tester);
    expect(find_.field.hasFocus, isTrue);

    await tester.enterText(findField(), 'WIDGET');
    await settle(tester);
    // One hit per line: "Widget A" holds two, and counts once.
    expect(find.text('1 of 2'), findsOneWidget);
    expect(marks(tester), {
      0: LineItemFindMark.current,
      1: LineItemFindMark.none,
      2: LineItemFindMark.match,
      3: LineItemFindMark.none,
    });
    expect(fillOf(tester, 0), fill(LineItemFindMark.current));
    expect(fillOf(tester, 2), fill(LineItemFindMark.match));
    expect(fillOf(tester, 1), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(marks(tester)[2], LineItemFindMark.current);
    expect(marks(tester)[0], LineItemFindMark.match);

    // Wraps.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(LineItemFindBar), findsNothing);
    expect(find_.query.text, 'WIDGET');
    expect(marks(tester).values.toSet(), {LineItemFindMark.none});
    expect(fillOf(tester, 0), isNull);

    // Back in the editor: the chord opens it again, on the kept query.
    expect(await chord(tester, LogicalKeyboardKey.keyF), isTrue);
    expect(find.text('1 of 2'), findsOneWidget);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('the chord fires from inside a field of the form', (
    tester,
  ) async {
    final fixture = await mount(tester, width: 1440);
    final po = find.widgetWithText(TextField, 'PO Number').first;
    await tester.tap(po);
    await tester.pump();
    expect(await chord(tester, LogicalKeyboardKey.keyF), isTrue);
    expect(find.byType(LineItemFindBar), findsOneWidget);
    expect(controller(tester).field.hasFocus, isTrue);
    // It typed nothing into the field it left.
    final text = tester.widget<TextField>(po).controller?.text ?? '';
    expect(text, isEmpty);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('the screen\'s own chords above the editor still fire with no '
      'click — the focus owner is below them', (tester) async {
    // Stands in for the edit scaffold's ⌘S, bound above the body.
    var saves = 0;
    final fixture = await mount(
      tester,
      width: 1440,
      wrap: (layout) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              saves++,
        },
        child: layout,
      ),
    );
    expect(await chord(tester, LogicalKeyboardKey.keyS), isTrue);
    expect(saves, 1);
    // And with the find bar open, from its field.
    await chord(tester, LogicalKeyboardKey.keyF);
    expect(await chord(tester, LogicalKeyboardKey.keyS), isTrue);
    expect(saves, 2);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a step to a line on another items tab moves to that tab', (
    tester,
  ) async {
    final fixture = await mount(
      tester,
      width: 1440,
      lines: [
        _line('Design'),
        _line('Consulting', notes: 'Design review', type: LineItemType.task),
      ],
    );
    // The editor's own items tabs, inside the wide layout.
    TabController items() => tester
        .widget<TabBar>(
          find.byWidgetPredicate(
            (w) =>
                w is TabBar &&
                w.tabs.any(
                  (t) => t is Tab && (t.text ?? '').startsWith('Tasks'),
                ),
          ),
        )
        .controller!;
    expect(items().index, 0);

    await chord(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(findField(), 'design');
    await settle(tester);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(items().index, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(items().index, 1, reason: 'the hit is on the Tasks tab');
    expect(marks(tester)[1], LineItemFindMark.current);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a purchase order finds in its lines too', (tester) async {
    final fixture = await mount(
      tester,
      width: 1440,
      doc: BillingDoc.purchaseOrder,
    );
    expect(await chord(tester, LogicalKeyboardKey.keyF), isTrue);
    await tester.enterText(findField(), 'gadget');
    await settle(tester);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(marks(tester)[1], LineItemFindMark.current);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('phone: the chord goes to the Items tab, and the cards are '
      'tinted', (tester) async {
    final fixture = await mount(tester, width: 390);
    final strip = tester.widget<TabBar>(find.byType(TabBar).first);
    expect(strip.controller!.index, 0);

    expect(await chord(tester, LogicalKeyboardKey.keyF), isTrue);
    await settle(tester);
    final labels = tabBarLabels(tester).first;
    expect(strip.controller!.index, labels.indexOf('Items'));
    expect(find.byType(LineItemFindBar), findsOneWidget);
    final find_ = controller(tester);

    await tester.enterText(findField(), 'widget');
    await settle(tester);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(fillOf(tester, 0), fill(LineItemFindMark.current));
    expect(fillOf(tester, 2), fill(LineItemFindMark.match));
    expect(fillOf(tester, 1), _tokens.surface);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(fillOf(tester, 2), fill(LineItemFindMark.current));

    // Leaving the Items tab closes the find, as leaving the record's
    // Overview does.
    await showTab(tester, 0);
    expect(find_.isOpen, isFalse);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
