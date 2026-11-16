import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/field_label.dart';

/// `LabeledField` draws a field's label above it and hides the one inside
/// (`docs/form-fields.md` § Labels sit above the field). No `ListDensityScope`
/// here, which reads as Comfortable: labels above.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  Widget field({String text = ''}) => LabeledField(
    label: 'Name',
    child: TextField(
      controller: TextEditingController(text: text),
      decoration: const InputDecoration(
        labelText: 'Name',
        hintText: 'Auto generated',
      ),
    ),
  );

  testWidgets('the field keeps its screen-reader name, empty or filled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final text in ['', 'Acme']) {
      await pump(tester, field(text: text));
      expect(
        tester.getSemantics(find.byType(EditableText)).label,
        'Name',
        reason: 'text "$text"',
      );
    }
    handle.dispose();
  });

  testWidgets('the label is matched once, and sits above the box', (
    tester,
  ) async {
    await pump(tester, field());
    // The decoration's own label: still in the tree, drawn at no width, so
    // the border cuts no notch for it.
    final inside = find.text('Name');
    expect(inside, findsOneWidget);
    expect(tester.getSize(inside).width, 0);
    final above = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == 'Name' && w.maxLines == 1,
    );
    expect(
      tester.getBottomLeft(above.first).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
    );
  });

  testWidgets('an empty field shows its hint', (tester) async {
    await pump(tester, field());
    final fade = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Auto generated'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(fade.opacity, 1.0);
  });

  testWidgets('no label, no wrapper; and no app theme is not an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LabeledField(label: null, child: TextField()),
              LabeledField(label: 'Name', child: TextField()),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(InputDecorationTheme), findsOneWidget);
  });
}
