import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/spell_check_controller.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/ui/core/widgets/spell_check.dart';

/// Sentry FLUTTER-ADMIN-Y / -10 (flutter/flutter#196223, #191881): when the
/// runner's spell-check reply lands, `EditableTextState._performSpellCheck`
/// assigns `renderEditable.text` outside a frame. A mouse move over the field
/// before the next frame then hit tests a `TextPainter` with no layout, so
/// `NativeSpellCheckService` holds its reply until the next frame.
void main() {
  const channel = MethodChannel('invoice_ninja/spell_check');

  testWidgets('a hover between the spell-check reply and the next frame', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final reply = Completer<List<Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) => reply.future);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final controller = SpellCheckController(prefs: DevicePrefsStore(null));
    final service = NativeSpellCheckService();
    await tester.pumpWidget(
      ChangeNotifierProvider<SpellCheckController>.value(
        value: controller,
        child: MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 300,
                child: LineItemSpellCheck(
                  builder: (context, config) => TextField(
                    controller: TextEditingController(text: 'teh widget'),
                    spellCheckConfiguration: config == null
                        ? null
                        : SpellCheckConfiguration(spellCheckService: service),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The configuration arrives a frame after mount, which starts the check.
    await tester.pump();

    // The runner answers; the reply is applied outside a frame.
    reply.complete([
      {
        'start': 0,
        'end': 3,
        'suggestions': ['the'],
      },
    ]);
    await tester.idle();

    // The mouse moves over the field before the next frame.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(TextField)));

    expect(tester.takeException(), isNull);

    // The result is still applied — on the next frame.
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.spellCheckResults?.suggestionSpans, [
      const SuggestionSpan(TextRange(start: 0, end: 3), ['the']),
    ]);
  });
}
