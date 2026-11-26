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
/// and Show Product Quantity off, so those two columns go as well.
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
  test('the narrowed config draws Item, Unit Cost, Line Total only', () {
    expect(_narrowed.desktopColumns, [
      LineItemTableColumn.item,
      LineItemTableColumn.unitCost,
      LineItemTableColumn.lineTotal,
    ]);
  });

  late List<List<LineItem>> emitted;

  Future<GoRouter> pump(
    WidgetTester tester, {
    LineItemColumnConfig? config,
    LineItemTableDesktopController? controller,
  }) async {
    emitted = <List<LineItem>>[];
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);
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
    await teardown(tester);
  });

  testWidgets('an edit, then a save, keeps every hidden value', (tester) async {
    final controller = LineItemTableDesktopController();
    await pump(tester, controller: controller);

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

  testWidgets('Edit Columns opens the Invoice Design tab the columns come '
      'from', (tester) async {
    final router = await pump(tester);

    final button = find.byKey(const ValueKey('line_item_edit_columns'));
    expect(button, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Edit Columns',
      ),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/settings/invoice_design/product_columns',
    );
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
