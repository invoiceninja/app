import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tap to Pay on iPhone is signed into Debug builds only until Apple grants
/// the distribution entitlement (docs/in-person-payments.md): Debug signs with
/// `RunnerDebug.entitlements`, Release and Profile with `Runner.entitlements`,
/// which must not carry the key yet or every TestFlight upload fails. The app
/// learns which it is from the `IN_TAP_TO_PAY_ENTITLED` build setting
/// (Info.plist `INTapToPayEntitled`), so that setting has to say YES exactly
/// where the signing entitlements have the key — a YES without it offers Tap
/// to Pay that can't connect, a NO with it hides a working one.
void main() {
  const key = 'com.apple.developer.proximity-reader.payment.acceptance';
  final release = File('ios/Runner/Runner.entitlements').readAsStringSync();
  final debug = File('ios/Runner/RunnerDebug.entitlements').readAsStringSync();
  final project = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  /// The Runner target's build settings, by configuration name.
  Map<String, String> runnerConfigs() {
    final configs = <String, String>{};
    final block = RegExp(
      r'buildSettings = \{(.*?)\};\s*name = (\w+);',
      dotAll: true,
    );
    for (final m in block.allMatches(project)) {
      if (m
          .group(1)!
          .contains('PRODUCT_BUNDLE_IDENTIFIER = com.invoiceninja.admin;')) {
        configs[m.group(2)!] = m.group(1)!;
      }
    }
    return configs;
  }

  String withoutComments(String plist) =>
      plist.replaceAll(RegExp(r'\s*<!--.*?-->', dotAll: true), '');

  test('the Debug entitlements are the Release ones plus Tap to Pay', () {
    final tapToPay = RegExp('\\s*<key>${RegExp.escape(key)}</key>\\s*<true/>');
    expect(tapToPay.hasMatch(debug), isTrue);
    expect(
      withoutComments(debug).replaceAll(tapToPay, ''),
      withoutComments(release),
      reason: 'an entitlement added to one file must go in both',
    );
  });

  test('the build setting says YES exactly where the key is signed in', () {
    final configs = runnerConfigs();
    expect(configs.keys, containsAll(['Debug', 'Release', 'Profile']));
    for (final MapEntry(key: name, value: settings) in configs.entries) {
      final file = RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/(\w+)\.entitlements;',
      ).firstMatch(settings)?.group(1);
      final entitled = RegExp(
        r'IN_TAP_TO_PAY_ENTITLED = (YES|NO);',
      ).firstMatch(settings)?.group(1);
      expect(file, isNotNull, reason: name);
      expect(entitled, isNotNull, reason: name);
      final signed = File(
        'ios/Runner/$file.entitlements',
      ).readAsStringSync().contains('<key>$key</key>');
      expect(entitled == 'YES', signed, reason: '$name signs with $file');
    }
  });

  test('Release and Profile stay without it until distribution is granted', () {
    expect(release, isNot(contains(key)));
  });

  test('Info.plist hands the setting to the app', () {
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      matches(
        RegExp(
          r'<key>INTapToPayEntitled</key>\s*<string>\$\(IN_TAP_TO_PAY_ENTITLED\)</string>',
        ),
      ),
    );
  });
}
