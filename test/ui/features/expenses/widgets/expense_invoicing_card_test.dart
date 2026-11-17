// The expense form's Invoicing card (shared with Recurring Expense) and the
// Amount card's link to Tax Settings.

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_invoicing_card.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_tax_section.dart';

import '../../billing_shared/edit/_billing_edit_harness.dart';
import '../../shell/_shell_test_helpers.dart';

void main() {
  Future<ShellFixture> fixture(WidgetTester tester) async {
    setWindow(tester, 1200);
    final f = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(f.dispose);
    return f;
  }

  Widget conversion({String invoiceCurrencyId = ''}) =>
      ExpenseCurrencyConversionFields(
        expenseCurrencyId: '1',
        invoiceCurrencyId: invoiceCurrencyId,
        exchangeRate: Decimal.one,
        convertedAmount: Decimal.zero,
        useCommaAsDecimalPlace: false,
        onInvoiceCurrencyChanged: (_) {},
        onExchangeRateChanged: (_) {},
        onConvertedAmountChanged: (_) {},
        errorFor: (_) => null,
      );

  testWidgets('Client and Project always show; Should be invoiced reveals '
      'Invoice Documents and the currency conversion', (tester) async {
    final f = await fixture(tester);
    var invoiced = false;
    await tester.pumpWidget(
      wrapWithShell(
        f.services,
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ExpenseInvoicingCard(
              billTo: const Text('BILL TO'),
              shouldBeInvoiced: invoiced,
              onShouldBeInvoicedChanged: (v) => setState(() => invoiced = v),
              invoiceDocuments: true,
              onInvoiceDocumentsChanged: (_) {},
              conversion: conversion(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('BILL TO'), findsOneWidget);
    expect(find.text('Should be invoiced'), findsOneWidget);
    expect(find.text('Enable the expense to be invoiced'), findsOneWidget);
    expect(find.text('Invoice Documents'), findsNothing);
    expect(find.text('Currency conversion'), findsNothing);

    await tester.tap(find.text('Should be invoiced'));
    await settle(tester);

    expect(invoiced, isTrue);
    expect(find.text('BILL TO'), findsOneWidget);
    expect(find.text('Invoice Documents'), findsOneWidget);
    expect(find.text('Currency conversion'), findsOneWidget);
    await unmount(tester, f);
  });

  testWidgets('the rate and the converted amount appear, both editable, once '
      'the invoice currency differs', (tester) async {
    final f = await fixture(tester);
    await tester.pumpWidget(wrapWithShell(f.services, conversion()));
    await settle(tester);
    expect(find.text('Exchange Rate'), findsNothing);
    expect(find.text('Converted Amount'), findsNothing);

    await tester.pumpWidget(
      wrapWithShell(f.services, conversion(invoiceCurrencyId: '3')),
    );
    await settle(tester);
    for (final label in ['Exchange Rate', 'Converted Amount']) {
      final field = tester.widget<EntityEditField>(
        find.ancestor(
          of: find.text(label).first,
          matching: find.byType(EntityEditField),
        ),
      );
      expect(field.readOnly, isFalse, reason: label);
    }
    await unmount(tester, f);
  });

  Widget taxSection() => ExpenseTaxSection(
    companyId: kHarnessCompanyId,
    amount: Decimal.zero,
    currencyId: '1',
    taxTotal: Decimal.zero,
    total: Decimal.zero,
    amountError: null,
    taxNames: const ['', '', ''],
    taxRates: [Decimal.zero, Decimal.zero, Decimal.zero],
    taxAmounts: [Decimal.zero, Decimal.zero, Decimal.zero],
    usesInclusiveTaxes: false,
    calculateTaxByAmount: false,
    onAmountChanged: (_) {},
    onTaxNameChanged: (_, _) {},
    onTaxRateChanged: (_, _) {},
    onTaxAmountChanged: (_, _) {},
    onUsesInclusiveTaxesChanged: (_) {},
    onCalculateByAmountChanged: (_) {},
    amountBeside: const Text('CURRENCY'),
    amountTrailing: const Text('DATE'),
  );

  testWidgets('the date sits on the amount row where the card has room', (
    tester,
  ) async {
    final f = await fixture(tester);
    await tester.pumpWidget(wrapWithShell(f.services, taxSection()));
    await settle(tester);
    final amount = tester.getTopLeft(find.byType(EntityEditField).first);
    expect(tester.getTopLeft(find.text('DATE')).dy, amount.dy);
    expect(
      tester.getTopLeft(find.text('DATE')).dx,
      greaterThan(tester.getTopLeft(find.text('CURRENCY')).dx),
    );
    await unmount(tester, f);
  });

  testWidgets('with expense taxes off, the hint links to Tax Settings with a '
      'full-size target on touch', (tester) async {
    final f = await fixture(tester);
    await tester.pumpWidget(wrapWithShell(f.services, taxSection()));
    await settle(tester);
    expect(find.text('Item tax rates are disabled'), findsOneWidget);
    final link = find.widgetWithText(TextButton, 'Tax Settings');
    expect(link, findsOneWidget);
    expect(tester.getSize(link).height, greaterThanOrEqualTo(44));
    await unmount(tester, f);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
