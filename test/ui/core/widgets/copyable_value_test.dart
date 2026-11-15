import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';

/// `CopyableValue` copies via the platform clipboard channel. Reading the
/// clipboard back hangs in a widget test (fake-async), so these tests intercept
/// the `Clipboard.setData` method-channel call and assert what was written.
void main() {
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

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('empty value renders the child with no copy affordance', (
    tester,
  ) async {
    await pump(tester, const CopyableValue(value: '', child: Text('x')));

    expect(find.text('x'), findsOneWidget);
    expect(find.byType(CopyIconButton), findsNothing);
  });

  testWidgets('mobile: tapping the value copies it, no hover icon', (
    tester,
  ) async {
    // Reset inside the body (not addTearDown): the foundation-vars invariant
    // check runs before teardowns, so a lingering override fails the test.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(
        tester,
        const CopyableValue(value: 'VAT-123', child: Text('VAT-123')),
      );

      // No persistent copy icon on touch — the value itself is the target.
      expect(find.byType(CopyIconButton), findsNothing);

      await tester.tap(find.text('VAT-123'));
      await tester.pumpAndSettle();

      expect(copied, 'VAT-123');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop: hover reveals the copy icon and clicking it copies', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pump(
        tester,
        const CopyableValue(value: 'GB42', child: Text('GB42')),
      );

      // Tapping the value does nothing on desktop — copy is via the icon only.
      await tester.tap(find.text('GB42'));
      await tester.pumpAndSettle();
      expect(copied, isNull);

      // Hover the value to reveal the (otherwise pointer-ignoring) icon.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('GB42')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CopyIconButton));
      await tester.pumpAndSettle();

      expect(copied, 'GB42');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('floatIcon', () {
    testWidgets('desktop: reserves no space at rest, and the icon appears '
        'beside the value on hover', (tester) async {
      // An inline value with something after it on its line (a document
      // number followed by its status pill): the reserved slot would be a
      // 30 px hole between the two.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(
          tester,
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CopyableValue(
                value: '0042',
                fillWidth: false,
                floatIcon: true,
                child: Text('#0042'),
              ),
              Text('NEXT'),
            ],
          ),
        );

        expect(find.byType(CopyIconButton), findsNothing);
        expect(
          tester.getTopLeft(find.text('NEXT')).dx,
          tester.getTopRight(find.text('#0042')).dx,
          reason: 'the neighbour sits flush against the value',
        );

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture.moveTo(tester.getCenter(find.text('#0042')));
        await tester.pumpAndSettle();

        expect(find.byType(CopyIconButton), findsOneWidget);
        // Just past the value's trailing edge, on its centre line.
        final value = tester.getRect(find.text('#0042'));
        final icon = tester.getRect(find.byType(CopyIconButton));
        expect(icon.left, value.right + 4);
        expect(icon.center.dy, moreOrLessEquals(value.center.dy));

        // The pointer can travel from the value to the icon and click it.
        await gesture.moveTo(icon.center);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CopyIconButton), findsOneWidget);
        await tester.tap(find.byType(CopyIconButton));
        await tester.pumpAndSettle();
        expect(copied, '0042');

        // …and it goes once the pointer has left both.
        await gesture.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(CopyIconButton), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('desktop: the keyboard reaches it — Tab shows the icon and '
        'Enter copies', (tester) async {
      // The icon is not in the tree until it shows, so it cannot be the tab
      // stop; the value is.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(
          tester,
          const CopyableValue(
            value: '0042',
            fillWidth: false,
            floatIcon: true,
            child: Text('#0042'),
          ),
        );
        expect(find.byType(CopyIconButton), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(find.byType(CopyIconButton), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(copied, '0042');

        // A screen reader gets a Copy action on the value itself.
        expect(
          tester
              .getSemantics(find.text('#0042'))
              .getSemanticsData()
              .hasAction(SemanticsAction.copy),
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('touch: unchanged — a link-bearing value copies on '
        'long-press and keeps its own tap', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        var opened = 0;
        await pump(
          tester,
          CopyableValue(
            value: 'Acme Corp',
            fillWidth: false,
            floatIcon: true,
            enableTapToCopy: false,
            enableLongPressToCopy: true,
            child: GestureDetector(
              onTap: () => opened++,
              child: const Text('Acme Corp'),
            ),
          ),
        );

        await tester.tap(find.text('Acme Corp'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(copied, isNull);

        await tester.longPress(find.text('Acme Corp'));
        await tester.pumpAndSettle();
        expect(copied, 'Acme Corp');
        expect(find.byType(CopyIconButton), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
