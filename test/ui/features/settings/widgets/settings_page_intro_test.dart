import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_page_intro.dart';

/// A settings page's intro sentence and its page-level actions share ONE row
/// (`docs/settings-screens.md` § A page's intro and its actions share one
/// row): the sentence at the start, wrapping, the actions at the end level
/// with its first line — and under it, never overflowing, where the row is
/// too narrow.

const _long =
    'The designs your documents print with, and what they show, '
    'for every kind of document this company sends to its clients.';

Widget _button(String label) => OutlinedButton(
  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
  onPressed: () {},
  child: Text(label),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 800,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _sentence => find.byKey(const ValueKey('settings-page-subtitle'));

void main() {
  testWidgets('the actions sit at the end, level with the first line of a '
      'sentence that wraps beside them', (tester) async {
    await _pump(
      tester,
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SettingsPageIntro(key: Key('one-line'), text: 'One line.'),
            SettingsPageIntro(text: _long, actions: [_button('Act')]),
          ],
        ),
      ),
      width: 600,
    );

    final line = tester
        .getSize(
          find.descendant(
            of: find.byKey(const Key('one-line')),
            matching: _sentence,
          ),
        )
        .height;
    final long = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is SettingsPageIntro && w.actions.isNotEmpty,
      ),
      matching: _sentence,
    );
    final button = find.byType(OutlinedButton);
    final sentence = tester.getRect(long);
    // It did wrap — the case worth pinning.
    expect(sentence.height, greaterThan(line * 1.5));
    expect(
      tester.getCenter(button).dy,
      moreOrLessEquals(sentence.top + line / 2, epsilon: 1),
    );
    expect(tester.getTopLeft(button).dx, greaterThan(sentence.right));
    expect(tester.getTopRight(button).dx, moreOrLessEquals(600 - 24));
  });

  testWidgets('right-to-left: the sentence at the right, the actions at the '
      'left', (tester) async {
    await _pump(
      tester,
      SettingsPageIntro(text: 'Intro.', actions: [_button('Act')]),
      direction: TextDirection.rtl,
    );

    expect(
      tester.getTopRight(_sentence).dx,
      moreOrLessEquals(800, epsilon: 0.5),
    );
    expect(
      tester.getTopLeft(find.byType(OutlinedButton)).dx,
      moreOrLessEquals(0),
    );
  });

  testWidgets('actions with no sentence sit at the end on their own', (
    tester,
  ) async {
    await _pump(tester, SettingsPageIntro(actions: [_button('Act')]));

    expect(_sentence, findsNothing);
    expect(tester.getTopRight(find.byType(OutlinedButton)).dx, 800);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('320 px at ${scale}x: the actions drop under the sentence '
        'and nothing overflows', (tester) async {
      await _pump(
        tester,
        Padding(
          padding: const EdgeInsets.all(InSpacing.xl),
          child: SettingsPageIntro(
            text: _long,
            actions: [_button('Show Preview'), _button('New design')],
          ),
        ),
        width: 320,
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      final buttons = find.byType(OutlinedButton);
      for (final b in buttons.evaluate()) {
        final rect = tester.getRect(find.byWidget(b.widget));
        expect(
          rect.top,
          greaterThanOrEqualTo(tester.getRect(_sentence).bottom),
        );
        expect(rect.right, lessThanOrEqualTo(320 - InSpacing.xl + 0.5));
      }
    });
  }

  testWidgets('SettingsFormShell: the subtitle and its actions share the row '
      'above the first section', (tester) async {
    await _pump(
      tester,
      SettingsFormShell(
        subtitle: 'Intro.',
        actions: [_button('Act')],
        sections: const [SizedBox(height: 40, child: Text('CARD'))],
      ),
    );

    final button = find.byType(OutlinedButton);
    expect(
      tester.getCenter(_sentence).dy,
      moreOrLessEquals(tester.getCenter(button).dy, epsilon: 1),
    );
    // The card follows the row directly: one gap, no spacer row.
    expect(
      tester.getTopLeft(find.text('CARD')).dy,
      moreOrLessEquals(tester.getBottomLeft(button).dy + 16, epsilon: 0.5),
    );
  });

  testWidgets('SettingsFormShell: actions handed down by a shell join the '
      'page\'s own, once — a nested shell does not repeat them', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsPageActions(
        actions: [_button('Shell')],
        child: SettingsFormShell(
          actions: [_button('Page')],
          child: SizedBox(
            height: 300,
            child: SettingsFormShell(
              sections: const [SizedBox(height: 40, child: Text('INNER'))],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('Page'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Shell')).dy,
      tester.getCenter(find.text('Page')).dy,
    );
    // Page's own first, then the shell's, at the end.
    expect(
      tester.getCenter(find.text('Page')).dx,
      lessThan(tester.getCenter(find.text('Shell')).dx),
    );
  });
}
