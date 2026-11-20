// The narrow billing editor's Details tab and strip: the Items tab's line
// count, the partial (deposit) fields collapsed to an "Add deposit" link, and
// the invoice due date's payment-terms presets.

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/payment_term_api_model.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/payment_term.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
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
    bool compactList = false,
    Widget Function(Widget layout)? wrap,
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
    await fixture.services.listDensity.setCompact(compactList);
    final layout = ListDensityScope(
      controller: fixture.services.listDensity,
      child: wrap?.call(mounted.layout) ?? mounted.layout,
    );
    await tester.pumpWidget(wrapWithShell(fixture.services, layout));
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

    /// The due date's outlined box, and the icon buttons inside it.
    Finder dueBox() => find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == 'Due Date',
    );
    Finder inBox(IconData icon) => find.descendant(
      of: dueBox(),
      matching: find.widgetWithIcon(IconButton, icon),
    );
    final termsButton = find.widgetWithIcon(
      IconButton,
      Icons.event_repeat_outlined,
    );

    testWidgets('narrow: one icon in the field, the terms on the label line', (
      tester,
    ) async {
      final m = await mount(tester, BillingDoc.invoice, terms: terms);
      expect(
        find.descendant(of: dueBox(), matching: find.byType(IconButton)),
        findsOneWidget,
        reason: 'only the calendar inside the field',
      );
      expect(inBox(Icons.date_range), findsOneWidget);
      expect(termsButton, findsOneWidget);
      final box = tester.getRect(dueBox());
      final button = tester.getRect(termsButton);
      final label = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.maxLines == 1 &&
              w.text.toPlainText() == 'Due Date',
        ),
      );
      // At the end of the label's line, its icon centred on the label.
      expect(button.right, box.right);
      final icon = tester.getRect(
        find.descendant(
          of: termsButton,
          matching: find.byIcon(Icons.event_repeat_outlined),
        ),
      );
      expect(icon.center.dy, moreOrLessEquals(label.center.dy, epsilon: 3));
      expect(icon.bottom, lessThanOrEqualTo(box.top));
      // The touch square (44 px under `flutter test`'s Android).
      expect(button.size, const Size.square(InSizes.touchTarget));
      // No extra row: the due date's box stays level with the date's.
      final dateBox = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is InputDecorator && w.decoration.labelText == 'Invoice Date',
        ),
      );
      expect(box.top, dateBox.top);
      // The whole hint shows.
      expect(tester.getSize(dueBox()).width, greaterThan(0));
      await unmount(tester, m.fixture);
    }, timeout: timeout);

    testWidgets('wide: both icons in the field', (tester) async {
      final m = await mount(
        tester,
        BillingDoc.invoice,
        terms: terms,
        width: 1440,
      );
      expect(inBox(Icons.event_repeat_outlined), findsOneWidget);
      expect(inBox(Icons.date_range), findsOneWidget);
      await unmount(tester, m.fixture);
    }, timeout: timeout);

    testWidgets('narrow at Compact: the calendar is a menu of the picker '
        'and the terms', (tester) async {
      final m = await mount(
        tester,
        BillingDoc.invoice,
        terms: terms,
        compactList: true,
        seed: (vm) => (vm as InvoiceEditViewModel).setDate(Date(2026, 3, 1)),
      );
      expect(
        find.descendant(of: dueBox(), matching: find.byType(IconButton)),
        findsOneWidget,
      );
      expect(termsButton, findsNothing);
      await tester.tap(inBox(Icons.date_range));
      await settle(tester);
      expect(find.text('Select date'), findsWidgets);
      await tester.tap(find.text('Net 30'));
      await settle(tester);
      expect((m.vm.draft as Invoice).dueDate, Date(2026, 3, 31));
      await unmount(tester, m.fixture);
    }, timeout: timeout);

    // 2x text is pinned on the field alone (in_date_field_test): mounted
    // whole, the editor's Settings tab overflows at 2x in its scope banner,
    // which is not this field.
    for (final (name, rtl, dark, scale) in [
      ('RTL', true, false, 1.0),
      ('dark', false, true, 1.0),
      ('RTL dark', true, true, 1.0),
    ]) {
      testWidgets('narrow, $name: the terms at the label line\'s end', (
        tester,
      ) async {
        final m = await mount(
          tester,
          BillingDoc.invoice,
          terms: terms,
          wrap: (layout) => Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Theme(
                  data: buildInTheme(dark ? InTheme.dark : InTheme.light),
                  child: layout,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(of: dueBox(), matching: find.byType(IconButton)),
          findsOneWidget,
        );
        final box = tester.getRect(dueBox());
        final button = tester.getRect(termsButton);
        expect(rtl ? button.left : button.right, rtl ? box.left : box.right);
        expect(button.top, lessThan(box.top));
        await unmount(tester, m.fixture);
      }, timeout: timeout);
    }

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

  testWidgets('the client\'s notes sit under the picker on the Details tab '
      '(#201)', (tester) async {
    final m = await mount(
      tester,
      BillingDoc.invoice,
      seed: (vm) => vm.selectClient('c1', const []),
    );
    await tester.runAsync(
      () => m.fixture.services.clients.applyUpdateResponse(
        companyId: kHarnessCompanyId,
        serverResponse: const ClientApi(
          id: 'c1',
          name: 'Acme',
          privateNotes: '<p>Driving distance: 42 km</p>',
          publicNotes: 'Thanks!',
          updatedAt: 1710000000,
        ),
      ),
    );
    await settle(tester);

    final notes = find.byKey(const ValueKey('billing-party-notes'));
    expect(notes, findsOneWidget);
    expect(find.text('Driving distance: 42 km'), findsOneWidget);
    expect(find.text('Thanks!'), findsOneWidget);
    // Between the client and the number, in that order.
    final picker = fieldLabels(tester).indexOf('Client');
    expect(picker, isNonNegative);
    expect(
      tester.getTopLeft(notes).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byWidgetPredicate(
                (w) =>
                    w is InputDecorator &&
                    w.decoration.labelText == 'Invoice Number',
              ),
            )
            .dy,
      ),
    );
    await unmount(tester, m.fixture);
  }, timeout: timeout);
}
