// The wide shell's floating timer pill steps aside while the on-screen keyboard
// is up on a touch device — an unfolded foldable with the keyboard up has only
// ~330 pt left, and the pill sat on the field being typed in. The narrow dock
// already does this (`RunningTimerDock`). docs/foldables.md.

import 'package:admin/app/services.dart';
import 'package:admin/ui/features/tasks/widgets/running_timer_pill.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '_task_filter_doubles.dart';

void main() {
  bool offstage(WidgetTester tester) => tester
      .widget<Offstage>(
        find
            .descendant(
              of: find.byType(RunningTimerPill),
              matching: find.byType(Offstage),
            )
            .first,
      )
      .offstage;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Provider<Services>.value(
        value: FakeServices(),
        child: const MaterialApp(home: Scaffold(body: RunningTimerPill())),
      ),
    );
  }

  testWidgets('hidden while the touch keyboard is up, back when it goes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pump(tester);
      expect(offstage(tester), isFalse);
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pump();
      expect(offstage(tester), isTrue);
      tester.view.resetViewInsets();
      await tester.pump();
      expect(offstage(tester), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a desktop keeps it (no soft keyboard to clear)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pump(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pump();
      expect(offstage(tester), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
