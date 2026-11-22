import 'package:flutter/foundation.dart';

import 'package:admin/app/env.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/mobile_app_promo.dart';
import 'package:admin/domain/web_app_banner.dart';

/// The "get the desktop app" promo's pure rules — the mobile-app promo's
/// reverse, shown on native iOS, iPadOS and Android (docs/desktop-app-promo.md).
/// Which computers to offer, and to whom, is decided here, where a unit test
/// pins it; the schedule is the mobile-app promo's
/// (`MobileAppPromoController`, under its own preference key).

/// Off switch for the whole desktop promo: the automatic open and the About,
/// Device Settings and Integrations entries.
const bool kDesktopPromoEnabled = true;

/// A computer the desktop app installs on.
enum DesktopPromoTarget {
  windows,
  mac,
  linux;

  /// The web banner's platform, whose download page this target shares
  /// ([nativeAppUrl]), so the launch switch that sets those links sets these.
  NativeAppPlatform get platform => switch (this) {
    DesktopPromoTarget.windows => NativeAppPlatform.windows,
    DesktopPromoTarget.mac => NativeAppPlatform.mac,
    DesktopPromoTarget.linux => NativeAppPlatform.linux,
  };

  /// The platform's own name. Brand names read the same in every locale.
  String get displayName => switch (this) {
    DesktopPromoTarget.windows => 'Windows',
    DesktopPromoTarget.mac => 'Mac',
    DesktopPromoTarget.linux => 'Linux',
  };
}

/// Where a native app is downloaded, or null with no public listing yet —
/// [nativeAppUrl] in the app, a fake in a test.
typedef DesktopAppUrlOf = String? Function(NativeAppPlatform platform);

/// The computers this surface may offer, in display order.
///
/// - **Native iOS and iPadOS: the Mac only.** An App Store build may not show
///   "names, icons, or imagery of other mobile platforms or alternative app
///   marketplaces" (App Review Guideline 2.3.10). Windows and Linux are not
///   mobile platforms, but each installs from a third-party store (Microsoft
///   Store, Flathub, Snap Store) whose name is the link we would hand out,
///   and no neutral download page is live yet — so the Apple builds stay on
///   the one computer Apple's own store serves (docs/desktop-app-promo.md
///   § Store-policy review).
/// - **Native Android (Google Play and F-Droid): Windows, Mac and Linux.**
/// - **Everything else: nothing.** A computer and the web already run this
///   app on a big screen; the web's own banner offers the native app
///   (`WebAppBanner`).
///
/// A target whose download page [urlOf] doesn't know yet is left out: today
/// that is Windows, until the Microsoft Store listing's audience is Public
/// (`kWindowsAppUrl`, the launch switch).
List<DesktopPromoTarget> desktopPromoTargets({
  required bool isWeb,
  required TargetPlatform platform,
  DesktopAppUrlOf urlOf = nativeAppUrl,
}) {
  if (isWeb) return const [];
  final offered = switch (platform) {
    TargetPlatform.iOS => const [DesktopPromoTarget.mac],
    TargetPlatform.android => DesktopPromoTarget.values,
    _ => const <DesktopPromoTarget>[],
  };
  return [
    for (final t in offered)
      if (urlOf(t.platform) != null) t,
  ];
}

/// The live surface's targets — [desktopPromoTargets] for this build.
List<DesktopPromoTarget> currentDesktopPromoTargets() =>
    desktopPromoTargets(isWeb: kIsWeb, platform: defaultTargetPlatform);

/// [target]'s download page. Only ever called for a target
/// [desktopPromoTargets] offered, which checked it has one.
String desktopPromoUrl(
  DesktopPromoTarget target, {
  DesktopAppUrlOf urlOf = nativeAppUrl,
}) => urlOf(target.platform) ?? '';

/// The caption under the link: what opening it on the computer does. The
/// Mac's follows the link itself, so the launch switch that moves it from
/// TestFlight to the App Store moves the caption too.
String desktopPromoStepKey(DesktopPromoTarget target, String url) =>
    switch (target) {
      DesktopPromoTarget.mac
          when Uri.tryParse(url)?.host == 'testflight.apple.com' =>
        'desktop_app_promo_mac_testflight_step',
      DesktopPromoTarget.mac => 'desktop_app_promo_mac_store_step',
      DesktopPromoTarget.windows => 'desktop_app_promo_windows_step',
      DesktopPromoTarget.linux => 'desktop_app_promo_linux_step',
    };

/// Whether this session may be offered the desktop app: a live, non-demo
/// session whose server another machine could reach — the mobile-app
/// promo's rule ([mobilePromoEligible]) under its own switch. A `localhost`
/// server here is an emulator's or a dev machine's, never one a computer
/// down the hall can sign in to.
bool desktopPromoEligible(
  AuthSession? session, {
  bool isDemoBuild = Env.isDemoBuild,
  bool demoMode = Env.demoMode,
}) {
  if (!kDesktopPromoEnabled || session == null) return false;
  if (isDemoBuild || demoMode || session.isDemo) return false;
  return !isLoopbackHost(session.baseUrl);
}

/// Which of the two promos this build runs: the phone app on a computer or
/// the web, the desktop app on a phone. Never both — their surfaces are
/// disjoint, which is why the two can share one schedule controller.
enum AppPromoKind { mobile, desktop }

/// The promo [session] may be offered on this build, or null for none.
AppPromoKind? currentAppPromoKind(AuthSession? session) {
  if (currentMobilePromoTargets().isNotEmpty) {
    return mobilePromoEligible(session) ? AppPromoKind.mobile : null;
  }
  if (currentDesktopPromoTargets().isNotEmpty) {
    return desktopPromoEligible(session) ? AppPromoKind.desktop : null;
  }
  return null;
}
