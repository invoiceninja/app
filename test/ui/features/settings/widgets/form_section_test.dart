import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('renders the title with no rule under it', (tester) async {
    await pump(
      tester,
      const FormSection(title: 'Client', children: [Text('field')]),
    );

    expect(find.text('Client'), findsOneWidget);
    // The fields follow the title in the card's padding, as on the edit forms.
    expect(find.byType(Divider), findsNothing);
    expect(find.text('field'), findsOneWidget);
  });

  testWidgets('title:null omits the header row and the divider', (
    tester,
  ) async {
    await pump(
      tester,
      const FormSection(title: null, children: [Text('field')]),
    );

    expect(find.byType(Divider), findsNothing);
    expect(find.text('field'), findsOneWidget);
  });

  testWidgets('elevated:false drops the boxShadow (keeps the border)', (
    tester,
  ) async {
    await pump(
      tester,
      const FormSection(
        title: null,
        elevated: false,
        children: [Text('field')],
      ),
    );

    final decorated = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(FormSection),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);
    expect(decorated.boxShadow, anyOf(isNull, isEmpty));
    expect(decorated.border, isNotNull);
  });
}
