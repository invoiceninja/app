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

/// Mac: invoiceninja.com's download page for the Mac App Store listing (one App
/// Store record serves the iPhone, iPad and Mac apps, but the Mac one opens on
/// its own platform page).
const String kMacAppUrl = 'https://invoiceninja.com/apps/mac/';

/// Windows: invoiceninja.com's download page for the Microsoft Store listing
/// (`9NG93WNXN797`, public since the launch release).
const String kWindowsAppUrl = 'https://invoiceninja.com/apps/windows/';

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
/// `defaultTargetPlatform` is the browser's operating system) and
/// [userAgent].
///
/// A Chromebook reports Linux, but it runs Android apps from Google Play and
/// a Flatpak only inside the opt-in Linux container, so a `CrOS` user agent
/// (`Mozilla/5.0 (X11; CrOS x86_64 …)`) is offered the Android app.
NativeAppPlatform? nativeAppPlatformFor(
  TargetPlatform platform, {
  String userAgent = '',
}) => switch (platform) {
  TargetPlatform.iOS => NativeAppPlatform.ios,
  TargetPlatform.android => NativeAppPlatform.android,
  TargetPlatform.macOS => NativeAppPlatform.mac,
  TargetPlatform.windows => NativeAppPlatform.windows,
  TargetPlatform.linux when isChromeOsUserAgent(userAgent) =>
    NativeAppPlatform.android,
  TargetPlatform.linux => NativeAppPlatform.linux,
  TargetPlatform.fuchsia => null,
};

/// Whether [userAgent] is a Chromebook's browser. Every ChromeOS browser —
/// Chrome, and the Lacros builds — carries the `CrOS` token.
bool isChromeOsUserAgent(String userAgent) => userAgent.contains('CrOS');

/// Where [platform]'s native app is downloaded, or null where there is no
/// public listing. Every platform has one since the launch release; the
/// nullable shape stays for a platform that loses or hasn't got its listing.
String? nativeAppUrl(NativeAppPlatform platform) => switch (platform) {
  NativeAppPlatform.ios => kMobileAppIosUrl,
  NativeAppPlatform.android => kMobileAppAndroidUrl,
  NativeAppPlatform.mac => kMacAppUrl,
  NativeAppPlatform.windows => kWindowsAppUrl,
  NativeAppPlatform.linux => kLinuxAppUrl,
};

/// The banner's links for a browser on [platform] (with [userAgent], which
/// tells a Chromebook from Linux) signed in to a hosted ([isHosted]) or
/// self-hosted server.
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
  String userAgent = '',
}) {
  if (whiteLabeled && !isHosted) return const WebAppBannerLinks();
  final native = nativeAppPlatformFor(platform, userAgent: userAgent);
  final url = native == null ? null : nativeAppUrl(native);
  return WebAppBannerLinks(
    webAppUrl: isHosted ? kHostedReactUrl : null,
    nativePlatform: url == null ? null : native,
    nativeUrl: url,
  );
}
