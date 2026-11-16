import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';

/// `inFieldBorder`: a field answers the mouse with its border, never its fill.
void main() {
  const t = InTheme.light;

  BorderSide side(Set<WidgetState> states) =>
      (WidgetStateProperty.resolveAs<InputBorder>(inFieldBorder(t), states)
              as OutlineInputBorder)
          .borderSide;

  test('rest, hover and focus are one ramp on the border', () {
    expect(side({}).color, t.border);
    expect(side({WidgetState.hovered}).color, t.borderStrong);
    expect(side({WidgetState.focused}).color, t.accent);
    // Only focus changes the width, or text shimmers as the mouse passes.
    expect(side({}).width, 1);
    expect(side({WidgetState.hovered}).width, 1);
    expect(side({WidgetState.focused}).width, 1.5);
  });

  test('an error stays an error under the mouse; disabled does not react', () {
    expect(side({WidgetState.error, WidgetState.hovered}).color, t.overdue);
    expect(side({WidgetState.disabled, WidgetState.hovered}).color, t.border);
  });

  testWidgets('hovering a field moves its border and leaves its fill', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(t),
        home: const Scaffold(
          body: Center(child: SizedBox(width: 300, child: TextField())),
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(TextField)));
    expect(theme.inputDecorationTheme.hoverColor, Colors.transparent);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(TextField)));
    await tester.pumpAndSettle();
    expect(
      find.byType(TextField),
      paints
        ..rrect(color: t.bg)
        ..rrect(color: t.borderStrong),
    );
  });
}
