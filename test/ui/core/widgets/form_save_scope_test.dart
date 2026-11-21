import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/core/widgets/form_save_scope.dart';

void main() {
  group('FormSaveScope', () {
    testWidgets('single-line TextField onSubmitted invokes onSubmit', (
      tester,
    ) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormSaveScope(
              onSubmit: () => count++,
              child: Builder(
                builder: (context) {
                  final scope = FormSaveScope.maybeOf(context)!;
                  return TextField(onSubmitted: (_) => scope.trySubmit());
                },
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(count, 1);
    });

    testWidgets('disabled scope does not fire onSubmit', (tester) async {
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormSaveScope(
              enabled: false,
              onSubmit: () => count++,
              child: Builder(
                builder: (context) {
                  final scope = FormSaveScope.maybeOf(context)!;
                  return TextField(onSubmitted: (_) => scope.trySubmit());
                },
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(count, 0);
    });

    testWidgets('maybeOf returns null without an ancestor scope', (
      tester,
    ) async {
      FormSaveScope? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = FormSaveScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(captured, isNull);
    });

    testWidgets('a held Enter saves once, not once per repeat', (tester) async {
      var count = 0;
      late FormSaveScope scope;
      await tester.pumpWidget(
        MaterialApp(
          home: FormSaveScope(
            onSubmit: () => count++,
            child: Builder(
              builder: (context) {
                scope = FormSaveScope.maybeOf(context)!;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      scope.trySubmit();
      // What the field gets for each repeat of the held key.
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      scope.trySubmit();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      scope.trySubmit();
      expect(count, 1);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      scope.trySubmit();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(count, 2, reason: 'a new press saves again');

      // A soft keyboard's Done holds no key.
      scope.trySubmit();
      expect(count, 3);
    });
  });
}
