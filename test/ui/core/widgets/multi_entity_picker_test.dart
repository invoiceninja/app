// A multi-picker with nothing to offer said "Loading…" for good: its empty
// hint fell through to the single picker's default. A stream-fed caller says
// Loading only until the stream answers (as the single pickers do since
// a4ee157e); an empty answer, or an empty list handed over directly, reads
// None.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/multi_entity_picker.dart';

import '../../../_localization_helper.dart';

void main() {
  Future<void> pump(WidgetTester tester, {String? emptyHintKey}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: emptyHintKey == null
                ? MultiEntityPicker<String>(
                    labelKey: 'clients',
                    selectedIds: const [],
                    items: const [],
                    idOf: (s) => s,
                    displayString: (s) => s,
                    onChanged: (_) {},
                  )
                : MultiEntityPicker<String>(
                    labelKey: 'clients',
                    selectedIds: const [],
                    items: const [],
                    idOf: (s) => s,
                    displayString: (s) => s,
                    onChanged: (_) {},
                    emptyHintKey: emptyHintKey,
                  ),
          ),
        ),
      );

  String? hint(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText;

  testWidgets('no items reads None, not Loading', (tester) async {
    await pump(tester);
    expect(hint(tester), 'None');
  });

  testWidgets('a caller still waiting on its stream says Loading', (
    tester,
  ) async {
    await pump(tester, emptyHintKey: 'loading');
    expect(hint(tester), isNot('None'));
    expect(hint(tester), startsWith('Loading'));
  });
}
