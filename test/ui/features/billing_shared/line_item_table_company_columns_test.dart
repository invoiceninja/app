import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/static/pdf_catalogs.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_column_config.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_columns.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart';

import '../../../_localization_helper.dart';
import '../shell/_shell_test_helpers.dart';

/// The desktop table draws the company's Invoice Design columns
/// (invoiceninja/app#216). A column it leaves out hides a field, never its
/// value: the line is saved with everything it held.

/// Product Columns: Item, Unit Cost, Line Total — no Description. Discounts
/// and Show Product Quantity off, so those two columns go as well. Two custom
/// fields, which React's rule shows whatever the list says; which of them
/// the table shows is this device's choice.
final _narrowed =
    const LineItemColumnConfig(
      showDiscount: true,
      taxColumnCount: 1,
    ).forCompany(
      const Company(
        id: 'co1',
        enableProductDiscount: false,
        enableProductQuantity: false,
        enabledItemTaxRates: 0,
        customFields: {
          'product1': 'Serial|single_line_text',
          'product2': 'Batch|single_line_text',
        },
        settings: CompanySettings(
          pdfVariables: {
            PdfVariableSection.productColumns: [
              r'$product.item',
              r'$product.unit_cost',
              r'$product.line_total',
            ],
          },
        ),
      ),
    );

LineItem _line() => emptyLineItem().copyWith(
  productKey: 'Widget',
  notes: 'Hidden note',
  cost: Decimal.fromInt(10),
  quantity: Decimal.fromInt(3),
  discount: Decimal.fromInt(5),
  taxName1: 'VAT',
  taxRate1: Decimal.fromInt(20),
  customValue1: 'SN-1',
);

/// Feeds the emitted list back, as the real edit layouts do.
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    required this.config,
    required this.onChanged,
    this.controller,
  });

  final List<LineItem> initial;
  final LineItemColumnConfig config;
  final ValueChanged<List<LineItem>> onChanged;
  final LineItemTableDesktopController? controller;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<LineItem> _items = widget.initial;

  @override
  Widget build(BuildContext context) => LineItemTableDesktop(
    companyId: 'co1',
    items: _items,
    onChanged: (next) {
      widget.onChanged(next);
      setState(() => _items = next);
    },
    newItemFactory: emptyLineItem,
    config: widget.config,
    controller: widget.controller,
  );
}

