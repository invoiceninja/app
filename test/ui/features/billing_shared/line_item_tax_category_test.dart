// "When I save my quote it erases all the taxes on physical goods": with the
// company's Calculate Taxes on, the server replaces every line's tax names and
// rates on save with what the line's tax category (`tax_id`) and the client's
// location call for — only an Override (7) line keeps its own
// (`InvoiceItemSum::calcTaxesAutomatically`, `BaseRule::tax`). The editor
// offered rate pickers on every line regardless, so users typed taxes the
// save threw away. React (`useResolveInputField`) and admin-portal show a
// per-line Tax Category instead; so does this app now, wide and narrow.

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/product.dart';
import 'package:admin/domain/product_tax_categories.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_column_config.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_edit_dialog.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart';

import '../../../_localization_helper.dart';
import '../shell/_shell_test_helpers.dart';

const _categories = LineItemColumnConfig(
  taxColumnCount: 1,
  useTaxCategories: true,
);
const _rates = LineItemColumnConfig(taxColumnCount: 1);

LineItem _line(String taxId) => emptyLineItem().copyWith(
  productKey: 'Widget',
  notes: 'A widget',
  cost: Decimal.fromInt(10),
  taxName1: 'VAT',
  taxRate1: Decimal.fromInt(20),
  taxCategoryId: taxId,
);

/// Feeds the emitted list back, as the real edit layouts do.
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    required this.config,
    required this.onChanged,
  });

  final List<LineItem> initial;
  final LineItemColumnConfig config;
  final ValueChanged<List<LineItem>> onChanged;

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
    newItemFactory: () =>
        emptyLineItem().copyWith(taxCategoryId: kDefaultTaxCategoryId),
    config: widget.config,
  );
}

