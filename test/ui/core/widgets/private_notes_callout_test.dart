// The private-notes callout — docs/detail-screen-layout.md § Private notes
// are a callout above the comments. Beta feedback (Nov 2026): account
// information kept in Private Notes was being overlooked.

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/private_notes_callout.dart';

import '../../../_localization_helper.dart';

const _calloutKey = ValueKey('private-notes-callout');

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  InTheme tokens = InTheme.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(tokens),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(key: ValueKey('above'), height: 10),
              child,
              const SizedBox(key: ValueKey('below'), height: 10),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('is content only when the stored HTML holds words', () {
    expect(PrivateNotesCallout.hasContent('x'), isTrue);
    expect(PrivateNotesCallout.hasContent('<p>Call Jane</p>'), isTrue);
    for (final empty in ['', '   ', '<p></p>', '<p><br></p>', '<p> </p>']) {
      expect(
        PrivateNotesCallout.hasContent(empty),
        isFalse,
        reason: '"$empty"',
      );
    }
  });

  testWidgets('shows the words, not the markup, under a lock and the label', (
    tester,
  ) async {
    await _pump(
      tester,
      const PrivateNotesCallout(notes: '<p>Call <b>Jane</b> first.</p>'),
    );
    expect(find.byKey(_calloutKey), findsOneWidget);
    expect(find.text('Private Notes'), findsOneWidget);
    expect(find.text('Call Jane first.'), findsOneWidget);
    expect(find.textContaining('<'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('is drawn in the warning tone of the theme it is in', (
    tester,
  ) async {
    for (final tokens in [InTheme.light, InTheme.dark]) {
      await _pump(
        tester,
        const PrivateNotesCallout(notes: 'On credit hold'),
        tokens: tokens,
      );
      // MaterialApp animates a theme change.
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(find.byKey(_calloutKey));
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, tokens.warningSoft);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.lock_outline)).color,
        tokens.warning,
      );
    }
  });

  for (final (name, notes) in [
    ('blank', ''),
    ('whitespace', '  \n '),
    ('markup that renders as nothing', '<p><br></p>'),
  ]) {
    testWidgets('$name notes draw nothing at all', (tester) async {
      await _pump(tester, PrivateNotesCallout(notes: notes));
      expect(find.byKey(_calloutKey), findsNothing);
      expect(find.text('Private Notes'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('below'))).dy -
            tester.getBottomLeft(find.byKey(const ValueKey('above'))).dy,
        0,
      );
    });
  }

  testWidgets('a long note is clamped with an in-place More', (tester) async {
    final long = List.generate(12, (i) => 'Line ${i + 1}').join('\n');
    await _pump(tester, PrivateNotesCallout(notes: long));
    expect(
      tester.widget<Text>(find.text(long)).maxLines,
      kPrivateNotesCalloutLines,
    );
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
    expect(find.text('Less'), findsOneWidget);
  });

  group('copy', () {
    String? copied;

    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('touch: a long-press copies the whole note as plain text', (
      tester,
    ) async {
      await _pump(
        tester,
        const PrivateNotesCallout(notes: '<p>Gate code <b>4417</b></p>'),
      );
      await tester.longPress(find.text('Gate code 4417'));
      await tester.pump();
      expect(copied, 'Gate code 4417');
      // Let the "Copied" toast's timer run out.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('touch: a tap does not copy — it is the clamp\'s More', (
      tester,
    ) async {
      await _pump(tester, const PrivateNotesCallout(notes: 'Short note'));
      await tester.tap(find.text('Short note'));
      await tester.pump();
      expect(copied, isNull);
    });
  });
}
