import 'package:decimal/decimal.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/models/domain/quote_status.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/country.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/ui/core/widgets/formatter_scope.dart';
import 'package:admin/ui/features/billing_shared/billing_row_subtitle.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_list_tile.dart';
import 'package:admin/ui/features/purchase_orders/view_models/purchase_order_edit_view_model.dart';
import 'package:admin/ui/features/purchase_orders/widgets/purchase_order_list_tile.dart';
import 'package:admin/ui/features/quotes/view_models/quote_edit_view_model.dart';
import 'package:admin/ui/features/quotes/widgets/quote_list_tile.dart';
import 'package:admin/utils/formatting.dart';

import '../../../_localization_helper.dart';

/// The narrow billing row's second line: "client · Due {date}", the date in
/// the overdue ink exactly when the row's own pill says past due / expired.
final _formatter = Formatter(
  settings: CompanyFormatSettings.fallback,
  currencies: {
    '1': Currency(
      id: '1',
      name: 'USD',
      code: 'USD',
      symbol: r'$',
      precision: 2,
      thousandSeparator: ',',
      decimalSeparator: '.',
      swapCurrencySymbol: false,
      exchangeRate: Decimal.one,
    ),
  },
  countries: const {
    '840': Country(
      id: '840',
      name: 'United States',
      iso2: 'US',
      iso3: 'USA',
      swapCurrencySymbol: false,
      thousandSeparator: '',
      decimalSeparator: '',
      swapPostalCode: false,
    ),
  },
  dateFormats: const {'5': DatetimeFormat(id: '5', format: 'MMM d, yyyy')},
);

