import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/shortcut_tooltip.dart';

// docs/tooltip-delays.md
void main() {
  group('tooltipBesideTarget', () {
    const overlay = Size(1000, 800);
    const tooltip = Size(120, 30);
    const targetSize = Size(200, 40);

    Offset place(
      TextDirection direction, {
      required Offset target,
      Size overlaySize = overlay,
    }) => tooltipBesideTarget(direction)(
      TooltipPositionContext(
        target: target,
        targetSize: targetSize,
        tooltipSize: tooltip,
        verticalOffset: 24,
        overlaySize: overlaySize,
      ),
    );

    test('LTR: to the right of the row, vertically centred', () {
      final p = place(TextDirection.ltr, target: const Offset(120, 200));
      expect(p, const Offset(120 + 100 + 8, 200 - 15));
    });

    test('RTL: to the left of the row', () {
      final p = place(TextDirection.rtl, target: const Offset(880, 200));
      expect(p.dx, 880 - 100 - 8 - 120);
    });

    test('LTR with no room on the right falls back to the left', () {
      final p = place(TextDirection.ltr, target: const Offset(850, 200));
      expect(p.dx, 850 - 100 - 8 - 120);
    });

    test('no room on either side falls back to above / below', () {
      final p = place(
        TextDirection.ltr,
        target: const Offset(150, 200),
        overlaySize: const Size(300, 800),
      );
      // Material's positionDependentBox: below the target by verticalOffset.
      expect(p.dy, 200 + 24);
    });

    test('clamped to the overlay at the top edge', () {
      final p = place(TextDirection.ltr, target: const Offset(120, 5));
      expect(p.dy, 0);
    });
  });

  testWidgets('a shortcut tooltip never takes the pointer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShortcutTooltip(label: 'New', keys: ['N'], child: Text('x')),
      ),
    );
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).ignorePointer, true);
  });

  test('the theme waits the label delay; Material would wait none', () {
    final theme = buildInTheme(InTheme.light);
    expect(theme.tooltipTheme.waitDuration, InTooltip.labelDelay);
    expect(InTooltip.hintDelay, greaterThan(InTooltip.labelDelay));
  });
}