void main() {
  test('the narrowed config draws Item, Unit Cost, the custom fields and '
      'Line Total', () {
    expect(_narrowed.desktopColumns, [
      LineItemTableColumn.item,
      LineItemTableColumn.unitCost,
      const LineItemTableColumn.custom(1),
      const LineItemTableColumn.custom(2),
      LineItemTableColumn.lineTotal,
    ]);
    expect(_narrowed.hidingCustomSlots({1}).desktopColumns, [
      LineItemTableColumn.item,
      LineItemTableColumn.unitCost,
      const LineItemTableColumn.custom(2),
      LineItemTableColumn.lineTotal,
    ]);
    // The line still holds both: the phone and the dialog show them.
    expect(_narrowed.hidingCustomSlots({1}).customFields, hasLength(2));
  });

  late List<List<LineItem>> emitted;
  late Services services;

  Future<GoRouter> pump(
    WidgetTester tester, {
    LineItemColumnConfig? config,
    LineItemTableDesktopController? controller,
    bool admin = true,
    Set<int> hidden = const {},
  }) async {
    emitted = <List<LineItem>>[];
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Co', isAdmin: admin, isOwner: admin),
      ],
    );
    addTearDown(fixture.dispose);
    services = fixture.services;
    for (final slot in hidden) {
      await services.lineItemHiddenColumns.setHidden(
        'co1',
        task: false,
        slot: slot,
        hidden: true,
      );
    }
    // US dollars, so a figure renders at all — `money` is blank for a
    // currency the statics don't hold.
    await fixture.services.statics.applyStatic(<String, dynamic>{
      'currencies': [
        {
          'id': '1',
          'name': 'US Dollar',
          'code': 'USD',
          'symbol': r'$',
          'precision': 2,
          'thousand_separator': ',',
          'decimal_separator': '.',
          'swap_currency_symbol': false,
          'exchange_rate': 1,
        },
      ],
    });
    await fixture.services.formatterFor('co1');
    final router = GoRouter(
      initialLocation: '/invoices/new',
      routes: [
        GoRoute(
          path: '/invoices/new',
          builder: (context, state) => Scaffold(
            body: _Host(
              initial: [_line()],
              config: config ?? _narrowed,
              onChanged: emitted.add,
              controller: controller,
            ),
          ),
        ),
        GoRoute(
          path: '/settings/invoice_design/:tab',
          builder: (context, state) =>
              Scaffold(body: Text('design ${state.pathParameters['tab']}')),
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
    await tester.pump(const Duration(milliseconds: 50));
    return router;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a column off the list is not drawn', (tester) async {
    await pump(tester);

    expect(find.text('ITEM'), findsOneWidget);
    expect(find.text('UNIT COST'), findsOneWidget);
    expect(find.text('LINE TOTAL'), findsOneWidget);
    for (final header in ['DESCRIPTION', 'QUANTITY', 'DISCOUNT', 'TAX']) {
      expect(find.text(header), findsNothing, reason: header);
    }
    expect(find.text('Hidden note'), findsNothing);
    // Nothing hidden on this device: every custom field shows, as React.
    expect(find.text('SERIAL'), findsOneWidget);
    expect(find.text('BATCH'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('an edit, then a save, keeps every hidden value', (tester) async {
    final controller = LineItemTableDesktopController();
    // Serial hidden on this device.
    await pump(tester, controller: controller, hidden: {1});
    expect(find.text('SERIAL'), findsNothing);
    expect(find.text('SN-1'), findsNothing);
    expect(find.text('BATCH'), findsOneWidget);

    final cost = find.descendant(
      of: find.byKey(const ValueKey('unitCost')).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(cost, '12');
    // Saved inside the cell's debounce: the save path's flush commits it.
    controller.flushPending();
    await tester.pump();

    final saved = emitted.last.single;
    expect(saved.cost, Decimal.fromInt(12));
    expect(saved.productKey, 'Widget');
    expect(saved.notes, 'Hidden note');
    expect(saved.quantity, Decimal.fromInt(3));
    expect(saved.discount, Decimal.fromInt(5));
    expect(saved.taxName1, 'VAT');
    expect(saved.taxRate1, Decimal.fromInt(20));
    expect(saved.customValue1, 'SN-1');

    // And the debounce's own commit, after the flush, changes nothing.
    await tester.pump(const Duration(milliseconds: 300));
    expect(emitted.last.single, saved);
    await teardown(tester);
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('line_item_edit_columns')));
    await tester.pump();
  }

  testWidgets('the menu hides a custom field for this company and table only', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Edit Columns',
      ),
      findsOneWidget,
    );
    await openMenu(tester);
    final serial = find.byWidgetPredicate(
      (w) =>
          w is CheckboxMenuButton &&
          w.key == const ValueKey('line_item_column_custom_1'),
    );
    expect(tester.widget<CheckboxMenuButton>(serial).value, isTrue);

    // Two frames: a menu item's activation lands a frame after the tap.
    await tester.tap(serial);
    await tester.pump();
    await tester.pump();
    expect(find.text('SERIAL'), findsNothing);
    expect(find.text('BATCH'), findsOneWidget);
    expect(tester.widget<CheckboxMenuButton>(serial).value, isFalse);
    final prefs = services.lineItemHiddenColumns;
    expect(prefs.hiddenSlots('co1', task: false), {1});
    expect(prefs.hiddenSlots('co1', task: true), isEmpty);
    expect(prefs.hiddenSlots('co2', task: false), isEmpty);

    // And back.
    await tester.tap(serial);
    await tester.pump();
    await tester.pump();
    expect(find.text('SERIAL'), findsOneWidget);
    expect(prefs.value, isEmpty);
    await teardown(tester);
  });

  testWidgets('the settings entry opens the Invoice Design tab the columns '
      'come from', (tester) async {
    final router = await pump(tester);
    await openMenu(tester);
    final entry = find.byKey(const ValueKey('line_item_columns_settings'));
    expect(
      find.descendant(of: entry, matching: find.text('Product Columns')),
      findsOneWidget,
    );
    await tester.tap(entry);
    await tester.pump();
    await tester.pump();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/invoice_design/product_columns',
    );
    await teardown(tester);
  });

  testWidgets('a non-admin gets the custom-field toggles, not the settings '
      'entry', (tester) async {
    await pump(tester, admin: false);
    await openMenu(tester);
    expect(find.widgetWithText(CheckboxMenuButton, 'Serial'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('line_item_columns_settings')),
      findsNothing,
    );
    await teardown(tester);
  });

  testWidgets('a non-admin with no custom fields gets no menu', (tester) async {
    await pump(
      tester,
      admin: false,
      config: const LineItemColumnConfig().forCompany(
        const Company(
          id: 'co1',
          enableProductQuantity: true,
          settings: CompanySettings(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('line_item_edit_columns')), findsNothing);
    await teardown(tester);
  });

  testWidgets('no company columns yet: every field, and no link', (
    tester,
  ) async {
    await pump(
      tester,
      config: const LineItemColumnConfig(showDiscount: true, taxColumnCount: 1),
    );
    for (final header in [
      'ITEM',
      'DESCRIPTION',
      'UNIT COST',
      'QUANTITY',
      'DISCOUNT',
      'TAX',
      'LINE TOTAL',
    ]) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.byKey(const ValueKey('line_item_edit_columns')), findsNothing);
    await teardown(tester);
  });

  testWidgets('Tax Amount and Gross Line Total are read-only figures', (
    tester,
  ) async {
    final config = const LineItemColumnConfig(taxColumnCount: 1).forCompany(
      const Company(
        id: 'co1',
        enableProductQuantity: true,
        enabledItemTaxRates: 1,
        settings: CompanySettings(
          pdfVariables: {
            PdfVariableSection.productColumns: [
              r'$product.item',
              r'$product.tax_amount',
              r'$product.gross_line_total',
              r'$product.line_total',
            ],
          },
        ),
      ),
    );
    await pump(tester, config: config);

    // 10 x 3 less no document discount = 30, VAT 20% = 6, gross 36. (The
    // line's own 5 discount is a percent on an invoice: 28.50, 5.70, 34.20.)
    Finder figure(String id, String text) => find.descendant(
      of: find.byKey(ValueKey(id)).first,
      matching: find.textContaining(text),
    );
    for (
      var i = 0;
      i < 15 && figure('taxAmount', r'$').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(figure('taxAmount', r'$5.70'), findsOneWidget);
    expect(figure('grossLineTotal', r'$34.20'), findsOneWidget);
    // Neither is a field.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('taxAmount')).first,
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    await teardown(tester);
  });
}
