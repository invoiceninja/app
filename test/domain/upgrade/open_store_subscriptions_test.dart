import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/upgrade/upgrade_launcher.dart';

/// An IAP-billed plan is managed in the store. Apple's is always the web
/// subscriptions page, never StoreKit's in-app sheet: the sheet lists only
/// this app's subscriptions, so one bought in the Legacy app would be missing.
void main() {
  late List<Uri> launched;

  setUp(() => launched = []);

  Future<void> open(TargetPlatform platform) => openStoreSubscriptions(
    platform: platform,
    launch: (uri) async {
      launched.add(uri);
      return true;
    },
  );

  test('iOS opens the App Store subscriptions page', () async {
    await open(TargetPlatform.iOS);
    expect(launched, [
      Uri.parse('https://apps.apple.com/account/subscriptions'),
    ]);
  });

  test('macOS opens the same App Store page', () async {
    await open(TargetPlatform.macOS);
    expect(launched, [
      Uri.parse('https://apps.apple.com/account/subscriptions'),
    ]);
  });

  test('Android opens Play\'s page', () async {
    await open(TargetPlatform.android);
    expect(launched, [
      Uri.parse('https://play.google.com/store/account/subscriptions'),
    ]);
  });
}
