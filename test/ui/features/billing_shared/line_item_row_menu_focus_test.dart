// The line-item row's ⋮ (clone, insert, move, remove). It sat at opacity 0
// until hovered and inside `ExcludeFocus`, so a keyboard user had no way to
// reach a row's actions at all and a touch user saw nothing to tap. Now it
// is a Tab stop on every platform and shows while it holds focus.

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_column_config.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart';

import '../shell/_shell_test_helpers.dart';

void main() {
  Future<Finder> pumpRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        LineItemTableDesktop(
          companyId: 'co1',
          items: [
            emptyLineItem().copyWith(
              productKey: 'A',
              notes: 'Alpha',
              cost: Decimal.fromInt(10),
              quantity: Decimal.one,
            ),
          ],
          onChanged: (_) {},
          newItemFactory: emptyLineItem,
          config: const LineItemColumnConfig(),
          controller: LineItemTableDesktopController(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return find.byIcon(Icons.more_vert).first;
  }

  double opacityOf(WidgetTester tester, Finder menu) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: menu, matching: find.byType(AnimatedOpacity)).first,
      )
      .opacity;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('with a pointer the row ⋮ is a Tab stop and shows while '
      'focused', (tester) async {
    final menu = await pumpRow(tester);
    double opacity() => opacityOf(tester, menu);

    expect(
      find.ancestor(of: menu, matching: find.byType(ExcludeFocus)),
      findsNothing,
      reason: 'the row actions need a keyboard path',
    );
    expect(opacity(), 0, reason: 'hover-revealed at rest with a pointer');

    Focus.of(tester.element(menu)).requestFocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), 1, reason: 'a focused ⋮ is never invisible');
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on touch the row ⋮ shows at rest — there is no hover', (
    tester,
  ) async {
    final menu = await pumpRow(tester);
    expect(opacityOf(tester, menu), 1);
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
