// The expense Amount card's tax tiers. Their count used to be latched on the
// FIRST build — which on a new expense ran before the company row arrived — so
// a company with expense taxes enabled kept the "tax rates are disabled" hint
// and no tax inputs at all.

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_tax_section.dart';

import '../../billing_shared/edit/_billing_edit_harness.dart';
import '../../shell/_shell_test_helpers.dart';

void main() {
  Widget section({Decimal? taxTotal, Decimal? total, bool inclusive = false}) =>
      ExpenseTaxSection(
        companyId: kHarnessCompanyId,
        amount: Decimal.zero,
        currencyId: '1',
        taxTotal: taxTotal ?? Decimal.zero,
        total: total ?? Decimal.zero,
        amountError: null,
        taxNames: const ['', '', ''],
        taxRates: [Decimal.zero, Decimal.zero, Decimal.zero],
        taxAmounts: [Decimal.zero, Decimal.zero, Decimal.zero],
        usesInclusiveTaxes: inclusive,
        calculateTaxByAmount: false,
        onAmountChanged: (_) {},
        onTaxNameChanged: (_, _) {},
        onTaxRateChanged: (_, _) {},
        onTaxAmountChanged: (_, _) {},
        onUsesInclusiveTaxesChanged: (_) {},
        onCalculateByAmountChanged: (_) {},
      );

  Future<void> setRates(ShellFixture fixture, int enabled) async {
    final db = fixture.db;
    await (db.update(db.companies)
          ..where((c) => c.id.equals(kHarnessCompanyId)))
        .write(CompaniesCompanion(enabledExpenseTaxRates: Value(enabled)));
  }

  /// The amount field, plus a name + rate pair per tier (no bundled rates, so
  /// each tier is the freeform pair).
  int tiers(WidgetTester tester) =>
      (tester.widgetList(find.byType(EntityEditField)).length - 1) ~/ 2;

  testWidgets('grows when the company answers after the first frame, and '
      'never shrinks', (tester) async {
    setWindow(tester, 1200);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);

    await tester.pumpWidget(wrapWithShell(fixture.services, section()));
    await settle(tester);
    expect(tiers(tester), 0);
    expect(find.text('Item tax rates are disabled'), findsOneWidget);

    await setRates(fixture, 2);
    await settle(tester);
    expect(tiers(tester), 2);
    expect(find.text('Item tax rates are disabled'), findsNothing);

    await setRates(fixture, 1);
    await settle(tester);
    expect(tiers(tester), 2);
    await unmount(tester, fixture);
  });
  // Beta feedback: admin-portal printed "Expense Total: <gross>" in the edit
  // footer, and the rebuild showed the amount with no figure including tax.
  testWidgets('states the tax and the Expense Total once taxes are on, and '
      'neither while they are off', (tester) async {
    setWindow(tester, 1200);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        section(taxTotal: Decimal.parse('10'), total: Decimal.parse('110')),
      ),
    );
    await settle(tester);
    expect(find.text('Expense Total'), findsNothing);

    await setRates(fixture, 1);
    await settle(tester);
    expect(find.text('Expense Total'), findsOneWidget);
    // Exclusive: the net is the amount the user typed, so no row repeats it.
    expect(find.text('Net Amount'), findsNothing);
    // The harness has no currency catalog, so the figures themselves are
    // blank here — the formatting is `Formatter.money`'s own test.
    await unmount(tester, fixture);
  });

  // Inclusive: the total IS the amount typed, so the net is the figure added.
  testWidgets('an inclusive tax adds the Net Amount row', (tester) async {
    setWindow(tester, 1200);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    await setRates(fixture, 1);

    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        section(
          taxTotal: Decimal.parse('10'),
          total: Decimal.parse('110'),
          inclusive: true,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Net Amount'), findsOneWidget);
    expect(find.text('Expense Total'), findsOneWidget);
    await unmount(tester, fixture);
  });
}
