import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/features/tasks/widgets/running_duration_label.dart';
import 'package:admin/ui/features/tasks/widgets/running_timer_pill.dart';

import '../../../../_localization_helper.dart';
import '../../shell/_shell_test_helpers.dart';

/// The phone shell docks the running timer as a full-width bar UNDER the
/// content (`RunningTimerDock`). The floating pill it replaced sat 112 px up,
/// above every screen's FAB clearance, so it covered a field or a row on most
/// phone screens and no scrollable paid for it.
///
/// What makes the dock work with no per-screen code is all in
/// `RunningTimerDockLayout`, pumped here without `Services`: the bar owns the
/// bottom safe inset (the content sees none while it shows), it hides while
/// the keyboard is up, it lifts toasts above itself, and the content never
/// remounts as a timer starts or stops.

const _window = Size(390, 844);
const _inset = 34.0;

final _theme = ThemeData.light().copyWith(
  extensions: <ThemeExtension<dynamic>>[InTheme.light],
);

RunningTimerDockSurface _running({
  VoidCallback? onOpen,
  VoidCallback? onStop,
  VoidCallback? onStopAll,
  int count = 1,
}) => RunningTimerDockSurface.running(
  label: 'Kitchen refit',
  start: DateTime.now().subtract(const Duration(minutes: 30)),
  runningCount: count,
  onOpen: onOpen ?? () {},
  onStop: onStop ?? () {},
  onStopAll: onStopAll ?? () {},
);

/// Records the MediaQuery the content is handed, and keeps a counter so a
/// remount (which would reset it) is visible.
class _Probe extends StatefulWidget {
  const _Probe();

