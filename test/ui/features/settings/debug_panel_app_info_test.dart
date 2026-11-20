import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:admin/app/debug_capture_store.dart';
import 'package:admin/app/screenshot_window_controller.dart';
import 'package:admin/app/version.dart';
import 'package:admin/ui/features/settings/views/advanced/debug_panel_app_info.dart';
import 'package:admin/ui/features/settings/views/advanced/debug_panel_section.dart';

import '../../../_responsive_helper.dart';

/// The Debug Panel's App info tab. Reading the clipboard back hangs in a
/// widget test (fake-async), so Copy all is checked by intercepting the
/// `Clipboard.setData` call, as `copyable_value_test` does.
void main() {
  String? copied;

  setUp(() {
    copied = null;
    PackageInfo.setMockInitialValues(
      appName: 'Invoice Ninja',
      packageName: 'com.invoiceninja.admin',
      version: AppVersion.kClientVersion,
      buildNumber: '34',
      buildSignature: '',
    );
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

  testWidgets('renders the rows and Copy all copies them as lines', (
    tester,
  ) async {
    await pumpAt(
      tester,
      800,
      const SizedBox(height: 1200, child: DebugAppInfoTab()),
      height: 1300,
      scroll: false,
    );
    await tester.pump();

    expect(find.text('App info'), findsOneWidget);
    expect(find.text('App Version'), findsOneWidget);
    expect(find.text(AppVersion.kClientVersion), findsOneWidget);
    expect(find.text('Build number'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);
    // `flutter test` runs on the Android platform by default.
    expect(find.text('Android'), findsOneWidget);
    // `setSurfaceSize` leaves `MediaQuery` where the view put it, so the
    // expected size is read back rather than assumed.
    final size = MediaQuery.sizeOf(
      tester.element(find.byType(DebugAppInfoTab)),
    );
    final sizeText = '${size.width.round()} × ${size.height.round()}';
    expect(find.text(sizeText), findsOneWidget);
    // No session (no Services): no server rows.
    expect(find.text('Server version'), findsNothing);
    expectNoOverflow(tester);

    await tester.tap(find.text('Copy all'));
    await tester.pump();

    final lines = copied!.split('\n');
    expect(lines.take(4), [
      'App Version: ${AppVersion.kClientVersion}',
      'Build number: 34',
      'Build mode: debug',
      'Beta: ${kAppIsBeta ? 'Yes' : 'No'}',
    ]);
    expect(lines, contains('Platform: Android'));
    expect(lines, contains('Screen size: $sizeText'));
    expect(lines, contains('Text direction: LTR'));
    expect(lines, contains('Theme: Light'));
    expect(lines, contains('Display features: None'));
    // One line per rendered row: every label is on screen.
    for (final line in lines) {
      final label = line.substring(0, line.indexOf(': '));
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('no overflow on a phone-width band', (tester) async {
    for (final width in [320.0, 390.0]) {
      await pumpAt(
        tester,
        width,
        const SizedBox(height: 1600, child: DebugAppInfoTab()),
        height: 1700,
        scroll: false,
      );
      await tester.pump();
      expectNoOverflow(tester);
      expect(find.text('Copy all'), findsOneWidget);
    }
  });

  testWidgets('the panel has an App info tab', (tester) async {
    await pumpAt(
      tester,
      800,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: 480,
          child: DebugPanelSection(
            store: DebugCaptureStore(),
            windowController: ScreenshotWindowController(),
            onHide: () {},
          ),
        ),
      ),
      scroll: false,
    );
    await tester.tap(find.widgetWithText(Tab, 'App info'));
    await tester.pumpAndSettle();
    expect(find.byType(DebugAppInfoTab), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
  });
}
