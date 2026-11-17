// The wide billing editor's details: three cards across the top — the party,
// the dates, the number — equal in width, sharing a top, each at its own
// height (as 5.1.30 drew them), and every field box at one height so the
// n-th field of each card shares a top with its neighbours'. The discount
// used to sit 8 px above the partial beside it, and its % / $ switch painted
// 8 px short of the box (Hillel, 2026-11-17: "keep 3 panels at the top,
// partial and deposit aren't aligned", "there's a gap under the $ symbol",
// "make each of the 3 panels shorter as before").

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
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
    InTheme? tokens,
    bool compactList = false,
    double textScale = 1,
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
    await fixture.services.listDensity.setCompact(compactList);
    // The app's own theme (its segmented-button and field themes), under the
    // list density and text scale the field heights depend on.
    final Widget layout = tokens == null
        ? mounted.layout
        : ListDensityScope(
            controller: fixture.services.listDensity,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Theme(data: buildInTheme(tokens), child: mounted.layout),
              ),
            ),
          );
    await tester.pumpWidget(wrapWithShell(fixture.services, layout));
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
    testWidgets('${doc.name}: three cards across the top, each its own '
        'height', (tester) async {
      final fixture = await mount(tester, doc);
      final rects = [for (final k in _cards) tester.getRect(find.byKey(k))];
      for (final r in rects.skip(1)) {
        expect(r.top, rects.first.top, reason: 'the cards share a top');
        expect(r.width, moreOrLessEquals(rects.first.width, epsilon: 0.01));
      }
      // Natural heights: each field card ends the same distance under its
      // own last field — nothing stretches it to a neighbour's height.
      double tail(int i) {
        final last = labelsIn(tester, _cards[i]).last;
        return rects[i].bottom - box(tester, last).bottom;
      }

      expect(tail(1), tail(2));
      expect(tail(1), lessThan(64));
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
    await unmount(tester, fixture);
  }, timeout: timeout);

  // The % / $ switch is the discount box's exact height, top and bottom.
  // Measured on what is PAINTED — the segments — not the SegmentedButton's
  // own box: under `IntrinsicHeight` + stretch the button's box was 44 px
  // while its segments painted 32 (macOS, compact density), the gap under
  // the `$`. The field itself is 36–54 px across these cases.
  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    for (final (name, tokens) in [
      ('light', InTheme.light),
      ('dark', InTheme.dark),
    ]) {
      for (final compactList in [false, true]) {
        for (final textScale in [1.0, 1.5]) {
          testWidgets('${platform.name} $name, '
              '${compactList ? 'Compact' : 'Comfortable'} list density, '
              'text x$textScale: the switch fills the discount box', (
            tester,
          ) async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            final fixture = await mount(
              tester,
              BillingDoc.invoice,
              tokens: tokens,
              compactList: compactList,
              textScale: textScale,
            );
            final discount = box(tester, 'Discount');
            expect(
              discount.top,
              box(tester, 'Partial/Deposit').top,
              reason: 'level with the partial',
            );
            final toggle = find.byType(SegmentedButton<bool>);
            final segments = find.descendant(
              of: toggle,
              matching: find.byType(TextButton),
            );
            expect(segments, findsNWidgets(2));
            for (final r in [
              tester.getRect(toggle),
              for (final e in segments.evaluate())
                tester.getRect(find.byWidget(e.widget)),
            ]) {
              expect(r.top, discount.top, reason: 'top');
              expect(r.bottom, discount.bottom, reason: 'bottom');
            }
            expect(tester.getRect(toggle).left, greaterThan(discount.right));
            await unmount(tester, fixture);
            debugDefaultTargetPlatformOverride = null;
          }, timeout: timeout);
        }
      }
    }
  }

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
    // The dates card grew by the new field; the number card did not — it
    // still ends just under the discount, as far below it as the dates card
    // ends below its own last field.
    final dates = tester.getRect(find.byKey(_cards[1]));
    final number = tester.getRect(find.byKey(_cards[2]));
    expect(dates.top, number.top);
    expect(dates.height, greaterThan(number.height));
    expect(
      number.bottom - box(tester, 'Discount').bottom,
      dates.bottom - box(tester, 'Partial Due Date').bottom,
    );
    await unmount(tester, fixture);
  }, timeout: timeout);
}
