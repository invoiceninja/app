// `DismissOnWindowResize` closes a popup anchored by a global position once the
// window changes size (a foldable opening or closing), and leaves it alone when
// only the keyboard comes up. docs/foldables.md.

import 'package:admin/ui/core/widgets/dismiss_on_window_resize.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openPopup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const DismissOnWindowResize(child: Text('POPUP')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('POPUP'), findsOneWidget);
  }

  testWidgets('a window resize closes it', (tester) async {
    await openPopup(tester);
    tester.view.physicalSize = const Size(951, 669);
    await tester.pumpAndSettle();
    expect(find.text('POPUP'), findsNothing);
  });

  testWidgets('the keyboard coming up does not', (tester) async {
    await openPopup(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.text('POPUP'), findsOneWidget);
  });
}
