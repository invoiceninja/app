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
        nativeUrl: kMacAppUrl,
      ),
      TargetPlatform.windows: const WebAppBannerLinks(
        webAppUrl: kHostedReactUrl,
        nativePlatform: NativeAppPlatform.windows,
        nativeUrl: kWindowsAppUrl,
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
        nativeUrl: kMacAppUrl,
      ),
      TargetPlatform.windows: const WebAppBannerLinks(
        nativePlatform: NativeAppPlatform.windows,
        nativeUrl: kWindowsAppUrl,
      ),
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

  test('a white-labeled self-hosted install gets no banner', () {
    for (final platform in TargetPlatform.values) {
      expect(
        webAppBannerLinks(
          platform: platform,
          isHosted: false,
          whiteLabeled: true,
        ).isEmpty,
        isTrue,
        reason: platform.name,
      );
    }
    // A hosted white_label plan is not a white-labeled install.
    expect(
      webAppBannerLinks(
        platform: TargetPlatform.android,
        isHosted: true,
        whiteLabeled: true,
      ).isEmpty,
      isFalse,
    );
  });

  test('nothing to offer is empty, so no banner', () {
    expect(
      webAppBannerLinks(platform: TargetPlatform.fuchsia, isHosted: false),
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

  group('a Chromebook reports Linux but gets the Android app', () {
    const chromebook =
        'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    const linux =
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

    test('hosted and self-hosted', () {
      expect(
        webAppBannerLinks(
          platform: TargetPlatform.linux,
          isHosted: true,
          userAgent: chromebook,
        ),
        const WebAppBannerLinks(
          webAppUrl: kHostedReactUrl,
          nativePlatform: NativeAppPlatform.android,
          nativeUrl: kMobileAppAndroidUrl,
        ),
      );
      expect(
        webAppBannerLinks(
          platform: TargetPlatform.linux,
          isHosted: false,
          userAgent: chromebook,
        ),
        const WebAppBannerLinks(
          nativePlatform: NativeAppPlatform.android,
          nativeUrl: kMobileAppAndroidUrl,
        ),
      );
    });

    test('a desktop Linux browser still gets Flathub', () {
      expect(
        nativeAppPlatformFor(TargetPlatform.linux, userAgent: linux),
        NativeAppPlatform.linux,
      );
      expect(
        nativeAppPlatformFor(TargetPlatform.linux),
        NativeAppPlatform.linux,
      );
    });

    test('only a Linux report is reinterpreted', () {
      expect(isChromeOsUserAgent(chromebook), isTrue);
      expect(isChromeOsUserAgent(linux), isFalse);
      expect(isChromeOsUserAgent(''), isFalse);
      expect(
        nativeAppPlatformFor(TargetPlatform.windows, userAgent: chromebook),
        NativeAppPlatform.windows,
      );
    });
  });

  test('the Mac and Windows links are invoiceninja.com download pages', () {
    expect(kMacAppUrl, 'https://invoiceninja.com/apps/mac/');
    expect(kWindowsAppUrl, 'https://invoiceninja.com/apps/windows/');
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
