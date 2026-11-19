import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/theme.dart';
import 'package:admin/domain/mobile_app_promo.dart';
import 'package:admin/domain/web_app_banner.dart';

/// The web banner's links: every URL it can open, per browser OS and server
/// kind. The launch swap (docs/mobile-app-promo.md § Swap the links at
/// launch) changes the constants, never this table's shape.
void main() {
  const flathub = 'https://flathub.org/apps/com.invoiceninja.InvoiceNinja';

  group('hosted: Invoice Ninja Web plus the native app', () {
    final expected = <TargetPlatform, WebAppBannerLinks>{
      TargetPlatform.iOS: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
        nativePlatform: NativeAppPlatform.ios,
        nativeUrl: kMobileAppIosUrl,
      ),
      TargetPlatform.android: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
        nativePlatform: NativeAppPlatform.android,
        nativeUrl: kMobileAppAndroidUrl,
      ),
      TargetPlatform.macOS: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
        nativePlatform: NativeAppPlatform.mac,
        nativeUrl: kMobileAppIosUrl,
      ),
      // No public Microsoft Store listing yet: the web app only.
      TargetPlatform.windows: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
      ),
      TargetPlatform.linux: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
        nativePlatform: NativeAppPlatform.linux,
        nativeUrl: flathub,
      ),
      TargetPlatform.fuchsia: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
      ),
    };
    for (final MapEntry(key: platform, value: links) in expected.entries) {
      test(platform.name, () {
        expect(webAppBannerLinks(platform: platform, isHosted: true), links);
      });
    }
  });

  group('self-hosted: the native app only', () {
    final expected = <TargetPlatform, WebAppBannerLinks>{
      TargetPlatform.iOS: const WebAppBannerLinks(
        nativePlatform: NativeAppPlatform.ios,
        nativeUrl: kMobileAppIosUrl,
      ),
      TargetPlatform.android: const WebAppBannerLinks(
        nativePlatform: NativeAppPlatform.android,
        nativeUrl: kMobileAppAndroidUrl,
      ),
      TargetPlatform.macOS: const WebAppBannerLinks(
        nativePlatform: NativeAppPlatform.mac,
        nativeUrl: kMobileAppIosUrl,
      ),
      TargetPlatform.windows: const WebAppBannerLinks(),
      TargetPlatform.linux: const WebAppBannerLinks(
        nativePlatform: NativeAppPlatform.linux,
        nativeUrl: flathub,
      ),
      TargetPlatform.fuchsia: const WebAppBannerLinks(),
    };
    for (final MapEntry(key: platform, value: links) in expected.entries) {
      test(platform.name, () {
        expect(webAppBannerLinks(platform: platform, isHosted: false), links);
      });
    }
  });

  test('nothing to offer is empty, so no banner', () {
    expect(
      webAppBannerLinks(platform: TargetPlatform.windows, isHosted: false),
      isA<WebAppBannerLinks>().having((l) => l.isEmpty, 'isEmpty', isTrue),
    );
    expect(
      webAppBannerLinks(
        platform: TargetPlatform.linux,
        isHosted: false,
      ).isEmpty,
      isFalse,
    );
  });

  test('the Windows link waits for the public Microsoft Store listing', () {
    // Flip this with `kWindowsAppUrl` at launch.
    expect(kWindowsAppUrl, isNull);
    expect(nativeAppUrl(NativeAppPlatform.windows), isNull);
  });

  test('every link is https', () {
    for (final platform in TargetPlatform.values) {
      for (final hosted in [true, false]) {
        final links = webAppBannerLinks(platform: platform, isHosted: hosted);
        for (final url in [links.webAppUrl, links.nativeUrl]) {
          if (url == null) continue;
          expect(Uri.parse(url).scheme, 'https', reason: '$platform $url');
        }
      }
    }
  });
}
