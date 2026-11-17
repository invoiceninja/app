// The discount's % / $ switch fits its row at every width and text scale.
// At 2x text (390 / 1024 / 1280 px) and 1.5x (1024 px) the switch beside the
// field overflowed the card by 37-107 px (5.1.31 review): it now stacks under
// the field, full width, when the row has no room for both. And it is the
// height of the field's input box, never the box plus a 422 error line. The
// sweep also caught the recurring invoice's Frequency / Auto Bill dropdowns
// overflowing their cards at x1.5 (now `isExpanded`).

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/features/billing_shared/edit/field_with_side_control.dart';
import 'package:admin/ui/features/billing_shared/view_models/billing_doc_edit_view_model.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

void main() {
  Future<({ShellFixture fixture, GenericBillingDocEditViewModel<Object?> vm})>
  mount(
    WidgetTester tester,
    BillingDoc doc, {
    required double width,
    double textScale = 1,
    void Function(GenericBillingDocEditViewModel<Object?> vm)? seed,
  }) async {
    setWindow(tester, width);
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: [const FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(fixture.dispose);
    final mounted = buildLayout(
      doc,
      fixture.services,
      showPdfTab: width >= 600,
    );
    addTearDown(mounted.vm.dispose);
    seed?.call(mounted.vm);
    final layout = ListDensityScope(
      controller: fixture.services.listDensity,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Theme(
            data: buildInTheme(InTheme.light),
            child: mounted.layout,
          ),
        ),
      ),
    );
    await tester.pumpWidget(wrapWithShell(fixture.services, layout));
    await settle(tester);
    return (fixture: fixture, vm: mounted.vm);
  }

  const timeout = Timeout(Duration(seconds: 120));
  final toggle = find.byType(SegmentedButton<bool>);
  final discount = find.descendant(
    of: find.byType(FieldWithSideControl),
    matching: find.byType(InputDecorator),
  );

  /// The discount's input box: the decorator's container, which excludes
  /// the helper / error line under it.
  Rect inputBox(WidgetTester tester) {
    // `containerOf` looks up from below the decorator's render object: the
    // text input, which sits in one of its slots.
    final inside = find
        .descendant(of: discount, matching: find.byType(EditableText))
        .evaluate()
        .single;
    final box = InputDecorator.containerOf(inside)!;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  for (final doc in BillingDoc.values) {
    for (final width in [390.0, 820.0, 1024.0, 1280.0, 1440.0]) {
      testWidgets('${doc.name} at $width px: the switch fits at text x1, '
          'x1.5 and x2', (tester) async {
        for (final textScale in [1.0, 1.5, 2.0]) {
          final m = await mount(
            tester,
            doc,
            width: width,
            textScale: textScale,
          );
          final at = 'x$textScale';
          expect(
            tester.takeException(),
            isNull,
            reason: '$at renders without an overflow',
          );
          expect(toggle, findsOneWidget, reason: at);
          final box = inputBox(tester);
          final t = tester.getRect(toggle);
          expect(t.height, box.height, reason: '$at: the box\'s height');
          if (t.top == box.top) {
            // Beside, inside the field's row.
            expect(t.left, greaterThan(box.right), reason: at);
            expect(t.right, lessThanOrEqualTo(width), reason: at);
          } else {
            // Stacked: under the field, its full width.
            expect(t.top, greaterThan(box.bottom), reason: at);
            expect(t.left, box.left, reason: at);
            expect(t.width, box.width, reason: at);
          }
          await unmount(tester, m.fixture);
        }
      }, timeout: timeout);
    }
  }

  testWidgets('beside the field, the switch at large text keeps it '
      '(1440 px, x1.5)', (tester) async {
    final m = await mount(
      tester,
      BillingDoc.invoice,
      width: 1440,
      textScale: 1.5,
    );
    final box = inputBox(tester);
    expect(tester.getRect(toggle).top, box.top);
    expect(tester.getRect(toggle).left, greaterThan(box.right));
    await unmount(tester, m.fixture);
  }, timeout: timeout);

  testWidgets('too narrow at x2 (1024 px): the switch drops under the field, '
      'full width, at the box\'s height', (tester) async {
    final m = await mount(
      tester,
      BillingDoc.invoice,
      width: 1024,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final box = inputBox(tester);
    final t = tester.getRect(toggle);
    expect(t.top, greaterThan(box.bottom));
    expect(t.width, box.width);
    expect(t.height, box.height);
    await unmount(tester, m.fixture);
  }, timeout: timeout);

  for (final width in [390.0, 1440.0]) {
    testWidgets('a 422 on the discount ($width px): the switch is the input '
        'box\'s height, not the box plus the error line', (tester) async {
      final m = await mount(
        tester,
        BillingDoc.invoice,
        width: width,
        seed: (vm) => vm.applyFailedSync(
          rowId: 1,
          errors: {
            'discount': ['The discount must be a number.'],
          },
        ),
      );
      expect(find.text('The discount must be a number.'), findsOneWidget);
      final box = inputBox(tester);
      final field = tester.getRect(discount);
      expect(
        field.height,
        greaterThan(box.height),
        reason: 'the error line sits under the box',
      );
      final t = tester.getRect(toggle);
      expect(t.top, box.top);
      expect(t.height, box.height);
      for (final e
          in find
              .descendant(of: toggle, matching: find.byType(TextButton))
              .evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.top, box.top, reason: 'segment top');
        expect(r.bottom, box.bottom, reason: 'segment bottom');
      }
      await unmount(tester, m.fixture);
    }, timeout: timeout);
  }
}
