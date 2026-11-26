import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/views/advanced/invoice_design/widgets/design_code_field.dart';

import '../../../../_localization_helper.dart';

// invoiceninja/app#212: on web a right-click opened the browser's own menu,
// whose Copy read re_editor's hidden one-line input, so copying a multi-line
// selection gave a fragment of its first line. The editor now has its own
// menu, and its Copy goes through the editing controller.
void main() {
  const template = '<style>\n  body { color: red; }\n</style>';

  testWidgets('right-click Copy puts the whole selection on the clipboard', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    late CodeLineEditingController controller;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: DesignCodeField(
              initial: template,
              seedRevision: 0,
              isTemplate: false,
              onChanged: (_) {},
              insertController: (c) => controller = c,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.selectAll();
    await tester.pump();

    await tester.tapAt(
      tester.getCenter(find.byType(CodeEditor)),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, [template]);
  });
}
