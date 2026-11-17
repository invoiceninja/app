// The wide billing editor's details: three cards across the top — the party,
// the dates, the number — equal in width and height, and every field box at
// one height so the n-th field of each card shares a top with its
// neighbours'. The discount used to sit 8 px above the partial beside it
// (Hillel, 2026-11-17: "keep 3 panels at the top, partial and deposit aren't
// aligned").

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/features/billing_shared/view_models/billing_doc_edit_view_model.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

const _cards = [
  ValueKey('billing-details-party'),
  ValueKey('billing-details-dates'),
  ValueKey('billing-details-number'),
];

void main() {
  Future<ShellFixture> mount(
    WidgetTester tester,
    BillingDoc doc, {
    double width = 1440,
    void Function(GenericBillingDocEditViewModel<Object?> vm)? seed,
  }) async {
    setWindow(tester, width);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: [const FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    final mounted = buildLayout(doc, fixture.services, showPdfTab: true);
    addTearDown(mounted.vm.dispose);
    seed?.call(mounted.vm);
    await tester.pumpWidget(wrapWithShell(fixture.services, mounted.layout));
    await settle(tester);
    return fixture;
  }

  /// The outlined box of the field labelled [label] — its `InputDecorator`,
  /// which excludes the label drawn above it.
  Rect box(WidgetTester tester, String label) => tester.getRect(
    find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == label,
    ),
  );

  /// Field labels inside the card keyed [key], in paint order.
  List<String> labelsIn(WidgetTester tester, Key key) =>
      fieldLabels(tester, within: find.byKey(key));

  const timeout = Timeout(Duration(seconds: 60));

  for (final doc in BillingDoc.values) {
    testWidgets('${doc.name}: three cards across the top, one height', (
      tester,
    ) async {
      final fixture = await mount(tester, doc);
      final rects = [for (final k in _cards) tester.getRect(find.byKey(k))];
      for (final r in rects.skip(1)) {
        expect(r.top, rects.first.top, reason: 'the cards share a top');
        expect(r.height, rects.first.height, reason: 'and a height');
        expect(r.width, moreOrLessEquals(rects.first.width, epsilon: 0.01));
      }
      // Start to end, never overlapping.
      expect(rects[0].right, lessThan(rects[1].left));
      expect(rects[1].right, lessThan(rects[2].left));
      await unmount(tester, fixture);
    }, timeout: timeout);
  }

  testWidgets('each card holds its own fields (invoice)', (tester) async {
    final fixture = await mount(tester, BillingDoc.invoice);
    expect(labelsIn(tester, _cards[0]), ['Client']);
    expect(labelsIn(tester, _cards[1]), [
      'Invoice Date',
      'Due Date',
      'Partial/Deposit',
    ]);
    expect(labelsIn(tester, _cards[2]), [
      'Invoice Number',
      'PO Number',
      'Discount',
    ]);
    await unmount(tester, fixture);
  }, timeout: timeout);

  testWidgets('the purchase order: no partial, its number is the PO number', (
    tester,
  ) async {
    final fixture = await mount(tester, BillingDoc.purchaseOrder);
    expect(labelsIn(tester, _cards[0]), ['Vendor']);
    expect(labelsIn(tester, _cards[1]), ['Purchase Order Date', 'Due Date']);
    expect(labelsIn(tester, _cards[2]), ['PO Number', 'Discount']);
    await unmount(tester, fixture);
  }, timeout: timeout);

  testWidgets('the recurring invoice: the schedule in the dates card, '
      'auto-bill under the discount', (tester) async {
    final fixture = await mount(tester, BillingDoc.recurringInvoice);
    expect(labelsIn(tester, _cards[1]), [
      'Frequency',
      'Next Send Date',
      'Remaining Cycles',
      'Due Date',
    ]);
    expect(labelsIn(tester, _cards[2]), [
      'Invoice Number',
      'PO Number',
      'Discount',
      'Auto Bill',
    ]);
    await unmount(tester, fixture);
  }, timeout: timeout);

  testWidgets('every field box is 44 px, and row n of each card shares a top '
      '— the discount level with the partial', (tester) async {
    final fixture = await mount(tester, BillingDoc.invoice);
    final rows = [
      ['Client', 'Invoice Date', 'Invoice Number'],
      ['Due Date', 'PO Number'],
      ['Partial/Deposit', 'Discount'],
    ];
    for (final row in rows) {
      final first = box(tester, row.first);
      for (final label in row) {
        final r = box(tester, label);
        expect(r.height, InSizes.touchTarget, reason: '$label box height');
        expect(r.top, first.top, reason: '$label level with ${row.first}');
      }
    }
    // The % / amount switch sits beside the discount box, at its height.
    final toggle = tester.getRect(find.byType(SegmentedButton<bool>));
    final discount = box(tester, 'Discount');
    expect(toggle.top, discount.top);
    expect(toggle.height, discount.height);
    expect(toggle.left, greaterThan(discount.right));
    await unmount(tester, fixture);
  }, timeout: timeout);

  testWidgets('a partial adds its due date under it, in the dates card', (
    tester,
  ) async {
    final fixture = await mount(
      tester,
      BillingDoc.invoice,
      seed: (vm) => (vm as InvoiceEditViewModel).setPartial('25'),
    );
    expect(labelsIn(tester, _cards[1]), [
      'Invoice Date',
      'Due Date',
      'Partial/Deposit',
      'Partial Due Date',
    ]);
    // The cards still end on one line.
    final heights = {
      for (final k in _cards) tester.getRect(find.byKey(k)).height,
    };
    expect(heights, hasLength(1));
    await unmount(tester, fixture);
  }, timeout: timeout);
}
