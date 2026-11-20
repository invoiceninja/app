import 'package:flutter/foundation.dart';

import 'package:admin/app/theme.dart';
import 'package:admin/domain/mobile_app_promo.dart';

/// The web build's "other apps" banner (`WebAppBanner`) — which apps it may
/// suggest, and where each one opens. The banner only draws this: every link
/// it can open is decided here, so the launch swap is one file
/// (docs/mobile-app-promo.md § Swap the links at launch).

/// Linux: Flathub, the store v1's Linux users already update from
/// (docs/flatpak.md). Public since 5.1.23.
const String kLinuxAppUrl =
    'https://flathub.org/apps/com.invoiceninja.InvoiceNinja';

/// Windows: null until the Microsoft Store listing's audience is Public — a
/// Private-audience listing tells everyone else the app isn't available. Set
/// it to `'https://apps.microsoft.com/detail/$kMicrosoftStoreId'` at launch
/// (docs/mobile-app-promo.md § Swap the links at launch).
const String? kWindowsAppUrl = null;

/// The native app the banner offers on the browser's operating system.
enum NativeAppPlatform {
  /// iPhone and iPad — an iPad's browser reports iOS too.
  ios,
  android,
  mac,
  windows,
  linux,
}

/// What the banner offers: Invoice Ninja Web (React), the native app for this
/// operating system, both, or — when [isEmpty] — nothing, and no banner.
@immutable
class WebAppBannerLinks {
  const WebAppBannerLinks({this.webAppUrl, this.nativePlatform, this.nativeUrl})
    : assert((nativePlatform == null) == (nativeUrl == null));

  /// Invoice Ninja Web, or null where it can't be reached.
  final String? webAppUrl;

  /// The native app's platform and its download page, both null or neither.
  final NativeAppPlatform? nativePlatform;
  final String? nativeUrl;

  bool get isEmpty => webAppUrl == null && nativeUrl == null;

  @override
  bool operator ==(Object other) =>
      other is WebAppBannerLinks &&
      other.webAppUrl == webAppUrl &&
      other.nativePlatform == nativePlatform &&
      other.nativeUrl == nativeUrl;

  @override
  int get hashCode => Object.hash(webAppUrl, nativePlatform, nativeUrl);

  @override
  String toString() =>
      'WebAppBannerLinks(web: $webAppUrl, $nativePlatform: $nativeUrl)';
}

/// The native app for a browser reporting [platform] (on the web,
/// `defaultTargetPlatform` is the browser's operating system).
NativeAppPlatform? nativeAppPlatformFor(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS => NativeAppPlatform.ios,
      TargetPlatform.android => NativeAppPlatform.android,
      TargetPlatform.macOS => NativeAppPlatform.mac,
      TargetPlatform.windows => NativeAppPlatform.windows,
      TargetPlatform.linux => NativeAppPlatform.linux,
      TargetPlatform.fuchsia => null,
    };

/// Where [platform]'s native app is downloaded, or null where there is no
/// public listing yet. The Mac app is the iPhone app's TestFlight beta today
/// (one App Store record serves both), so it follows [kMobileAppIosUrl].
String? nativeAppUrl(NativeAppPlatform platform) => switch (platform) {
  NativeAppPlatform.ios => kMobileAppIosUrl,
  NativeAppPlatform.android => kMobileAppAndroidUrl,
  NativeAppPlatform.mac => kMobileAppIosUrl,
  NativeAppPlatform.windows => kWindowsAppUrl,
  NativeAppPlatform.linux => kLinuxAppUrl,
};

/// The banner's links for a browser on [platform] signed in to a hosted
/// ([isHosted]) or self-hosted server.
///
/// Invoice Ninja Web is offered on hosted only. A self-hosted server serves
/// React at its root only when the account has made React its default
/// (`set_react_as_default_ap`), and then it never serves this app — so from
/// here there is no React URL to send anyone to, and switching an account's
/// default is not a banner's call.
///
/// A white-labeled self-hosted install ([whiteLabeled],
/// `AuthSession.isWhiteLabeledSelfHost`) shows nothing of Invoice Ninja's
/// own, so it gets no banner at all.
WebAppBannerLinks webAppBannerLinks({
  required TargetPlatform platform,
  required bool isHosted,
  bool whiteLabeled = false,
}) {
  if (whiteLabeled && !isHosted) return const WebAppBannerLinks();
  final native = nativeAppPlatformFor(platform);
  final url = native == null ? null : nativeAppUrl(native);
  return WebAppBannerLinks(
    webAppUrl: isHosted ? kHostedReactUrl : null,
    nativePlatform: url == null ? null : native,
    nativeUrl: url,
  );
}
