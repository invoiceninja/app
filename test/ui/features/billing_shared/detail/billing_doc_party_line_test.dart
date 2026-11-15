import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/widgets/cell_copy_hover.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/features/billing_shared/detail/billing_doc_record_header.dart';

/// The party name's copy icon used to float just past the name — which, with
/// tap-to-call on, is where the call button is. Hovering the name and moving
/// to the phone put the chip under the pointer, and the click copied instead
/// of dialling.
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

  /// A stand-in for a `copyable` name label: it reports the name it draws.
  Widget party() => Builder(
    builder: (context) {
      CellCopyNameScope.report(context, 'Acme Corp');
      return const Text('Acme Corp');
    },
  );

  Future<ValueNotifier<int>> pump(WidgetTester tester) async {
    final calls = ValueNotifier<int>(0);
    addTearDown(calls.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: Center(
            child: BillingDocPartyLine(
              party: party(),
              callButton: IconButton(
                key: const ValueKey('call'),
                icon: const Icon(Icons.phone),
                onPressed: () => calls.value++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('desktop: the copy icon sits after the call button, and the '
      'button still dials while the name is hovered', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final calls = await pump(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Acme Corp')));
      await tester.pumpAndSettle();

      final call = tester.getRect(find.byKey(const ValueKey('call')));
      final icon = tester.getRect(find.byType(CopyIconButton));
      expect(icon.left, greaterThanOrEqualTo(call.right));

      // From the name to the phone: nothing is in the way.
      await gesture.moveTo(call.center);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('call')));
      await tester.pumpAndSettle();
      expect(calls.value, 1);
      expect(copied, isNull);

      // …and the icon, at the end of the line, copies the name.
      await tester.tap(find.byType(CopyIconButton));
      await tester.pumpAndSettle();
      expect(copied, 'Acme Corp');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop: the slot is laid out at rest, so hover shifts '
      'nothing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pump(tester);
      final before = tester.getRect(find.byType(BillingDocPartyLine));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Acme Corp')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(BillingDocPartyLine)), before);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('touch: a plain row with no icon — the label copies on its '
      'own long-press', (tester) async {
    await pump(tester);
    expect(find.byType(CopyIconButton), findsNothing);
  });
}
