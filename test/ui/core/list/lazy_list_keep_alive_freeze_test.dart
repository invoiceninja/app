// Sentry FLUTTER-ADMIN-1F: a hovered row whose Tooltip is showing, scrolled
// past the cache extent in one frame, is parked in the keep-alive bucket (the
// hovered InkWell asks to be kept alive). The tooltip's overlay box is never
// laid out but is still hit-tested, so every later mouse event throws and the
// app stops reacting to the mouse (flutter/flutter#193566). These pin the
// mechanism behind test/lint/lazy_list_keep_alives_test.dart;
// docs/lazy-list-keep-alives.md.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Hovers row 26 and, in the same frame, jumps to the top; then moves the
/// mouse. Returns the first error that raised, or null.
Future<Object?> _hoverThenJump(
  WidgetTester tester, {
  required bool keepAlives,
  double? extent,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
            child: ListView.builder(
              shrinkWrap: true,
              controller: controller,
              addAutomaticKeepAlives: keepAlives,
              itemExtent: extent,
              itemCount: 60,
              // A loose-height row with no relayout boundary inside, like a
              // card: the shape that is never laid out once parked.
              itemBuilder: (context, i) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Row $i',
                    child: IconButton(
                      key: ValueKey(i),
                      onPressed: () {},
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  controller.jumpTo(1200);
  await tester.pump();

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await tester.pump();

  // A broken tree throws on every pointer event and every frame after it, so
  // collect them all rather than leave several pending for the binding.
  final errors = <Object>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exception);
  try {
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey(26))));
    controller.jumpTo(0);
    await tester.pump();
    await mouse.moveBy(const Offset(0, 5));
    await tester.pump();
    // Unmount before the pointer goes: removing it hit-tests too.
    await tester.pumpWidget(const SizedBox());
    await mouse.removePointer();
    await tester.pump();
  } catch (e) {
    errors.add(e);
  } finally {
    // A failed device update leaves the debug mouse tracker asserting on
    // every later frame; start the next frame on a fresh one.
    tester.binding.initMouseTracker();
    FlutterError.onError = previous;
  }
  return errors.firstOrNull;
}

void main() {
  testWidgets(
    'with keep-alives on, the parked row breaks hit-testing (flutter#193566)',
    (tester) async {
      // When this starts passing clean, the framework bug is fixed: see
      // docs/upstream-workarounds.md for what to revert.
      final error = await _hoverThenJump(tester, keepAlives: true);
      expect(
        '$error',
        contains('Cannot hit test a render box that has never been laid out'),
      );
    },
    semanticsEnabled: false,
  );

  testWidgets('with keep-alives off, the row is disposed and the mouse works', (
    tester,
  ) async {
    expect(await _hoverThenJump(tester, keepAlives: false), isNull);
  }, semanticsEnabled: false);

  testWidgets('a fixed extent keeps the parked row laid out', (tester) async {
    expect(await _hoverThenJump(tester, keepAlives: true, extent: 48), isNull);
  }, semanticsEnabled: false);
}
