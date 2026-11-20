// The document taxes on the billing edit screens (a card on the narrow
// layout, inside the totals card on the wide one). A tier shows once the
// document carries it or "+ Add tax" opens it, up to the company's
// `enabled_tax_rates`. The section used to be latched on the FIRST build —
// which on a new document ran before the company row arrived — so a company
// with document taxes enabled got no card at all. The inclusive-tax switch
// is not in this card: it is on the document's Settings tab, as in React
// (beta feedback — a US user never changes it, and it was a full-width row
// beside the totals).

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/tax_rate_api_model.dart';
import 'package:admin/data/models/domain/tax_rate.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/billing_shared/edit/billing_tax_surcharge_section.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

void main() {
  Future<ShellFixture> fixtureWith(
    WidgetTester tester, {
    int enabledTaxRates = 0,
    int enabledItemTaxRates = 0,
  }) async {
    setWindow(tester, 1200);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    await setRates(
      fixture,
      enabledTaxRates: enabledTaxRates,
      enabledItemTaxRates: enabledItemTaxRates,
    );
    return fixture;
  }

  Widget section({
    bool comma = false,
    String name1 = '',
    Decimal? rate1,
    ValueChanged<String>? onName1,
    ValueChanged<String>? onRate1,
  }) => BillingTaxSurchargeSection(
    companyId: kHarnessCompanyId,
    useCommaAsDecimalPlace: comma,
    taxRows: [
      (
        name: name1,
        rate: rate1 ?? Decimal.zero,
        onName: onName1 ?? (_) {},
        onRate: onRate1 ?? (_) {},
      ),
      for (var i = 1; i < 3; i++)
        (name: '', rate: Decimal.zero, onName: (_) {}, onRate: (_) {}),
    ],
    surcharges: [
      for (var i = 0; i < 4; i++) (amount: Decimal.zero, onAmount: (_) {}),
    ],
  );

  /// Two fields (name + rate) per tier; nothing else in the card is one.
  int tiers(WidgetTester tester) =>
      tester.widgetList(find.byType(EntityEditField)).length ~/ 2;

  Finder inclusiveSwitch() =>
      find.widgetWithText(SwitchListTile, 'Inclusive Taxes');

  Finder addTax() => find.text('Add tax');

  testWidgets('+ Add tax opens tiers up to the company\'s enabled count', (
    tester,
  ) async {
    final fixture = await fixtureWith(tester, enabledTaxRates: 2);
    await tester.pumpWidget(wrapWithShell(fixture.services, section()));
    await settle(tester);
    expect(tiers(tester), 0, reason: 'no empty tier waits on the document');
    expect(inclusiveSwitch(), findsNothing, reason: 'on the Settings tab');

    await tester.tap(addTax());
    await settle(tester);
    expect(tiers(tester), 1);
    await tester.tap(addTax());
    await settle(tester);
    expect(tiers(tester), 2);
    expect(addTax(), findsNothing, reason: 'the company enables two');
    await unmount(tester, fixture);
  });

  testWidgets('no + Add tax where the company enables no document tax', (
    tester,
  ) async {
    final fixture = await fixtureWith(tester, enabledItemTaxRates: 1);
    await tester.pumpWidget(wrapWithShell(fixture.services, section()));
    await settle(tester);
    expect(addTax(), findsNothing);
    await unmount(tester, fixture);
  });

  testWidgets('a tier the document carries shows without + Add tax', (
    tester,
  ) async {
    final fixture = await fixtureWith(tester, enabledTaxRates: 1);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        section(name1: 'VAT', rate1: Decimal.fromInt(20)),
      ),
    );
    await settle(tester);
    expect(tiers(tester), 1);
    expect(addTax(), findsNothing);
    await unmount(tester, fixture);
  });

  testWidgets('+ Add tax appears when the company answers after the first '
      'frame, and an opened tier never shrinks', (tester) async {
    final fixture = await fixtureWith(tester, enabledItemTaxRates: 1);
    await tester.pumpWidget(wrapWithShell(fixture.services, section()));
    await settle(tester);
    expect(addTax(), findsNothing);

    await setRates(fixture, enabledTaxRates: 2, enabledItemTaxRates: 1);
    await settle(tester);
    await tester.tap(addTax());
    await settle(tester);
    await tester.tap(addTax());
    await settle(tester);
    expect(tiers(tester), 2);

    await setRates(fixture, enabledTaxRates: 1, enabledItemTaxRates: 1);
    await settle(tester);
    expect(tiers(tester), 2, reason: 'the card has no way to remove a tier');
    await unmount(tester, fixture);
  });

  testWidgets('collapses when nothing in it applies', (tester) async {
    // Taxed lines no longer keep the card up: the switch they kept it up
    // for moved to the Settings tab.
    final fixture = await fixtureWith(tester, enabledItemTaxRates: 1);
    await tester.pumpWidget(wrapWithShell(fixture.services, section()));
    await settle(tester);
    expect(inclusiveSwitch(), findsNothing);
    expect(find.text('Taxes'), findsNothing);
    await unmount(tester, fixture);
  });

  // Beta feedback: the company's "NYS Sales Tax 8.75%" was nowhere to be
  // picked — every tier was a bare name + rate pair.
  group('with configured tax rates', () {
    Future<ShellFixture> withRates(WidgetTester tester) async {
      final fixture = await fixtureWith(tester, enabledTaxRates: 1);
      await fixture.services.taxRates.applyBundle(
        companyId: kHarnessCompanyId,
        bundle: const [
          TaxRateApi(id: 'r1', name: 'NYS Sales Tax', rate: 8.75),
          TaxRateApi(id: 'r2', name: 'County Tax', rate: 4),
        ],
      );
      return fixture;
    }

    Finder picker() => find.byType(SearchableDropdownField<TaxRate>);

    testWidgets('each tier is a picker, and picking writes name and rate', (
      tester,
    ) async {
      final fixture = await withRates(tester);
      String? name;
      String? rate;
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          section(onName1: (v) => name = v, onRate1: (v) => rate = v),
        ),
      );
      await settle(tester);
      await tester.tap(addTax());
      await settle(tester);
      expect(picker(), findsOneWidget);
      expect(tiers(tester), 0, reason: 'no freeform pair beside the picker');

      await tester.tap(picker());
      await settle(tester);
      await tester.tap(find.text('NYS Sales Tax (8.75%)').last);
      await settle(tester);
      expect(name, 'NYS Sales Tax');
      expect(Decimal.parse(rate!), Decimal.parse('8.75'));
      await unmount(tester, fixture);
    });

    // Matched against the list, not shown as the stand-in entry: the stand-in
    // carries the same label and id, so only the open list tells them apart —
    // a stored 8.5% shows its own row ABOVE the list's 8.75%.
    testWidgets('a stored rate is matched to the list entry', (tester) async {
      final fixture = await withRates(tester);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          section(name1: 'NYS Sales Tax', rate1: Decimal.parse('8.75')),
        ),
      );
      await settle(tester);
      expect(find.text('NYS Sales Tax (8.75%)'), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('a stored rate that differs from the list shows its own', (
      tester,
    ) async {
      final fixture = await withRates(tester);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          section(name1: 'NYS Sales Tax', rate1: Decimal.parse('8.5')),
        ),
      );
      await settle(tester);
      expect(find.text('NYS Sales Tax (8.5%)'), findsOneWidget);
      await tester.tap(picker());
      await settle(tester);
      expect(find.text('NYS Sales Tax (8.75%)'), findsOneWidget);
      await unmount(tester, fixture);
    });

    // The server taxes nothing for a nameless tier, but an inclusive document
    // still backs every rate out of its prices, so it must stay visible.
    testWidgets('a nameless stored rate still shows', (tester) async {
      final fixture = await withRates(tester);
      await tester.pumpWidget(
        wrapWithShell(fixture.services, section(rate1: Decimal.parse('5'))),
      );
      await settle(tester);
      expect(find.text('5%'), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('clearing the picker writes no tax', (tester) async {
      final fixture = await withRates(tester);
      String? name;
      String? rate;
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          section(
            name1: 'NYS Sales Tax',
            rate1: Decimal.parse('8.75'),
            onName1: (v) => name = v,
            onRate1: (v) => rate = v,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Clear'));
      await settle(tester);
      expect(name, '');
      expect(rate, '0');
      await unmount(tester, fixture);
    });

    testWidgets('rates read in the company\'s decimal separator', (
      tester,
    ) async {
      final fixture = await withRates(tester);
      await tester.pumpWidget(
        wrapWithShell(fixture.services, section(comma: true)),
      );
      await settle(tester);
      await tester.tap(addTax());
      await settle(tester);
      await tester.tap(picker());
      await settle(tester);
      expect(find.text('NYS Sales Tax (8,75%)'), findsOneWidget);
      await unmount(tester, fixture);
    });

    // Before the rates list answers, the tier is the picker's placeholder —
    // never the freeform pair, which used to flash on every open.
    testWidgets('no freeform pair before the rates answer', (tester) async {
      final fixture = await withRates(tester);
      // A tier the document carries, so one is on screen from the first
      // frame — before the rates list answers.
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          section(name1: 'Old Tax', rate1: Decimal.parse('5')),
        ),
      );
      expect(find.byType(EntityEditField), findsNothing);
      await settle(tester);
      expect(picker(), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('a stored pair not in the list still shows', (tester) async {
      final fixture = await withRates(tester);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          section(name1: 'Old Tax', rate1: Decimal.parse('5')),
        ),
      );
      await settle(tester);
      expect(find.text('Old Tax (5%)'), findsOneWidget);
      await unmount(tester, fixture);
    });
  });
}

Future<void> setRates(
  ShellFixture fixture, {
  required int enabledTaxRates,
  required int enabledItemTaxRates,
}) async {
  final db = fixture.db;
  await (db.update(
    db.companies,
  )..where((c) => c.id.equals(kHarnessCompanyId))).write(
    CompaniesCompanion(
      enabledTaxRates: Value(enabledTaxRates),
      enabledItemTaxRates: Value(enabledItemTaxRates),
    ),
  );
}