  static MediaQueryData? seen;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    _Probe.seen = MediaQuery.of(context);
    return Scaffold(
      body: GestureDetector(
        onTap: () => setState(() => taps++),
        child: Center(child: Text('taps $taps')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required RunningTimerDockSurface? surface,
  double keyboard = 0,
  ToastController? toasts,
}) async {
  tester.view.physicalSize = _window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme,
      localizationsDelegates: kTestLocalizationsDelegates,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // Flutter's own derivation: `padding` is the safe inset less
            // whatever the keyboard already covers.
            viewPadding: const EdgeInsets.only(bottom: _inset),
            padding: EdgeInsets.only(bottom: keyboard > 0 ? 0 : _inset),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: RunningTimerDockLayout(
            surface: surface,
            toasts: toasts,
            child: const _Probe(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('no timer: the content keeps the whole window and the inset', (
    tester,
  ) async {
    await _pump(tester, surface: null);
    expect(tester.getSize(find.byType(_Probe)).height, _window.height);
    expect(_Probe.seen!.padding.bottom, _inset);
    expect(find.text('Kitchen refit'), findsNothing);
  });

  testWidgets('docked: the bar sits under the content and owns the inset', (
    tester,
  ) async {
    await _pump(tester, surface: _running());
    final bar = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is Material && w.color == InTheme.light.inverseSurface,
      ),
    );
    // 48 px of bar plus the safe inset it paints beneath itself, flush with
    // the bottom of the window.
    expect(bar.height, kRunningTimerDockHeight + _inset);
    expect(bar.bottom, _window.height);
    // The content ends where the bar begins, and is told there is no inset
    // left to pay — so no SafeArea, list or FAB above pays it twice.
    final content = tester.getRect(find.byType(_Probe));
    expect(content.bottom, bar.top);
    expect(_Probe.seen!.padding.bottom, 0);
    expect(_Probe.seen!.viewPadding.bottom, 0);
  });

  testWidgets('a FAB on the screen above sits clear of the bar', (
    tester,
  ) async {
    await _pump(tester, surface: _running());
    final fab = tester.getRect(find.byType(FloatingActionButton));
    final content = tester.getRect(find.byType(_Probe));
    // Material's own 16 px margin above the content's bottom edge, with no
    // inset added (the bar paid it).
    expect(fab.bottom, content.bottom - kFloatingActionButtonMargin);
  });

  testWidgets('the keyboard hides the bar and hands the content back', (
    tester,
  ) async {
    await _pump(tester, surface: _running(), keyboard: 300);
    expect(find.text('Kitchen refit'), findsNothing);
    expect(tester.getSize(find.byType(_Probe)).height, _window.height);
    // Nothing removed: the screen's Scaffold resizes for the keyboard itself.
    expect(_Probe.seen!.viewPadding.bottom, _inset);
    expect(_Probe.seen!.viewInsets.bottom, 300);
  });

  testWidgets('a timer starting or stopping never remounts the content', (
    tester,
  ) async {
    await _pump(tester, surface: null);
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);

    await _pump(tester, surface: _running());
    expect(find.text('taps 1'), findsOneWidget);

    await _pump(tester, surface: _running(), keyboard: 300);
    expect(find.text('taps 1'), findsOneWidget);

    await _pump(tester, surface: null);
    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('a bottom toast is lifted above the bar, not the inset twice', (
    tester,
  ) async {
    final toasts = ToastController();
    addTearDown(toasts.dispose);
    await _pump(tester, surface: _running(), toasts: toasts);
    await tester.pump();
    // The toast host adds the safe inset on its own, so the bar reports only
    // its row.
    expect(toasts.bottomInset.value, kRunningTimerDockHeight);

    await _pump(tester, surface: null, toasts: toasts);
    await tester.pump();
    expect(toasts.bottomInset.value, 0);
  });

  testWidgets('stop is a 44 px target; the body opens the task', (
    tester,
  ) async {
    var opened = 0;
    var stopped = 0;
    await _pump(
      tester,
      surface: _running(onOpen: () => opened++, onStop: () => stopped++),
    );
    final stop = find.byTooltip('Stop');
    expect(tester.getSize(stop), const Size(44, 44));
    await tester.tap(stop);
    await tester.tap(find.text('Kitchen refit'));
    expect(stopped, 1);
    expect(opened, 1);
  });

  testWidgets('concurrent timers offer Stop all with the count', (
    tester,
  ) async {
    var all = 0;
    await _pump(tester, surface: _running(count: 3, onStopAll: () => all++));
    // The test font draws every glyph a square, so here the text is about
    // twice its real width and the bar collapses it to the badged icon; the
    // real-font group below pins which form shows when.
    final text = find.textContaining('(3)');
    await tester.tap(
      text.evaluate().isNotEmpty ? text : find.byTooltip('Stop all'),
    );
    expect(all, 1);
  });

  testWidgets('a booked block that is due now offers Start', (tester) async {
    var started = 0;
    await _pump(
      tester,
      surface: RunningTimerDockSurface.dueNow(
        label: 'Boiler service',
        onOpen: () {},
        onStart: () => started++,
      ),
    );
    expect(find.text('Boiler service'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
    await tester.tap(find.byTooltip('Start'));
    expect(started, 1);
  });

  testWidgets('the bar is inverted: ink fill, light text, a mono duration', (
    tester,
  ) async {
    await _pump(tester, surface: _running());
    const t = InTheme.light;
    expect(
      find.byWidgetPredicate(
        (w) => w is Material && w.color == t.inverseSurface,
      ),
      findsOneWidget,
    );
    final label = tester.widget<Text>(find.text('Kitchen refit'));
    expect(label.style?.color, t.onInverseMuted);
    final duration = tester.widget<RunningDurationLabel>(
      find.byType(RunningDurationLabel),
    );
    expect(duration.style?.fontFamily, kMonoFontFamily);
    expect(duration.style?.color, t.onInverse);
    final stop = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Stop'),
        matching: find.byType(IconButton),
      ),
    );
    expect(stop.color, t.onInverse);
  });

  testWidgets('due now keeps its warning cue on the inverted bar', (
    tester,
  ) async {
    await _pump(
      tester,
      surface: RunningTimerDockSurface.dueNow(
        label: 'Boiler service',
        onOpen: () {},
        onStart: () {},
      ),
    );
    const t = InTheme.light;
    // A booked block is not a running timer: no ticking duration, and the
    // label and the Start button take the caution colour, not the light ink.
    expect(find.byType(RunningDurationLabel), findsNothing);
    final due = tester.widget<Text>(find.text('Due now'));
    expect(due.style?.color, t.warningOnInverse);
    final start = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Start'),
        matching: find.byType(IconButton),
      ),
    );
    expect(start.color, t.warningOnInverse);
  });

  testWidgets('no edit permission: no Stop, the bar still opens the task', (
    tester,
  ) async {
    await _pump(
      tester,
      surface: RunningTimerDockSurface.running(
        label: 'Teammate task',
        start: DateTime.now(),
        onOpen: () {},
      ),
    );
    expect(find.text('Teammate task'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
  });

  group('a tight phone bar at 2x text', () {
    // Real metrics, not the test font (a square per glyph): the overflow is a
    // question of how wide the mono duration and "Stop all (N)" really are.
    setUpAll(() async {
      for (final font in const [
        (kSansFontFamily, 'assets/fonts/InterTight.ttf'),
        (kMonoFontFamily, 'assets/fonts/JetBrainsMono.ttf'),
      ]) {
        await (FontLoader(font.$1)..addFont(
              Future.value(File(font.$2).readAsBytesSync().buffer.asByteData()),
            ))
            .load();
      }
    });

    Future<void> pumpTight(
      WidgetTester tester, {
      required double width,
      required Duration elapsed,
      VoidCallback? onStop,
      VoidCallback? onStopAll,
    }) async {
      final size = Size(width, 700);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: RunningTimerDockLayout(
                surface: RunningTimerDockSurface.running(
                  label: 'Kitchen refit',
                  start: DateTime.now().subtract(elapsed),
                  runningCount: 3,
                  onOpen: () {},
                  onStop: onStop ?? () {},
                  onStopAll: onStopAll ?? () {},
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final width in const [320.0, 360.0]) {
      for (final elapsed in const [Duration(hours: 30), Duration(hours: 2)]) {
        testWidgets('${width.toInt()} px, a ${elapsed.inHours} h timer: '
            'Stop and Stop all stay on screen and tappable', (tester) async {
          var stopped = 0;
          var all = 0;
          await pumpTight(
            tester,
            width: width,
            elapsed: elapsed,
            onStop: () => stopped++,
            onStopAll: () => all++,
          );
          expect(tester.takeException(), isNull);
          final stop = tester.getRect(find.byTooltip('Stop'));
          expect(stop.left, greaterThanOrEqualTo(0));
          expect(stop.right, lessThanOrEqualTo(width));
          await tester.tap(find.byTooltip('Stop'));
          expect(stopped, 1);
          // Full text where it fits, an icon with the count where it does not
          // — either way it is reachable.
          final stopAll = find.byTooltip('Stop all').evaluate().isNotEmpty
              ? find.byTooltip('Stop all')
              : find.textContaining('(3)');
          final r = tester.getRect(stopAll);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(stop.left + 0.5));
          await tester.tap(stopAll);
          expect(all, 1);
        });
      }
    }

    testWidgets('a roomy bar keeps the "Stop all (N)" text', (tester) async {
      await pumpTight(tester, width: 600, elapsed: const Duration(hours: 2));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('(3)'), findsOneWidget);
    });
  });

  group('RunningTimerDock over the real task streams', () {
    Future<void> running(ShellFixture f, {required bool on}) =>
        f.db.taskDao.upsert(
          TasksCompanion.insert(
            id: 't1',
            companyId: 'co1',
            updatedAt: on ? 1 : 2,
            isRunning: Value(on),
            payload: jsonEncode({
              'id': 't1',
              'number': '0042',
              'description': 'Kitchen refit',
              'time_log': jsonEncode([
                [1700000000, on ? 0 : 1700003600, '', true],
              ]),
            }),
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    Widget host(Services services, {String? hiddenTaskId}) =>
        Provider<Services>.value(
          value: services,
          child: MaterialApp(
            localizationsDelegates: kTestLocalizationsDelegates,
            theme: _theme,
            home: RunningTimerDock(
              hiddenTaskId: hiddenTaskId,
              child: const _Probe(),
            ),
          ),
        );

    testWidgets('docks while a timer runs and undocks when it stops', (
      tester,
    ) async {
      tester.view.physicalSize = _window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Acme')],
        closeStreamsSynchronously: true,
      );
      addTearDown(f.dispose);

      await tester.pumpWidget(host(f.services));
      await settle(tester);
      expect(find.text('Kitchen refit'), findsNothing);
      expect(tester.getSize(find.byType(_Probe)).height, _window.height);

      await tester.runAsync(() => running(f, on: true));
      await settle(tester);
      expect(find.text('Kitchen refit'), findsOneWidget);
      expect(
        tester.getSize(find.byType(_Probe)).height,
        _window.height - kRunningTimerDockHeight,
      );

      await tester.runAsync(() => running(f, on: false));
      await settle(tester);
      expect(find.text('Kitchen refit'), findsNothing);
      expect(tester.getSize(find.byType(_Probe)).height, _window.height);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('leaves out the task whose edit screen is open', (
      tester,
    ) async {
      // invoiceninja/app#204: that form's Stop is a draft until Save, so the
      // bar went on ticking under a form that said the timer had stopped.
      tester.view.physicalSize = _window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Acme')],
        closeStreamsSynchronously: true,
      );
      addTearDown(f.dispose);
      await tester.runAsync(() => running(f, on: true));

      await tester.pumpWidget(host(f.services, hiddenTaskId: 't1'));
      await settle(tester);
      expect(find.text('Kitchen refit'), findsNothing);
      expect(tester.getSize(find.byType(_Probe)).height, _window.height);

      // Leaving the edit screen brings it back, on the same mounted dock.
      await tester.pumpWidget(host(f.services));
      await settle(tester);
      expect(find.text('Kitchen refit'), findsOneWidget);

      await tester.pumpWidget(host(f.services, hiddenTaskId: 't1'));
      await settle(tester);
      expect(find.text('Kitchen refit'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('taskIdBeingEdited', () {
    test('reads the id off a task edit route', () {
      expect(
        taskIdBeingEdited(Uri.parse('/tasks/Wpmbk5ezJn/edit')),
        'Wpmbk5ezJn',
      );
      expect(
        taskIdBeingEdited(Uri.parse('/tasks/Wpmbk5ezJn/edit?view=full')),
        'Wpmbk5ezJn',
      );
    });

    test('is null anywhere else', () {
      for (final path in [
        '/tasks',
        '/tasks/new',
        '/tasks/new/edit',
        '/tasks/Wpmbk5ezJn',
        '/clients/Wpmbk5ezJn/edit',
        '/tasks/Wpmbk5ezJn/edit/extra',
      ]) {
        expect(taskIdBeingEdited(Uri.parse(path)), isNull, reason: path);
      }
    });
  });
}
