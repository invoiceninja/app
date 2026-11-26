// Beta feedback on the Item cell of the desktop line-item table:
//
//  * a product name longer than the cell is cut off at its edge, so hovering
//    it shows the whole name — without costing the field its state when the
//    tooltip comes and goes;
//  * creating a product from the cell asks for its price and description,
//    as the Add-items picker does, instead of making a $0 catalog entry;
//  * the cell's options are wider than a narrow cell, so the create row and
//    a product's name read in full (invoiceninja/app#215).

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/ui/core/widgets/overflow_tooltip_text.dart';
import 'package:admin/ui/core/widgets/wide_picker_popover.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_column_config.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart';

import '../shell/_shell_test_helpers.dart';

const _longName =
    'Samsung Galaxy S22 5G OLED 120Hz Replacement Screen Assembly With Frame '
    '(Phantom Black, TCGJ, Grade A)';

class _Host extends StatefulWidget {
  const _Host({required this.initial});
  final List<LineItem> initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<LineItem> items = widget.initial;

  @override
  Widget build(BuildContext context) => LineItemTableDesktop(
    companyId: 'co1',
    items: items,
    onChanged: (next) => setState(() => items = next),
    newItemFactory: emptyLineItem,
    config: const LineItemColumnConfig(),
  );
}

LineItem _line(String key) => emptyLineItem().copyWith(
  productKey: key,
  cost: Decimal.fromInt(10),
  quantity: Decimal.one,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  Future<ShellFixture> pumpTable(
    WidgetTester tester,
    List<LineItem> items, {
    double width = 1400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [
        const FakeCompany(id: 'co1', name: 'Co', isAdmin: true, isOwner: true),
      ],
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(fixture.services, _Host(initial: items)),
    );
    await _settle(tester);
    return fixture;
  }

  /// Types a name no product has into the blank row's Item cell, leaving its
  /// options open on the "Create" row offered for it. A near match is seeded
  /// first: with nothing cached the cell waits on a server search before it
  /// opens, and the fixture has no server to answer one.
  Future<void> typeUnmatchedName(
    WidgetTester tester,
    ShellFixture fixture,
  ) async {
    await tester.runAsync(
      () => fixture.db.productDao.upsertAll([
        ProductsCompanion.insert(
          id: 'p1',
          companyId: 'co1',
          productKey: 'Widgetry',
          notes: '',
          price: '0',
          cost: '0',
          quantity: '1',
          updatedAt: 1,
          payload: jsonEncode({
            'id': 'p1',
            'product_key': 'Widgetry',
            'notes': '',
            'updated_at': 1,
          }),
        ),
      ]),
    );
    final field = find.byType(TextField).first;
    await tester.tap(field);
    await _settle(tester);
    await tester.enterText(field, 'Widget');
    // Two short steps, not a full settle: the options have to be taken
    // before the cell's 250 ms commit promotes the blank row under them.
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// [typeUnmatchedName], then takes the "Create" row.
  Future<void> openCreate(WidgetTester tester, ShellFixture fixture) async {
    await typeUnmatchedName(tester, fixture);
    await tester.tap(find.text('Create "Widget"'));
    await _settle(tester);
  }

  testWidgets("the Item cell's options are wider than the cell", (
    tester,
  ) async {
    final fixture = await pumpTable(tester, const [], width: 800);
    await typeUnmatchedName(tester, fixture);
    // At 800 px the Item column is ~150 px, and the options used to be laid
    // out at exactly that: "+ Create…" read "+ Erstel…" (invoiceninja/app#215).
    final cell = tester.getRect(find.byType(TextField).first);
    final options = tester.getRect(find.byType(ListView).last);
    expect(cell.width, lessThan(kPickerPopoverMinWidth));
    expect(options.width, closeTo(kPickerPopoverMinWidth, 0.5));
    expect(options.left, closeTo(cell.left, 0.5));
    // The create row is drawn across that width, and taking it still works.
    final create = find.text('Create "Widget"');
    expect(tester.getRect(create).right, lessThan(options.right));
    await tester.tap(create);
    await _settle(tester);
    expect(find.text('New Product'), findsOneWidget);
    await _teardown(tester);
  });

  Finder tooltipFor(String message) =>
      find.byWidgetPredicate((w) => w is Tooltip && w.message == message);

  testWidgets('a name cut off by the Item cell is offered in full on hover', (
    tester,
  ) async {
    await pumpTable(tester, [_line(_longName), _line('Short')]);

    expect(tooltipFor(_longName), findsOneWidget);
    expect(tooltipFor('Short'), findsNothing);

    // And a mouse resting on it actually raises it: the tooltip is hover-only
    // (`TooltipTriggerMode.manual`), which must not switch the hover off.
    expect(find.text(_longName), findsOneWidget); // the field itself
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(tooltipFor(_longName)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(_longName), findsNWidgets(2)); // …and the tooltip
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 2));
    await _teardown(tester);
  });

  testWidgets('focusing a cut-off name drops the tooltip and keeps the field', (
    tester,
  ) async {
    await pumpTable(tester, [_line(_longName)]);
    final field = find.widgetWithText(TextField, _longName);
    final before = tester.state(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

    await tester.tap(field);
    await _settle(tester);

    expect(tooltipFor(_longName), findsNothing);
    // The same field, not a new one mounted where the tooltip used to be.
    expect(
      tester.state(
        find.descendant(of: field, matching: find.byType(EditableText)),
      ),
      same(before),
    );
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await _teardown(tester);
  });

  testWidgets('creating from the Item cell asks for a price and description', (
    tester,
  ) async {
    final fixture = await pumpTable(tester, const []);

    await openCreate(tester, fixture);

    expect(find.text('New Product'), findsOneWidget);
    Finder inDialog(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextField, label),
    );
    await tester.enterText(inDialog('Price'), '12.50');
    await tester.enterText(inDialog('Description'), 'A fine widget');
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final products = await tester.runAsync(
      () => fixture.services.products.watchPage(companyId: 'co1').first,
    );
    final created = products!.singleWhere((p) => p.productKey == 'Widget');
    expect(created.price.toString(), '12.5');
    expect(created.notes, 'A fine widget');
    await _teardown(tester);
  });

  testWidgets('cancelling that dialog creates nothing', (tester) async {
    final fixture = await pumpTable(tester, const []);

    await openCreate(tester, fixture);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    final products = await tester.runAsync(
      () => fixture.services.products.watchPage(companyId: 'co1').first,
    );
    expect(products!.map((p) => p.productKey), ['Widgetry']);
    await _teardown(tester);
  });

  testWidgets('OverflowTooltipText adds a tooltip only to text it cut off', (
    tester,
  ) async {
    Widget host(String text, {int? maxLines = 1}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            child: OverflowTooltipText(text, maxLines: maxLines),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(_longName));
    expect(find.byType(Tooltip), findsOneWidget);

    await tester.pumpWidget(host('Short'));
    expect(find.byType(Tooltip), findsNothing);

    // Shown whole — nothing left for a tooltip to say.
    await tester.pumpWidget(host(_longName, maxLines: null));
    expect(find.byType(Tooltip), findsNothing);
  });
}
