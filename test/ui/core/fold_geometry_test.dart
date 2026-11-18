// `lib/ui/core/fold_geometry.dart`: which display features split the window,
// and how book posture is debounced. docs/foldables.md.

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:admin/ui/core/fold_geometry.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _window = Size(951, 669);

MediaQueryData _mq(List<DisplayFeature> features, {Size size = _window}) =>
    MediaQueryData(size: size, displayFeatures: features);

DisplayFeature _feature(
  Rect bounds, {
  DisplayFeatureType type = DisplayFeatureType.fold,
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
}) => DisplayFeature(bounds: bounds, type: type, state: state);

/// The iPhone Duo's division: 40 pt down the middle of the inner display.
final _duoFold = _feature(const Rect.fromLTWH(455, 0, 40, 669));

void main() {
  group('separatingFold', () {
    test('a half-open vertical fold splits left and right', () {
      final split = separatingFold(_mq([_duoFold]))!;
      expect(split.axis, FoldAxis.vertical);
      expect(split.start, const Rect.fromLTRB(0, 0, 455, 669));
      expect(split.end, const Rect.fromLTRB(495, 0, 951, 669));
    });

    test('a zero-width half-open fold (most Android) still splits', () {
      final split = separatingFold(
        _mq([_feature(const Rect.fromLTWH(475, 0, 0, 669))]),
      );
      expect(split?.axis, FoldAxis.vertical);
    });

    test('a flat zero-width fold does not — nothing to avoid', () {
      expect(
        separatingFold(
          _mq([
            _feature(
              const Rect.fromLTWH(475, 0, 0, 669),
              state: DisplayFeatureState.postureFlat,
            ),
          ]),
        ),
        isNull,
      );
    });

    test('a hinge with area splits even when flat', () {
      final split = separatingFold(
        _mq([
          _feature(
            const Rect.fromLTWH(455, 0, 40, 669),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ]),
      );
      expect(split?.axis, FoldAxis.vertical);
    });

    test('a horizontal fold is tabletop', () {
      final split = separatingFold(
        _mq([
          _feature(const Rect.fromLTWH(0, 455, 669, 40)),
        ], size: const Size(669, 951)),
      )!;
      expect(split.axis, FoldAxis.horizontal);
      expect(split.start.bottom, 455);
      expect(split.end.top, 495);
    });

    test('a camera cutout splits nothing', () {
      expect(
        separatingFold(
          _mq([
            _feature(
              const Rect.fromLTWH(10, 10, 30, 30),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
          ]),
        ),
        isNull,
      );
    });

    test('a fold that does not span the window splits nothing', () {
      expect(
        separatingFold(_mq([_feature(const Rect.fromLTWH(455, 0, 40, 300))])),
        isNull,
      );
    });
  });

  test('rebaseDisplayFeatures shifts the features, never the size', () {
    final rebased = rebaseDisplayFeatures(_mq([_duoFold]), -64);
    expect(rebased.size, _window);
    expect(
      rebased.displayFeatures.single.bounds,
      const Rect.fromLTWH(391, 0, 40, 669),
    );
    expect(rebased.displayFeatures.single.state, _duoFold.state);
  });

  // The shell's content starts past the rail while the fold is in window
  // coordinates. A sheet's DisplayFeatureSubScreen on a nested navigator
  // measures from that navigator's origin: without the re-base a sheet
  // anchored after the fold started 64 px past it (559, not 495) — and the
  // master-detail split, which reads the same coordinates, would have put the
  // list across the fold.
  group('a sheet on a navigator beside the rail', () {
    Future<Rect> sheetRect(
      WidgetTester tester, {
      required bool rebase,
      Offset? anchor,
    }) async {
      tester.view.physicalSize = _window;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(displayFeatures: [_duoFold]),
            child: inner!,
          ),
          home: Builder(
            builder: (context) => Stack(
              children: [
                PositionedDirectional(
                  start: 64,
                  top: 0,
                  end: 0,
                  bottom: 0,
                  child: MediaQuery(
                    data: rebase
                        ? rebaseDisplayFeatures(MediaQuery.of(context), -64)
                        : MediaQuery.of(context),
                    child: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (context) => Scaffold(
                          body: TextButton(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              anchorPoint: anchor,
                              builder: (_) => const SizedBox(height: 120),
                            ),
                            child: const Text('open'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.getRect(find.byType(BottomSheet));
    }

    testWidgets('re-based, it stays before the fold', (tester) async {
      final rect = await sheetRect(tester, rebase: true);
      expect(rect.left, greaterThanOrEqualTo(64));
      expect(rect.right, lessThanOrEqualTo(455));
    });

    testWidgets('re-based, one anchored after the fold starts at it', (
      tester,
    ) async {
      final rect = await sheetRect(
        tester,
        rebase: true,
        anchor: const Offset(700, 300),
      );
      expect(rect.left, 495);
      expect(rect.right, 951);
    });

    testWidgets('without the re-base it starts 64 px past the fold', (
      tester,
    ) async {
      final rect = await sheetRect(
        tester,
        rebase: false,
        anchor: const Offset(700, 300),
      );
      expect(rect.left, 559);
    });
  });

  // Anchored even with no fold: Material re-picks the sub-screen whenever the
  // features change, so a dialog opened flat would jump to the start half the
  // moment the device half-opened, with no anchor to stay by.
  testWidgets('foldAnchorPoint anchors with no fold present', (tester) async {
    Offset? anchor;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => anchor = foldAnchorPoint(context),
              child: const Text('tap'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    expect(anchor, tester.getCenter(find.byType(TextButton)));
  });

  group('FoldPostureHost', () {
    late ValueNotifier<List<DisplayFeature>> features;
    late List<bool> changes;

    Future<void> pump(WidgetTester tester) async {
      features = ValueNotifier(const []);
      addTearDown(features.dispose);
      changes = [];
      await tester.pumpWidget(
        ValueListenableBuilder<List<DisplayFeature>>(
          valueListenable: features,
          builder: (_, f, _) => MediaQuery(
            data: _mq(f),
            child: FoldPostureHost(
              onChanged: changes.add,
              child: Builder(
                builder: (context) => Text(
                  FoldPostureScope.bookPostureOf(context) ? 'BOOK' : 'FLAT',
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('enters book posture only once the fold has settled', (
      tester,
    ) async {
      await pump(tester);
      features.value = [_duoFold];
      await tester.pump();
      expect(find.text('FLAT'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('FLAT'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('BOOK'), findsOneWidget);
      expect(changes, [true]);
    });

    testWidgets('passing through half-open on the way to flat never enters', (
      tester,
    ) async {
      await pump(tester);
      features.value = [_duoFold];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      features.value = const [];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('FLAT'), findsOneWidget);
      expect(changes, isEmpty);
    });

    testWidgets('leaves at once when the fold goes', (tester) async {
      await pump(tester);
      features.value = [_duoFold];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('BOOK'), findsOneWidget);
      features.value = const [];
      await tester.pump();
      expect(find.text('FLAT'), findsOneWidget);
      await tester.pump();
      expect(changes, [true, false]);
    });

    // A sign-out disposes the shell; left set, the next session's rail stayed
    // collapsed against the preference.
    testWidgets('going away mid-posture reports it is over', (tester) async {
      await pump(tester);
      features.value = [_duoFold];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(changes, [true]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(changes, [true, false]);
    });

    testWidgets('bookFoldOf needs the debounce and a live fold', (
      tester,
    ) async {
      FoldSplit? seen;
      await tester.pumpWidget(
        MediaQuery(
          data: _mq([_duoFold]),
          child: FoldPostureHost(
            child: Builder(
              builder: (context) {
                seen = bookFoldOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen, isNull, reason: 'not settled yet');
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen?.start.right, 455);
    });
  });
}
