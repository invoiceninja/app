import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/activity/widgets/activity_feed_row.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';

import '../../../../_localization_helper.dart';

/// The row's semantics contract.
///
/// `ActivityFeedRow` is the shape `ActivityRecordRow` copied for
/// invoiceninja/flutter#143, and it carried the same latent defect: a
/// `Semantics(button: true)` whose subtree — and with it the `InkWell`'s own
/// `SemanticsAction.tap` — is dropped by `ExcludeSemantics`. Three surfaces
/// mount this widget (`/activity`, the dashboard card, the User Details audit
/// section), and none of them had a test.
Future<void> _pump(WidgetTester tester, {VoidCallback? onTap}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: ActivityFeedRow(
              render: const ActivityRender(
                title: 'Hammy Havoc updated quote 0092',
                meta: '2 minutes ago',
                icon: Icons.description_outlined,
                tone: ActivityTone.sent,
              ),
              meta: '18 May 2026 12:00 · 1.2.3.4',
              onTap: onTap,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a targeted row is a button a screen reader can invoke', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, onTap: () => taps++);

    final data = tester.getSemantics(find.byType(InkWell)).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(
      data.hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'announced but not invocable is the bug this guards',
    );
    expect(data.label, contains('0092'));

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a row with no target renders inert', (tester) async {
    // Its own doc: "A row with no [onTap] renders inert — no ripple, no
    // chevron, no `button` semantics."
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    handle.dispose();
  });

  group('layout', () {
    const render = ActivityRender(
      title: 'Ada Lovelace created invoice 0025',
      meta: '2 minutes ago',
      icon: Icons.edit_outlined,
      tone: ActivityTone.draft,
      segments: [
        ActivitySegment('Ada Lovelace', isValue: true),
        ActivitySegment(' created invoice '),
        ActivitySegment('0025', isValue: true),
      ],
    );

    Future<void> pumpAt(WidgetTester tester, double width) async {
      await tester.binding.setSurfaceSize(const Size(1400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: const ActivityFeedRow(
                  render: render,
                  time: '7:12 AM',
                  meta: '1.2.3.4',
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the filled values are in the strong weight', (tester) async {
      await pumpAt(tester, 700);
      final text = tester.widget<Text>(find.textContaining('created invoice'));
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.text, 'Ada Lovelace');
      expect(spans.first.style?.fontWeight, FontWeight.w600);
      expect(spans[1].style?.fontWeight, isNull);
    });

    testWidgets('a wide row puts the time in its own leading column', (
      tester,
    ) async {
      await pumpAt(tester, 700);
      expect(find.text('7:12 AM'), findsOneWidget);
      expect(find.text('1.2.3.4'), findsOneWidget);
      // Leading: before the sentence, on the same line.
      final time = tester.getRect(find.text('7:12 AM'));
      final sentence = tester.getRect(find.textContaining('created invoice'));
      expect(time.left, lessThan(sentence.left));
      expect((time.top - sentence.top).abs(), lessThan(6));
    });

    testWidgets('a narrow row (the pane, not the window) moves the time to '
        'the meta line', (tester) async {
      // The window is 1400 px wide; the row is not.
      await pumpAt(tester, 420);
      expect(find.text('7:12 AM · 1.2.3.4'), findsOneWidget);
    });
  });
}
