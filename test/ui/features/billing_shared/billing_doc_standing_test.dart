// The standing card's one lead rule (`billing_doc_standing.dart`): the balance
// leads only while it is open — not zero, and not a draft, cancelled or
// reversed document. The bug it fixes: a draft invoice (the server keeps its
// balance at 0) led with "Balance Due $0.00".

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
  currencies: const {},
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
  Future<({List<String> primary, List<String> secondary})> figures(
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
    return (
      primary: [for (final f in card.primary) f.label],
      secondary: [for (final f in card.secondary) f.label],
    );
  }

  testWidgets('a draft invoice leads with its amount, not Balance Due \$0', (
    tester,
  ) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('1', balance: '0'),
    );
    expect(f.primary, ['Amount']);
    expect(f.secondary, isEmpty);
  });

  testWidgets('a draft invoice with a locally stamped balance still leads '
      'with its amount, and does not print the balance', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('1', balance: '500'),
    );
    expect(f.primary, ['Amount']);
    expect(f.secondary, isEmpty);
  });

  for (final (label, status) in [('cancelled', '5'), ('reversed', '6')]) {
    testWidgets('a $label invoice leads with its amount', (tester) async {
      final f = await figures(
        tester,
        type: BillingDocType.invoice,
        doc: _invoice(status, balance: '0'),
      );
      expect(f.primary, ['Amount']);
    });
  }

  testWidgets('a sent invoice leads with Balance Due, the amount beside', (
    tester,
  ) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('2', balance: '500'),
    );
    expect(f.primary, ['Balance Due']);
    expect(f.secondary, ['Amount']);
  });

  testWidgets('a partial invoice keeps Balance Due and shows what was paid', (
    tester,
  ) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('3', balance: '300', paid: '200'),
      settled: Decimal.fromInt(200),
    );
    expect(f.primary, ['Balance Due']);
    expect(f.secondary, ['Amount', 'Paid to Date']);
  });

  testWidgets('a paid invoice leads with its amount and does not repeat it as '
      'Paid to Date', (tester) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('4', balance: '0', paid: '500'),
      settled: Decimal.fromInt(500),
    );
    expect(f.primary, ['Amount']);
    expect(f.secondary, isEmpty);
  });

  testWidgets('an overpaid invoice leads with its (negative) balance', (
    tester,
  ) async {
    final f = await figures(
      tester,
      type: BillingDocType.invoice,
      doc: _invoice('4', balance: '-50', paid: '550'),
      settled: Decimal.fromInt(550),
    );
    expect(f.primary, ['Balance Due']);
    expect(f.secondary, ['Amount', 'Paid to Date']);
  });

  testWidgets('a draft credit leads with its amount; a sent one with what '
      'remains', (tester) async {
    var f = await figures(
      tester,
      type: BillingDocType.credit,
      doc: _credit('1', balance: '500'),
    );
    expect(f.primary, ['Amount']);
    f = await figures(
      tester,
      type: BillingDocType.credit,
      doc: _credit('2', balance: '500'),
    );
    expect(f.primary, ['Credit Remaining']);
  });
}
