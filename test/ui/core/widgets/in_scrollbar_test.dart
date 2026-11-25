// The pointer platforms' scroll bar (docs/scrollbars.md): the look, the
// "Always show scroll bars" pin, and — the reason the pin is not a theme-level
// `thumbVisibility` — the trees on which that pin used to assert.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/always_show_scrollbars_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/ui/core/widgets/in_scrollbar.dart';

final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

/// Every scroll bar painter on screen.
List<ScrollbarPainter> _painters(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.foregroundPainter case final ScrollbarPainter p) p,
];

/// The painters whose thumb is fully drawn.
int _shown(WidgetTester tester) =>
    _painters(tester).where((p) => p.fadeoutOpacityAnimation.value == 1).length;

Widget _rows(int n, {ScrollController? controller, bool? primary}) =>
    ListView.builder(
      controller: controller,
      primary: primary,
      itemCount: n,
      itemExtent: 40,
      itemBuilder: (_, i) => Text('row $i'),
    );

class _Harness {
  _Harness()
    : always = AlwaysShowScrollbarsController(prefs: DevicePrefsStore(null));

  final AlwaysShowScrollbarsController always;
  final dark = ValueNotifier(false);

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AlwaysShowScrollbarsController>.value(
        value: always,
        child: ValueListenableBuilder<bool>(
          valueListenable: dark,
          builder: (context, isDark, _) => MaterialApp(
            theme: buildInTheme(
              isDark ? InTheme.darkEspresso : InTheme.light,
              pointerScrollbars: true,
            ),
            scrollBehavior: const InScrollBehavior(),
            home: Scaffold(body: body),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Several frames — the bar pins from a post-frame metrics notification and
  /// fades over 300 ms.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  group('the scroll behavior', () {
    testWidgets('gives a vertical scroll view an InScrollbar on a pointer '
        'platform, and a horizontal one none', (tester) async {
      await _Harness().pump(
        tester,
        Column(
          children: [
            Expanded(child: _rows(50)),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < 30; i++) Text('cell $i  ')],
              ),
            ),
          ],
        ),
      );
      expect(find.byType(InScrollbar), findsOneWidget);
      expect(find.byType(Scrollbar), findsNothing);
    }, variant: _desktop);

    testWidgets('gives none on a touch platform, as Material does', (
      tester,
    ) async {
      await _Harness().pump(tester, _rows(50));
      expect(find.byType(InScrollbar), findsNothing);
      expect(find.byType(Scrollbar), findsNothing);
    });
  });

  group('the look', () {
    test('a touch platform keeps Material\'s scroll bar theme', () {
      expect(
        buildInTheme(InTheme.light, pointerScrollbars: false).scrollbarTheme,
        ThemeData().scrollbarTheme,
      );
    });

    test('a pointer thumb is a rounded rectangle at both sizes, never a '
        'pill', () {
      final theme = pointerScrollbarTheme(InTheme.light);
      for (final states in [
        <WidgetState>{},
        {WidgetState.hovered},
        {WidgetState.dragged},
      ]) {
        final thickness = theme.thickness!.resolve(states)!;
        expect(theme.radius!.x, lessThan(thickness / 2), reason: '$states');
      }
      expect(theme.thickness!.resolve({}), InSizes.scrollbarThumb);
      expect(
        theme.thickness!.resolve({WidgetState.hovered}),
        InSizes.scrollbarThumbActive,
      );
    });

    test('every palette draws the thumb in its own ink, darker under the '
        'pointer', () {
      for (final tokens in [
        InTheme.lightSand,
        InTheme.lightMist,
        InTheme.lightPaper,
        InTheme.darkEspresso,
        InTheme.darkMidnight,
        InTheme.darkCarbon,
      ]) {
        final theme = pointerScrollbarTheme(tokens);
        expect(theme.thumbColor!.resolve({}), tokens.ink3);
        expect(theme.thumbColor!.resolve({WidgetState.hovered}), tokens.ink2);
        expect(theme.thumbColor!.resolve({WidgetState.dragged}), tokens.ink);
        expect(theme.trackVisibility!.resolve({}), isFalse);
        expect(theme.trackVisibility!.resolve({WidgetState.hovered}), isTrue);
      }
    });

    testWidgets('the thumb grows and gains a track under the mouse, and '
        'gives both back when it leaves', (tester) async {
      final h = _Harness();
      unawaited(h.always.set(true));
      await h.pump(tester, _rows(50));
      final painter = _painters(tester).single;
      expect(painter.thickness, InSizes.scrollbarThumb);
      expect(painter.trackColor.a, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(300, 200));
      await tester.pump();
      // Over the thumb, at the top of the right edge.
      await mouse.moveTo(const Offset(600 - 6, 20));
      await _Harness.settle(tester);
      expect(painter.thickness, InSizes.scrollbarThumbActive);
      expect(painter.trackColor.a, greaterThan(0));
      expect(painter.color, isSameColorAs(InTheme.light.ink2));

      await mouse.moveTo(const Offset(300, 200));
      await _Harness.settle(tester);
      expect(painter.thickness, InSizes.scrollbarThumb);
      expect(painter.trackColor.a, 0);
      expect(painter.color, isSameColorAs(InTheme.light.ink3));
    }, variant: _desktop);
  });

  group('Always show scroll bars', () {
    testWidgets('off: the thumb shows while scrolling, then fades', (
      tester,
    ) async {
      await _Harness().pump(tester, _rows(50));
      expect(_shown(tester), 0);
      final drag = await tester.startGesture(const Offset(300, 200));
      await drag.moveBy(const Offset(0, -80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_shown(tester), 1);
      await drag.up();
      await _Harness.settle(tester);
      expect(_shown(tester), 0);
    }, variant: _desktop);

    testWidgets('on: the thumb is drawn without a scroll, and the switch '
        'pins and unpins it live', (tester) async {
      final h = _Harness();
      unawaited(h.always.set(true));
      await h.pump(tester, _rows(50));
      expect(_shown(tester), 1);

      unawaited(h.always.set(false));
      await _Harness.settle(tester);
      expect(_shown(tester), 0);

      unawaited(h.always.set(true));
      await _Harness.settle(tester);
      expect(_shown(tester), 1);

      // And it stays through a scroll that ends.
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await _Harness.settle(tester);
      expect(_shown(tester), 1);
      expect(tester.takeException(), isNull);
    }, variant: _desktop);

    testWidgets('a list too short to scroll draws no thumb', (tester) async {
      final h = _Harness();
      unawaited(h.always.set(true));
      await h.pump(tester, _rows(3));
      expect(
        find.byType(InScrollbar),
        isNot(paints..rrect(color: InTheme.light.ink3)),
      );
      expect(tester.takeException(), isNull);
    }, variant: _desktop);

    testWidgets('a hand-placed bar over a scroll view that arrives later '
        'pins once it has attached', (tester) async {
      final h = _Harness();
      unawaited(h.always.set(true));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final ready = ValueNotifier(false);
      await h.pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (context, isReady, _) => InScrollbar(
            controller: controller,
            child: isReady
                ? SingleChildScrollView(
                    controller: controller,
                    child: const SizedBox(height: 2000),
                  )
                : const SizedBox.expand(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      ready.value = true;
      await _Harness.settle(tester);
      expect(tester.takeException(), isNull);
      // The hand-placed bar, plus the scroll view's own.
      expect(_shown(tester), 2);
    }, variant: _desktop);
  });

  // The classic failure. Each tree below is one the app can build; each makes
  // a theme-level `thumbVisibility: true` assert, and none may make the app's
  // pin assert.
  group('the pin cannot assert where a theme-level thumbVisibility does', () {
    Widget shared(ScrollController controller) => Row(
      children: [
        Expanded(child: _rows(50, controller: controller)),
        Expanded(child: _rows(50, controller: controller)),
      ],
    );

    Widget inheritedPrimary(ScrollController controller) =>
        PrimaryScrollController(
          controller: controller,
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: Row(
            children: [
              Expanded(child: _rows(50)),
              Expanded(child: _rows(50)),
            ],
          ),
        );

    final trees = <String, Widget Function(ScrollController)>{
      'two scroll views on one controller': shared,
      'two scroll views inheriting one PrimaryScrollController':
          inheritedPrimary,
    };

    for (final MapEntry(key: label, value: tree) in trees.entries) {
      testWidgets('control — theme-level thumbVisibility asserts on $label', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                scrollbarTheme: const ScrollbarThemeData(
                  thumbVisibility: WidgetStatePropertyAll(true),
                ),
              ),
              home: Scaffold(body: tree(controller)),
            ),
          );
          await _Harness.settle(tester);
        } finally {
          FlutterError.onError = previous;
        }
        expect(
          errors.map((e) => e.exceptionAsString()).join('\n'),
          contains('more than one ScrollPosition'),
        );
      }, variant: _desktop);

      testWidgets('the pin on $label: no exception, through a scroll, a '
          'theme change and the switch', (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final h = _Harness();
        unawaited(h.always.set(true));
        await h.pump(tester, tree(controller));
        expect(tester.takeException(), isNull);
        // Neither is pinned: neither controller has one position.
        expect(_shown(tester), 0);

        // A Material bar asserts here too, through its interactive path,
        // the moment either list is scrolled; this one is passive instead.
        await tester.drag(find.byType(ListView).first, const Offset(0, -60));
        await _Harness.settle(tester);
        expect(tester.takeException(), isNull, reason: 'a scroll');
        h.dark.value = true;
        await _Harness.settle(tester);
        unawaited(h.always.set(false));
        await _Harness.settle(tester);
        unawaited(h.always.set(true));
        await _Harness.settle(tester);
        expect(tester.takeException(), isNull);
      }, variant: _desktop);
    }

    testWidgets('a pinned bar whose scroll view leaves in the same frame as '
        'a theme change', (tester) async {
      // RawScrollbar checks a frame after any dependency change that the
      // controller still has one position; by then this one has none.
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final h = _Harness();
      unawaited(h.always.set(true));
      final present = ValueNotifier(true);
      await h.pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: present,
          builder: (context, isPresent, _) => InScrollbar(
            controller: controller,
            child: isPresent
                ? SingleChildScrollView(
                    controller: controller,
                    child: const SizedBox(height: 2000),
                  )
                : const SizedBox.expand(),
          ),
        ),
      );
      expect(_shown(tester), 2);
      present.value = false;
      h.dark.value = true;
      await _Harness.settle(tester);
      expect(tester.takeException(), isNull);
    }, variant: _desktop);
  });

  testWidgets('on a touch platform a hand-placed InScrollbar is Material\'s '
      'Scrollbar, and ignores the switch', (tester) async {
    final h = _Harness();
    unawaited(h.always.set(true));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await h.pump(
      tester,
      InScrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          child: const SizedBox(height: 2000),
        ),
      ),
    );
    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isNull);
    expect(bar.controller, controller);
    expect(_shown(tester), 0);
  });
}