void main() {
  group('LineItemColumnConfig.forCompany', () {
    Company company({required bool calculateTaxes}) => Company(
      id: 'co',
      enabledItemTaxRates: 1,
      calculateTaxes: calculateTaxes,
      settings: const CompanySettings(),
    );

    test('a client document gets categories only while the company '
        'calculates taxes', () {
      expect(
        _categories.forCompany(company(calculateTaxes: true)).useTaxCategories,
        isTrue,
      );
      expect(
        _categories.forCompany(company(calculateTaxes: false)).useTaxCategories,
        isFalse,
      );
    });

    test('a purchase order (the minimal config) never does', () {
      expect(
        LineItemColumnConfig.minimal
            .forCompany(company(calculateTaxes: true))
            .useTaxCategories,
        isFalse,
      );
    });

    test('before the company loads, the guess is rates', () {
      expect(_categories.forCompany(null).useTaxCategories, isFalse);
    });
  });

  group('a picked product', () {
    Product product(String taxId) => Product(
      id: 'p1',
      productKey: 'Widget',
      notes: '',
      cost: Decimal.zero,
      price: Decimal.fromInt(10),
      quantity: Decimal.one,
      maxQuantity: Decimal.zero,
      productImage: '',
      inStockQuantity: Decimal.zero,
      stockNotification: false,
      stockNotificationThreshold: Decimal.zero,
      taxName1: '',
      taxRate1: Decimal.zero,
      taxName2: '',
      taxRate2: Decimal.zero,
      taxName3: '',
      taxRate3: Decimal.zero,
      taxId: taxId,
      customValue1: '',
      customValue2: '',
      customValue3: '',
      customValue4: '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      archivedAt: null,
      isDeleted: false,
    );

    test('keeps its own category', () {
      expect(lineItemFromProduct(product('2')).taxCategoryId, '2');
    });

    test('with none bills as Physical Goods, as React fills it', () {
      expect(lineItemFromProduct(product('')).taxCategoryId, '1');
    });

    test('on a purchase order keeps its blank', () {
      expect(
        lineItemFromProduct(product(''), vendorDoc: true).taxCategoryId,
        '',
      );
    });
  });

  group('wide table', () {
    late List<List<LineItem>> emitted;

    Future<void> pump(
      WidgetTester tester, {
      required List<LineItem> items,
      required LineItemColumnConfig config,
    }) async {
      emitted = <List<LineItem>>[];
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fixture = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Co')],
      );
      addTearDown(fixture.dispose);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          _Host(initial: items, config: config, onChanged: emitted.add),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// Tax slot 1 on row [row] (0-based; the header's cells carry no key).
    Finder slot(int row) => find.byKey(const ValueKey('tax_1')).at(row);

    Finder rateField(int row) =>
        find.descendant(of: slot(row), matching: find.byType(TextField));

    testWidgets('a Physical Goods line shows its category and no rate field', (
      tester,
    ) async {
      await pump(tester, items: [_line('1')], config: _categories);

      expect(
        find.descendant(of: slot(0), matching: find.text('Physical Goods')),
        findsOneWidget,
      );
      expect(rateField(0), findsNothing);
      await teardown(tester);
    });

    testWidgets('an Override line keeps its rate field, with a way back', (
      tester,
    ) async {
      await pump(tester, items: [_line('7')], config: _categories);

      expect(rateField(0), findsOneWidget);
      final back = find.descendant(
        of: slot(0),
        matching: find.byIcon(Icons.repeat),
      );
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pump(const Duration(milliseconds: 50));

      expect(emitted.last.first.taxCategoryId, '1');
      expect(rateField(0), findsNothing);
      // The rates the line held ride along untouched — the server recomputes.
      expect(emitted.last.first.taxName1, 'VAT');
      await teardown(tester);
    });

    testWidgets('picking a category writes tax_id, and Override brings the '
        'rates back', (tester) async {
      await pump(tester, items: [_line('1')], config: _categories);

      await tester.tap(
        find.descendant(of: slot(0), matching: find.text('Physical Goods')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Services').last);
      await tester.pumpAndSettle();

      expect(emitted.last.first.taxCategoryId, '2');
      expect(emitted.last.first.toApiJson()['tax_id'], '2');
      expect(rateField(0), findsNothing);

      await tester.tap(
        find.descendant(of: slot(0), matching: find.text('Services')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Override Tax').last);
      await tester.pumpAndSettle();

      expect(emitted.last.first.taxCategoryId, '7');
      expect(rateField(0), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('the ghost row shows its category but cannot commit one', (
      tester,
    ) async {
      await pump(tester, items: [_line('1')], config: _categories);

      // Row 1 is the trailing "Add an item" row.
      final ghost = find.descendant(
        of: slot(1),
        matching: find.text('Physical Goods'),
      );
      expect(ghost, findsOneWidget);
      await tester.tap(ghost, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Services'), findsNothing);
      expect(emitted, isEmpty);
      await teardown(tester);
    });

    testWidgets('Calculate Taxes off: every line keeps its rate field', (
      tester,
    ) async {
      await pump(tester, items: [_line('1')], config: _rates);

      expect(rateField(0), findsOneWidget);
      expect(find.text('Physical Goods'), findsNothing);
      expect(find.byIcon(Icons.repeat), findsNothing);
      await teardown(tester);
    });
  });

  group('narrow edit dialog', () {
    Future<LineItem? Function()> open(
      WidgetTester tester, {
      required LineItem initial,
      required LineItemColumnConfig config,
    }) async {
      LineItem? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showLineItemEditDialog(
                    context,
                    initial: initial,
                    config: config,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    Finder category() => find.byKey(const ValueKey('line_item_tax_category'));

    testWidgets('a Physical Goods line shows its category and no rate fields', (
      tester,
    ) async {
      await open(tester, initial: _line('1'), config: _categories);

      expect(category(), findsOneWidget);
      expect(
        find.descendant(of: category(), matching: find.text('Physical Goods')),
        findsOneWidget,
      );
      expect(find.text('Tax Name 1'), findsNothing);
      expect(find.text('Tax Rate 1'), findsNothing);
    });

    testWidgets('an Override line shows its rate fields', (tester) async {
      await open(tester, initial: _line('7'), config: _categories);

      expect(category(), findsOneWidget);
      expect(find.text('Tax Name 1'), findsOneWidget);
    });

    testWidgets('switching category writes tax_id and toggles the rates', (
      tester,
    ) async {
      final result = await open(
        tester,
        initial: _line('1'),
        config: _categories,
      );

      await tester.tap(category());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Override Tax').last);
      await tester.pumpAndSettle();
      expect(find.text('Tax Name 1'), findsOneWidget);

      await tester.tap(category());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Services').last);
      await tester.pumpAndSettle();
      expect(find.text('Tax Name 1'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result()?.taxCategoryId, '2');
      expect(result()?.toApiJson()['tax_id'], '2');
    });

    testWidgets('Calculate Taxes off: no category, today\'s rate fields', (
      tester,
    ) async {
      await open(tester, initial: _line('1'), config: _rates);

      expect(category(), findsNothing);
      expect(find.text('Tax Name 1'), findsOneWidget);
    });
  });
}
