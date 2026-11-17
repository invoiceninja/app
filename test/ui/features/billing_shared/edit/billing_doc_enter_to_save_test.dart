import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/core/widgets/form_save_scope.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

/// Enter in a single-line field saves the surrounding form (§ Forms — Enter to
/// save). The billing documents' own header fields — the number, PO number,
/// discount, partial and exchange rate — never read the `FormSaveScope` the
/// edit scaffold puts around them, so Enter did nothing there.
void main() {
  Future<({ShellFixture fixture, int Function() saves})> mount(
    WidgetTester tester,
    double width,
  ) async {
    setWindow(tester, width);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    final mounted = buildLayout(
      BillingDoc.invoice,
      fixture.services,
      showPdfTab: width >= 600,
    );
    addTearDown(mounted.vm.dispose);
    var saves = 0;
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        FormSaveScope(onSubmit: () => saves++, child: mounted.layout),
      ),
    );
    await settle(tester);
    return (fixture: fixture, saves: () => saves);
  }

  Future<void> enterIn(WidgetTester tester, String label) async {
    final field = find.widgetWithText(TextField, label).first;
    // To the middle of the viewport, not its top edge: `ensureVisible` parks
    // a field flush with the top, and a neighbour sharing that row (Discount
    // beside Partial/Deposit, now the same height) is then left there without
    // a scroll of its own, where a tap at its centre misses.
    await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  const headerFields = [
    'Invoice Number',
    'PO Number',
    'Partial/Deposit',
    'Discount',
  ];

  for (final width in [390.0, 1440.0]) {
    testWidgets('Enter in a header field saves the document ($width px)', (
      tester,
    ) async {
      final (:fixture, :saves) = await mount(tester, width);
      // Counted per field: a total alone passes when one field saves twice
      // and another not at all.
      for (final (i, label) in headerFields.indexed) {
        // On a phone the partial starts collapsed behind "Add deposit".
        if (label == 'Partial/Deposit' &&
            find.text('Add deposit').evaluate().isNotEmpty) {
          await tester.tap(find.text('Add deposit'));
          await settle(tester);
        }
        await enterIn(tester, label);
        expect(saves(), i + 1, reason: label);
      }
      await unmount(tester, fixture);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  testWidgets('Enter in Exchange Rate saves the document', (tester) async {
    final (:fixture, :saves) = await mount(tester, 390);
    final tabs = tabBarLabels(tester).first;
    await showTab(tester, tabs.indexOf('Settings'));
    await enterIn(tester, 'Exchange Rate');
    expect(saves(), 1);
    await unmount(tester, fixture);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
