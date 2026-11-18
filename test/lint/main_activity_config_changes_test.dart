import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MainActivity must absorb every configuration change a foldable, a keyboard
/// or a desktop mode makes, or Android recreates it — restarting the Flutter
/// engine and losing whatever the user had not saved (docs/foldables.md).
/// Nothing in Dart can see this; it only shows on a device.
void main() {
  test('MainActivity handles fold, keyboard and DeX changes itself', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    final activity = RegExp(
      r'<activity[^>]*android:name="\.MainActivity"[^>]*>',
    ).firstMatch(manifest)?.group(0);
    expect(activity, isNotNull, reason: 'MainActivity is not declared');
    final changes = RegExp(
      r'android:configChanges="([^"]*)"',
    ).firstMatch(activity!)?.group(1)?.split('|').toSet();
    expect(
      changes,
      isNotNull,
      reason: 'MainActivity declares no configChanges',
    );
    expect(
      changes,
      containsAll(<String>[
        // A fold / unfold, rotation, a split-screen resize.
        'screenSize', 'smallestScreenSize', 'screenLayout', 'orientation',
        // A keyboard or mouse attached, a DeX switch.
        'keyboard', 'keyboardHidden', 'navigation', 'touchscreen',
        'density', 'uiMode', 'colorMode',
        'locale', 'layoutDirection', 'fontScale',
      ]),
    );
  });
}
