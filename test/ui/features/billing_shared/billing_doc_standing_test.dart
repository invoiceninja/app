// The standing card's figures (`billing_doc_standing.dart`): Amount and the
// balance side by side, zero included, and an invoice's Paid to Date always —
// the 5.1.30 figures, restored after a "one lead figure" pass left a paid
// invoice with only its amount. A draft's balance figure is its amount: the
// server keeps a draft's balance at 0, and "Balance Due $0.00" on a draft said
// nothing was owed.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/credit_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/domain/billing/billing_doc_fields.dart';
import 'package:admin/data/models/domain/credit.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/ui/core/detail/standing_card.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/ui/features/billing_shared/detail/billing_doc_standing.dart';
import 'package:admin/utils/formatting.dart';

import '../../../_localization_helper.dart';

final _formatter = Formatter(
  settings: const CompanyFormatSettings(
    currencyId: '1',
    countryId: '840',
    dateFormatId: 'X',
    useCommaAsDecimalPlace: false,
    showCurrencyCode: false,
    enableMilitaryTime: false,
    locale: '',
  ),
  // A real currency: without one `money` prints nothing, and every value
  // below would compare blank to blank.
  currencies: {
    '1': Currency(
      id: '1',
      name: 'US Dollar',
      code: 'USD',
      symbol: r'$',
      precision: 2,
      thousandSeparator: ',',
      decimalSeparator: '.',
      swapCurrencySymbol: false,
      exchangeRate: Decimal.one,
    ),
  },
  countries: const {},
  dateFormats: const {'X': DatetimeFormat(id: 'X', format: 'd/MMM/yyyy')},
);

// status_id wire ids: 1 draft, 2 sent, 3 partial, 4 paid, 5 cancelled,
// 6 reversed. No client, so the currency resolves without `Services`.
Invoice _invoice(String status, {required String balance, String paid = '0'}) =>
    Invoice.fromApi(InvoiceApi(id: 'i1', statusId: status)).copyWith(
      amount: Decimal.fromInt(500),
      balance: Decimal.parse(balance),
      paidToDate: Decimal.parse(paid),
    );

Credit _credit(String status, {required String balance}) => Credit.fromApi(
  CreditApi(id: 'c1', statusId: status),
).copyWith(amount: Decimal.fromInt(500), balance: Decimal.parse(balance));

void main() {
  Future<({List<StandingFigure> primary, List<StandingFigure> secondary})>
  figures(
    WidgetTester tester, {
    required BillingDocType type,
    required BillingDocFields doc,
    Decimal? settled,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: BillingDocStanding(
            type: type,
            doc: doc,
            formatter: _formatter,
            settled: settled,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = tester.widget<StandingCard>(find.byType(StandingCard));
    return (primary: card.primary, secondary: card.secondary);
  }

  Map<String, String> pairs(List<StandingFigure> figures) => {
    for (final f in figures) f.label: f.value,
  };

  testWidgets('a paid invoice shows Amount, Balance Due \$0.00 and Paid to '
      'Date, as 5.1.30 did', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('4', balance: '0', paid: '500'),
      settled: Decimal.fromInt(500),
    );
    expect(pairs(f.primary), {'Amount': r'$500.00', 'Balance Due': r'$0.00'});
    expect(pairs(f.secondary), {'Paid to Date': r'$500.00'});
  });

  testWidgets('a sent invoice shows Paid to Date at zero too', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('2', balance: '500'),
      settled: Decimal.zero,
    );
    expect(pairs(f.primary), {'Amount': r'$500.00', 'Balance Due': r'$500.00'});
    expect(pairs(f.secondary), {'Paid to Date': r'$0.00'});
  });

  testWidgets('a partial invoice shows what is left and what was paid', (
    tester,
  ) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('3', balance: '300', paid: '200'),
      settled: Decimal.fromInt(200),
    );
    expect(pairs(f.primary), {'Amount': r'$500.00', 'Balance Due': r'$300.00'});
    expect(pairs(f.secondary), {'Paid to Date': r'$200.00'});
  });

  testWidgets('a draft invoice\'s Balance Due is its amount, not the \$0 the '
      'server stores', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('1', balance: '0'),
      settled: Decimal.zero,
    );
    expect(pairs(f.primary), {'Amount': r'$500.00', 'Balance Due': r'$500.00'});
    expect(f.primary.first.label, 'Amount', reason: 'Amount leads');
  });

  for (final (label, status) in [('cancelled', '5'), ('reversed', '6')]) {
    testWidgets('a $label invoice owes nothing and says so', (tester) async {
      final f = await figures(
        tester,
        type: BillingDocType.invoice,
        doc: _invoice(status, balance: '0'),
        settled: Decimal.zero,
      );
      expect(pairs(f.primary), {'Amount': r'$500.00', 'Balance Due': r'$0.00'});
    });
  }

  testWidgets('an overpaid invoice shows its negative balance', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('4', balance: '-50', paid: '550'),
      settled: Decimal.fromInt(550),
    );
    expect([for (final x in f.primary) x.label], ['Amount', 'Balance Due']);
    expect(pairs(f.primary)['Balance Due'], contains('50.00'));
    expect(pairs(f.secondary), {'Paid to Date': r'$550.00'});
  });

  testWidgets('a credit shows Amount and Credit Remaining — a draft\'s is its '
      'amount — and Applied only once something was', (tester) async {
    var f = await figures(
      tester,
      type: BillingDocType.credit,
      doc: _credit('1', balance: '0'),
      settled: Decimal.zero,
    );
    expect(pairs(f.primary), {
      'Amount': r'$500.00',
      'Credit Remaining': r'$500.00',
    });
    expect(f.secondary, isEmpty);
    f = await figures(
      tester,
      type: BillingDocType.credit,
      doc: _credit('3', balance: '300'),
      settled: Decimal.fromInt(200),
    );
    expect(pairs(f.primary), {
      'Amount': r'$500.00',
      'Credit Remaining': r'$300.00',
    });
    expect(pairs(f.secondary), {'Applied': r'$200.00'});
  });

  testWidgets('a quote shows its amount alone', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.quote,
      doc: _invoice('2', balance: '500'),
    );
    expect(pairs(f.primary), {'Amount': r'$500.00'});
    expect(f.secondary, isEmpty);
  });
}