String _fmt(Date d) => _formatter.date(d.toIso());

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Formatter? formatter,
  bool withFormatter = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: FormatterScope(
          formatter: withFormatter ? (formatter ?? _formatter) : null,
          child: SizedBox(width: 390, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  final today = Date.today();

  group('BillingRowSubtitle', () {
    testWidgets('party, separator and the date on one line', (tester) async {
      final due = Date(2030, 3, 14);
      await _pump(
        tester,
        BillingRowSubtitle(
          party: const Text('Acme Ltd'),
          date: due,
          dateLabelKey: 'due_on_date_label',
        ),
      );
      expect(find.text('Acme Ltd'), findsOneWidget);
      expect(find.text('Due ${_fmt(due)}'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Acme Ltd')).dy,
        tester.getCenter(find.text('Due ${_fmt(due)}')).dy,
      );
    });

    testWidgets('no date: the party alone, no dangling separator', (
      tester,
    ) async {
      await _pump(
        tester,
        const BillingRowSubtitle(
          party: Text('Acme Ltd'),
          date: null,
          dateLabelKey: 'due_on_date_label',
        ),
      );
      expect(find.text('Acme Ltd'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
      expect(find.textContaining('Due'), findsNothing);
    });

    testWidgets('no formatter yet: no date in some other format', (
      tester,
    ) async {
      await _pump(
        tester,
        BillingRowSubtitle(
          party: const Text('Acme Ltd'),
          date: Date(2030, 3, 14),
          dateLabelKey: 'due_on_date_label',
        ),
        withFormatter: false,
      );
      expect(find.textContaining('Due'), findsNothing);
      expect(find.textContaining('2030'), findsNothing);
    });

    testWidgets('late: overdue ink, and the screen reader hears how late', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final due = Date(2020, 1, 2);
      await _pump(
        tester,
        BillingRowSubtitle(
          party: const Text('Acme Ltd'),
          date: due,
          dateLabelKey: 'due_on_date_label',
          late: true,
          lateText: '12 days late',
        ),
      );
      expect(_colorOf(tester, 'Due ${_fmt(due)}'), InTheme.light.overdue);
      expect(
        find.bySemanticsLabel('Due ${_fmt(due)}, 12 days late'),
        findsOneWidget,
      );
      handle.dispose();
    });

    Future<void> pumpLine(
      WidgetTester tester, {
      required String name,
      required double width,
    }) => _pump(
      tester,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: width,
          child: BillingRowSubtitle(
            party: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            date: Date(2030, 11, 15),
            dateLabelKey: 'valid_until_date_label',
          ),
        ),
      ),
    );

    bool ellipsized(WidgetTester tester, Finder f) {
      final p = tester.renderObject<RenderParagraph>(f);
      return p.didExceedMaxLines ||
          p.size.width < p.getMaxIntrinsicWidth(double.infinity) - 0.5;
    }

    // The test font draws every glyph 1 em (12 px) wide, so the 24-character
    // date is 288 px: on a 400 px line it fills well over the 60% a ratio
    // split would have given it.
    testWidgets('a short name keeps a long date whole', (tester) async {
      final date = 'Valid until ${_fmt(Date(2030, 11, 15))}';
      await pumpLine(tester, name: 'Acme', width: 400);
      expect(ellipsized(tester, find.text(date)), isFalse);
      expect(ellipsized(tester, find.text('Acme')), isFalse);
    });

    testWidgets('a long name keeps 40% of the line before the date gives way', (
      tester,
    ) async {
      final date = 'Valid until ${_fmt(Date(2030, 11, 15))}';
      await pumpLine(
        tester,
        name: 'Bayer-Kautzer Holdings International',
        width: 400,
      );
      final name = find.text('Bayer-Kautzer Holdings International');
      // Less at most one glyph: an ellipsized paragraph is as wide as the
      // glyphs it kept.
      expect(tester.getSize(name).width, greaterThanOrEqualTo(400 * 0.4 - 12));
      expect(ellipsized(tester, name), isTrue);
      expect(ellipsized(tester, find.text(date)), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long party name gives way; the date is never cut', (
      tester,
    ) async {
      final due = Date(2030, 3, 14);
      await _pump(
        tester,
        BillingRowSubtitle(
          party: Text(
            'A very long client name ' * 8,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          date: due,
          dateLabelKey: 'due_on_date_label',
        ),
      );
      expect(tester.takeException(), isNull);
      final dateBox = tester.getRect(find.text('Due ${_fmt(due)}'));
      expect(dateBox.right, lessThanOrEqualTo(390));
    });
  });

  group('the narrow rows', () {
    testWidgets('a past-due invoice: its active due date, in the overdue ink', (
      tester,
    ) async {
      final due = today.addDays(-12);
      final partialDue = today.addDays(-3);
      await _pump(
        tester,
        InvoiceListTile(
          invoice: emptyInvoice().copyWith(
            id: 'inv1',
            number: '0012',
            statusId: InvoiceStatus.sent,
            balance: Decimal.fromInt(100),
            amount: Decimal.fromInt(100),
            dueDate: due,
            partialDueDate: partialDue,
            partial: Decimal.fromInt(10),
          ),
          columns: const [],
          wide: false,
          onTap: () {},
        ),
      );
      // The partial's date — the one `isPastDueOn` measures from.
      final text = 'Due ${_fmt(partialDue)}';
      expect(find.text(text), findsOneWidget);
      expect(_colorOf(tester, text), InTheme.light.overdue);
      expect(find.text('#0012'), findsOneWidget);
    });

    testWidgets('an invoice not yet due: the date in the muted ink', (
      tester,
    ) async {
      final due = today.addDays(20);
      await _pump(
        tester,
        InvoiceListTile(
          invoice: emptyInvoice().copyWith(
            id: 'inv1',
            number: '0012',
            statusId: InvoiceStatus.sent,
            balance: Decimal.fromInt(100),
            dueDate: due,
          ),
          columns: const [],
          wide: false,
          onTap: () {},
        ),
      );
      final text = 'Due ${_fmt(due)}';
      expect(_colorOf(tester, text), InTheme.light.ink2);
    });

    testWidgets('an invoice with no due date and no client: no second line', (
      tester,
    ) async {
      await _pump(
        tester,
        InvoiceListTile(
          invoice: emptyInvoice().copyWith(id: 'inv1', number: '0012'),
          columns: const [],
          wide: false,
          onTap: () {},
        ),
      );
      expect(find.textContaining('Due'), findsNothing);
    });

    testWidgets('an expired quote: valid until, in the overdue ink', (
      tester,
    ) async {
      final validUntil = today.addDays(-2);
      await _pump(
        tester,
        QuoteListTile(
          quote: emptyQuote().copyWith(
            id: 'q1',
            number: 'Q-7',
            statusId: QuoteStatus.sent,
            dueDate: validUntil,
          ),
          columns: const [],
          wide: false,
          onTap: () {},
        ),
      );
      final text = 'Valid until ${_fmt(validUntil)}';
      expect(find.text(text), findsOneWidget);
      expect(_colorOf(tester, text), InTheme.light.overdue);
    });

    testWidgets('a purchase order: its due date, never in the overdue ink', (
      tester,
    ) async {
      final due = today.addDays(-30);
      await _pump(
        tester,
        PurchaseOrderListTile(
          purchaseOrder: emptyPurchaseOrder().copyWith(
            id: 'po1',
            number: 'PO-1',
            dueDate: due,
          ),
          columns: const [],
          wide: false,
          onTap: () {},
        ),
      );
      final text = 'Due ${_fmt(due)}';
      expect(find.text(text), findsOneWidget);
      expect(_colorOf(tester, text), InTheme.light.ink2);
    });
  });
}
