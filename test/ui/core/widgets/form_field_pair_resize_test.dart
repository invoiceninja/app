// A pair of fields crossing its pairing width must not remount the field being
// typed in (`lib/ui/core/widgets/form_field_pair.dart`). A foldable opening
// mid-edit widens the form from ~400 to ~719, across `Breakpoints.wide`; when
// the pair switched from a `Column` to a `Row` of `Expanded`s, the focused
// field was rebuilt from scratch and lost its focus, caret and keyboard.
// docs/foldables.md.

import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the focused field survives the pair flipping both ways', (
    tester,
  ) async {
    final left = TextEditingController();
    final right = TextEditingController();
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    final width = ValueNotifier<double>(400);
    addTearDown(width.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, w, _) => Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: w,
                child: FormFieldPair(
                  left: TextField(key: const ValueKey('l'), controller: left),
                  right: TextField(key: const ValueKey('r'), controller: right),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rightField = find.byKey(const ValueKey('r'));
    final stackedTop = tester.getTopLeft(rightField).dy;
    await tester.tap(rightField);
    await tester.enterText(rightField, 'Smith');
    right.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    final state = tester.state(rightField);

    for (final w in [719.0, 400.0, 719.0]) {
      width.value = w;
      await tester.pump();
      expect(tester.state(rightField), same(state), reason: 'remounted at $w');
      final editable = tester.widget<EditableText>(
        find.descendant(of: rightField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue, reason: 'unfocused at $w');
      expect(right.text, 'Smith');
      expect(right.selection, const TextSelection.collapsed(offset: 2));
      expect(tester.testTextInput.hasAnyClients, isTrue);
    }

    // And it is still a real pair when wide: side by side, each half width.
    expect(tester.getTopLeft(rightField).dy, lessThan(stackedTop));
    expect(
      tester.getSize(find.byKey(const ValueKey('l'))).width,
      lessThan(719 / 2),
    );
  });
}
