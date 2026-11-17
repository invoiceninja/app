import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/segmented_choice_field.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    required double width,
    String? value = 'left',
    List<String> labels = const ['Left', 'Center', 'Right'],
    bool enabled = true,
  }) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SegmentedChoiceField<String>(
                label: 'Email Alignment',
                value: value,
                options: [
                  for (final l in labels) (value: l.toLowerCase(), label: l),
                ],
                onChanged: enabled ? picked.add : null,
              ),
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('labels that fit render as one segmented control', (
    tester,
  ) async {
    final picked = await pump(tester, width: 600);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNothing);
    // The label is drawn above, where the search reveal looks for it.
    expect(find.text('Email Alignment'), findsOneWidget);

    await tester.tap(find.text('Center'));
    await tester.pump();
    expect(picked, ['center']);
  });

  testWidgets('tapping the selected segment keeps the choice', (tester) async {
    final picked = await pump(tester, width: 600);
    await tester.tap(find.text('Left'));
    await tester.pump();
    expect(picked, isEmpty);
  });

  testWidgets('a value never picked selects no segment', (tester) async {
    await pump(tester, width: 600, value: null);
    final button = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(button.selected, isEmpty);
  });

  testWidgets('labels too long for the width fall back to radios', (
    tester,
  ) async {
    final picked = await pump(
      tester,
      width: 320,
      labels: const [
        'Linksbündig ausrichten',
        'Zentriert ausrichten',
        'Rechtsbündig ausrichten',
      ],
      value: 'linksbündig ausrichten',
    );
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Zentriert ausrichten'));
    await tester.pump();
    expect(picked, ['zentriert ausrichten']);
  });

  testWidgets('a null onChanged disables either form', (tester) async {
    await pump(tester, width: 600, enabled: false);
    final button = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(button.onSelectionChanged, isNull);
  });
}
