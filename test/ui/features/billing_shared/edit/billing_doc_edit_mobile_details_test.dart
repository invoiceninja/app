// The narrow billing editor's Details tab and strip: the Items tab's line
// count, the partial (deposit) fields collapsed to an "Add deposit" link, and
// the invoice due date's payment-terms presets.

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/payment_term_api_model.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/payment_term.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/ui/features/billing_shared/edit/billing_doc_payment_terms_button.dart';
import 'package:admin/ui/features/billing_shared/view_models/billing_doc_edit_view_model.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

void main() {
  Future<({ShellFixture fixture, GenericBillingDocEditViewModel<Object?> vm})>
  mount(
    WidgetTester tester,
    BillingDoc doc, {
    double width = 390,
    List<PaymentTermApi> terms = const [],
    void Function(GenericBillingDocEditViewModel<Object?> vm)? seed,
  }) async {
    setWindow(tester, width);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: [const FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    if (terms.isNotEmpty) {
      await fixture.services.paymentTerms.applyBundle(
        companyId: kHarnessCompanyId,
        bundle: terms,
      );
    }
    final mounted = buildLayout(
      doc,
      fixture.services,
      showPdfTab: width >= 600,
    );
    addTearDown(mounted.vm.dispose);
    seed?.call(mounted.vm);
    await tester.pumpWidget(wrapWithShell(fixture.services, mounted.layout));
    await settle(tester);
    return (fixture: fixture, vm: mounted.vm);
  }

  const timeout = Timeout(Duration(seconds: 60));

  group('the Items tab count', () {
    testWidgets('counts the draft\'s own lines, live, and never a blank one', (
      tester,
    ) async {
      final m = await mount(tester, BillingDoc.invoice);
      expect(tabBarCounts(tester), {'Items': 0});
      expect(tabBarLabels(tester).first, contains('Items'));

      m.vm.replaceLineItems([
        emptyLineItem().copyWith(productKey: 'A', quantity: Decimal.one),
        emptyLineItem().copyWith(notes: 'B', quantity: Decimal.one),
        emptyLineItem(),
      ]);
      await settle(tester);
      expect(tabBarCounts(tester), {'Items': 2});
      await unmount(tester, m.fixture);
    }, timeout: timeout);
  });

  group('the deposit fields', () {
    for (final doc in [
      BillingDoc.invoice,
      BillingDoc.quote,
      BillingDoc.credit,
    ]) {
      testWidgets('${doc.name}: start collapsed to an Add deposit link', (
        tester,
      ) async {
        final m = await mount(tester, doc);
        expect(find.text('Add deposit'), findsOneWidget);
        expect(fieldLabels(tester), isNot(contains('Partial/Deposit')));
        expect(fieldLabels(tester), isNot(contains('Partial Due Date')));

        await tester.tap(find.text('Add deposit'));
        await settle(tester);
        expect(find.text('Add deposit'), findsNothing);
        expect(fieldLabels(tester), contains('Partial/Deposit'));
        // The caret lands in the amount the tap asked for.
        final focused = FocusManager.instance.primaryFocus;
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is TextField && w.focusNode == focused,
            ),
            matching: find.byType(EditableText),
          ),
          findsOneWidget,
        );
        await unmount(tester, m.fixture);
      }, timeout: timeout);
    }

    testWidgets('a draft with a partial opens on the fields', (tester) async {
      final m = await mount(
        tester,
        BillingDoc.invoice,
        seed: (vm) => (vm as InvoiceEditViewModel).setPartial('25'),
      );
      expect(find.text('Add deposit'), findsNothing);
      expect(
        fieldLabels(tester),
        containsAll(['Partial/Deposit', 'Partial Due Date']),
      );
      await unmount(tester, m.fixture);
    }, timeout: timeout);

    testWidgets('the wide layout keeps both fields, no link', (tester) async {
      final m = await mount(tester, BillingDoc.invoice, width: 1440);
      expect(find.text('Add deposit'), findsNothing);
      expect(fieldLabels(tester), contains('Partial/Deposit'));
      await unmount(tester, m.fixture);
    }, timeout: timeout);
  });

  group('payment-term presets', () {
    const terms = [
      PaymentTermApi(id: 't30', name: 'Net 30', numDays: 30, updatedAt: 1),
      PaymentTermApi(id: 't0', name: 'Now', numDays: 0, updatedAt: 1),
      // Same days under another name: listed once.
      PaymentTermApi(id: 't30b', name: 'Monthly', numDays: 30, updatedAt: 1),
    ];

    testWidgets('invoice: disabled with no date, then sets date + days', (
      tester,
    ) async {
      final m = await mount(tester, BillingDoc.invoice, terms: terms);
      (m.vm as InvoiceEditViewModel).setDate(null);
      await settle(tester);
      // A small icon inside the due date field, named by its tooltip.
      final button = find.widgetWithIcon(
        IconButton,
        Icons.event_repeat_outlined,
      );
      expect(button, findsOneWidget);
      expect(find.byTooltip('Payment Terms'), findsOneWidget);
      expect(tester.widget<IconButton>(button).onPressed, isNull);

      (m.vm as InvoiceEditViewModel).setDate(Date(2026, 3, 1));
      await settle(tester);
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await settle(tester);
      expect(find.text('Due on Receipt'), findsOneWidget);
      expect(find.text('Net 30'), findsOneWidget);

      await tester.tap(find.text('Net 30'));
      await settle(tester);
      expect((m.vm.draft as Invoice).dueDate, Date(2026, 3, 31));
      await unmount(tester, m.fixture);
    }, timeout: timeout);

    testWidgets('invoice with no terms: no button', (tester) async {
      final m = await mount(tester, BillingDoc.invoice);
      expect(find.byTooltip('Payment Terms'), findsNothing);
      await unmount(tester, m.fixture);
    }, timeout: timeout);

    for (final doc in [BillingDoc.quote, BillingDoc.credit]) {
      testWidgets('${doc.name}: never offered', (tester) async {
        final m = await mount(tester, doc, terms: terms);
        expect(find.byTooltip('Payment Terms'), findsNothing);
        await unmount(tester, m.fixture);
      }, timeout: timeout);
    }

    test('presets: each day count once, shortest first', () {
      PaymentTerm t(int days, {bool deleted = false}) => PaymentTerm(
        id: '$days',
        name: '',
        numDays: days,
        updatedAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
        archivedAt: null,
        isDeleted: deleted,
      );
      expect(
        paymentTermPresetDays([t(30), t(7), t(30), t(0), t(14, deleted: true)]),
        [0, 7, 30],
      );
    });
  });
}
