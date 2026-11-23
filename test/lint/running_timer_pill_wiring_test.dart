import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shell's railed (wide) branch pins `RunningTimerPill` above every
/// screen; where it pins the pill decides whether the pill covers a screen's
/// create FAB. invoiceninja/flutter#164 gave the dashboard a FAB on a phone in
/// landscape, where the shell is in its railed branch and used to put the pill
/// in exactly that corner. The narrow branch DOCKS the timer under the content
/// instead (`RunningTimerDock`, pumped in `running_timer_dock_test.dart`).
///
/// `runningTimerPillBottom` holds the rule and has its own unit test.
/// `ScaffoldWithNav` cannot be pumped (`InSidebar` deadlocks on its
/// saved-views Drift watch, see `sidebar_footer_wiring_test.dart`), so this
/// source scan is what keeps each branch on its surface.
void main() {
  String code(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '$path is missing');
    // Strip `//` tails so a comment that names the helper can't satisfy the
    // scan.
    return f
        .readAsLinesSync()
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');
  }

  test('the narrow branch docks the timer around the navigation shell', () {
    // The dock has to WRAP the content — it removes the bottom inset the
    // content sees and ends the content above itself — so a pill floated
    // beside the shell in a `Stack` is the regression this guards.
    final src = code('lib/ui/features/shell/scaffold_with_nav.dart');
    expect(
      RegExp(
        // `child:` last (`sort_child_properties_last`), after `hiddenTaskId:`.
        r'RunningTimerDock\((?:[^;]*?,)?\s*child:\s*widget\.navigationShell',
      ).allMatches(src),
      hasLength(1),
    );
  });

  test('the railed branch places the pill through the shared rule', () {
    final lines = code(
      'lib/ui/features/shell/scaffold_with_nav.dart',
    ).split('\n');
    final pills = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].contains('RunningTimerPill(')) i,
    ];
    expect(
      pills,
      hasLength(1),
      reason: 'the railed branch floats the pill; the narrow one docks it',
    );

    for (final at in pills) {
      // The `Positioned` that places the pill, whichever side of the pill it
      // is written on: the wide branch builds the pill first and positions it
      // in a builder below.
      //
      // The window is wide (35 lines) because the wide branch's offset depends on
      // **two** things that change independently — the rail's width and whether
      // the screen underneath shows a FAB, the latter driven by the Tasks view
      // toggle, which changes no route — so it nests two
      // `ValueListenableBuilder`s between the pill and its `Positioned`. Verified
      // that neither window contains a literal `bottom: <digit>` from an
      // unrelated widget, which is what keeps the second assertion meaningful at
      // this width.
      final around = lines
          .sublist((at - 35).clamp(0, lines.length), at)
          .followedBy(lines.sublist(at, (at + 36).clamp(0, lines.length)))
          .join('\n');
      expect(
        around,
        contains('bottom: runningTimerPillBottom('),
        reason: 'the pill at line ${at + 1} must take its offset from the rule',
      );
      expect(
        RegExp(r'bottom:\s*\d').hasMatch(around),
        isFalse,
        reason:
            'a literal offset beside the pill at line ${at + 1} is the '
            'regression this guards',
      );
    }
  });

  test('the railed branch measures the pane, not the window', () {
    // The pane is the window less the rail, and the rail's width follows the
    // collapse toggle. Measuring the window would keep the pill in the corner
    // for the whole 600–832 px band, where every list screen shows its FAB.
    final src = code('lib/ui/features/shell/scaffold_with_nav.dart');
    expect(
      RegExp(
        r'paneWidth:\s*constraints\.maxWidth\s*-\s*\(\s*collapsed',
      ).hasMatch(src),
      isTrue,
    );
  });

  test('the railed pill clears a published bottom bar', () {
    // A desktop invoice editor with a timer running: the pill sat 16 px up,
    // on the sticky totals bar's Total. Bars publish their height through
    // `ToastBottomInset`; the pill's offset has to read it.
    final src = code('lib/ui/features/shell/scaffold_with_nav.dart');
    expect(
      RegExp(r'bottomBar:\s*services\s*\.toasts\s*\.bottomInset').hasMatch(src),
      isTrue,
    );
    expect(src, contains('services.toasts.bottomInset,'));
  });

  test('every bottom bar publishes itself', () {
    // The three bars a screen pins to its bottom edge. A new one goes through
    // `ToastBottomInset` too, or the toast and the pill cover it.
    final desktop = code(
      'lib/ui/features/billing_shared/edit/billing_doc_edit_desktop_shell.dart',
    );
    expect(
      RegExp(
        r'ToastBottomInset\([^;]*?child:\s*stickyTotals',
      ).hasMatch(desktop),
      isTrue,
      reason: 'the wide billing editor\'s sticky totals',
    );
    final mobile = code(
      'lib/ui/features/billing_shared/edit/billing_doc_edit_layout.dart',
    );
    expect(
      RegExp(
        r'ToastBottomInset\([^;]*?_Totals<T>\([^)]*dense:\s*true\s*\)',
      ).hasMatch(mobile),
      isTrue,
      reason: 'the narrow billing editor\'s sticky totals',
    );
    final list = code('lib/ui/core/list/entity_list_screen_scaffold.dart');
    expect(
      RegExp(r'bottomNavigationBar:\s*_publishedBottomBar\(').hasMatch(list),
      isTrue,
      reason: 'the list selection bar',
    );
  });
}
