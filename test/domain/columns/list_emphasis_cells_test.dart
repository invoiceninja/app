import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/dao/invoice_dao.dart' show InvoiceFieldIds;
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/columns/client_columns.dart';
import 'package:admin/domain/columns/column_cells.dart';
import 'package:admin/domain/columns/invoice_columns.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart'
    show emptyClient;
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart'
    show emptyInvoice;

import '../../_localization_helper.dart';

/// The list cells that carry emphasis of their own: the Clients balance (what
/// is owed, at weight 600), the Clients last login (a dash, never "Never"),
/// and the invoice due date (the overdue ink, with how late in a tooltip).
Future<void> _pump(WidgetTester tester, WidgetBuilder build) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(body: Builder(builder: build)),
      ),
    );

TextStyle _style(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text)).style!;

void main() {
  setUpAll(initializeDateFormatting);

  group('Clients balance', () {
    final cell = clientColumnsById[ClientFieldIds.balance]!.cellBuilder;

    testWidgets('a balance owed is weight 600 in ink', (tester) async {
      final c = emptyClient().copyWith(balance: Decimal.parse('12.5'));
      await _pump(tester, (ctx) => cell(c, ctx));
      expect(find.byType(MoneyCellText), findsOneWidget);
      expect(_style(tester).fontWeight, FontWeight.w600);
      expect(_style(tester).color, InTheme.light.ink);
    });

    testWidgets('zero keeps the dimmed dash', (tester) async {
      await _pump(tester, (ctx) => cell(emptyClient(), ctx));
      expect(find.text('—'), findsOneWidget);
      expect(_style(tester).fontWeight, isNot(FontWeight.w600));
      expect(_style(tester).color, InTheme.light.ink3);
    });

    testWidgets('a credit (negative) stays plain', (tester) async {
      final c = emptyClient().copyWith(balance: Decimal.parse('-3'));
      await _pump(tester, (ctx) => cell(c, ctx));
      expect(_style(tester).fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('money is the sans face with tabular figures', (tester) async {
      final c = emptyClient().copyWith(balance: Decimal.parse('12.5'));
      await _pump(tester, (ctx) => cell(c, ctx));
      expect(_style(tester).fontFamily, kSansFontFamily);
      expect(
        _style(tester).fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  testWidgets('Clients last login: never signed in is the em dash', (
    tester,
  ) async {
    final cell = clientColumnsById[ClientFieldIds.lastLoginAt]!.cellBuilder;
    await _pump(tester, (ctx) => cell(emptyClient(), ctx));
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('Never'), findsNothing);
  });

  group('invoice due date', () {
    final cell = invoiceColumnsById[InvoiceFieldIds.dueDate]!.cellBuilder;
    final today = Date.today();

    testWidgets('a sent invoice past due is in the overdue ink, with how late '
        'in a tooltip', (tester) async {
      final i = emptyInvoice().copyWith(
        statusId: InvoiceStatus.sent,
        balance: Decimal.parse('10'),
        dueDate: today.addDays(-12),
      );
      await _pump(tester, (ctx) => cell(i, ctx));
      expect(_style(tester).color, InTheme.light.overdue);
      expect(find.byTooltip('12 days late'), findsOneWidget);
      // The cell shows the date only.
      expect(find.textContaining('late'), findsNothing);
    });

    testWidgets('one day reads singular', (tester) async {
      final i = emptyInvoice().copyWith(
        statusId: InvoiceStatus.sent,
        balance: Decimal.parse('10'),
        dueDate: today.addDays(-1),
      );
      await _pump(tester, (ctx) => cell(i, ctx));
      expect(find.byTooltip('1 day late'), findsOneWidget);
    });

    testWidgets('a partial due date that passed makes the row late, counted '
        'from it — the Overdue tab predicate', (tester) async {
      final i = emptyInvoice().copyWith(
        statusId: InvoiceStatus.partial,
        balance: Decimal.parse('10'),
        partialDueDate: today.addDays(-3),
        dueDate: today.addDays(20),
      );
      await _pump(tester, (ctx) => cell(i, ctx));
      expect(_style(tester).color, InTheme.light.overdue);
      expect(find.byTooltip('3 days late'), findsOneWidget);
    });

    for (final (name, status, balance) in [
      ('paid', InvoiceStatus.paid, '0'),
      ('draft', InvoiceStatus.draft, '10'),
    ]) {
      testWidgets('a $name invoice past its date is not late', (tester) async {
        final i = emptyInvoice().copyWith(
          statusId: status,
          balance: Decimal.parse(balance),
          dueDate: today.addDays(-12),
        );
        await _pump(tester, (ctx) => cell(i, ctx));
        expect(_style(tester).color, InTheme.light.ink);
        expect(find.byType(Tooltip), findsNothing);
      });
    }

    testWidgets('a due date ahead is plain', (tester) async {
      final i = emptyInvoice().copyWith(
        statusId: InvoiceStatus.sent,
        balance: Decimal.parse('10'),
        dueDate: today.addDays(5),
      );
      await _pump(tester, (ctx) => cell(i, ctx));
      expect(_style(tester).color, InTheme.light.ink);
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
