import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/desktop_app_promo.dart';
import 'package:admin/domain/web_app_banner.dart';

AuthSession _session({
  String baseUrl = 'https://invoicing.co',
  bool isHosted = true,
}) => AuthSession(
  baseUrl: baseUrl,
  isHosted: isHosted,
  accountId: 'acct',
  companies: [
    AuthCompany(
      id: 'co',
      name: 'Co',
      displayName: 'Co',
      permissions: '',
      isAdmin: true,
      isOwner: true,
      enabledModules: 0x7fffffff,
    ),
  ],
  currentCompanyId: 'co',
  userEmail: 'me@example.com',
);

/// Every platform with a public listing — the state after the launch switch.
String? _allListed(NativeAppPlatform p) => 'https://example.com/${p.name}';

/// The store-policy rules of the desktop-app promo live here, so they are
/// pinned here (docs/desktop-app-promo.md).
void main() {
  const windows = DesktopPromoTarget.windows;
  const mac = DesktopPromoTarget.mac;
  const linux = DesktopPromoTarget.linux;

  group('desktopPromoTargets', () {
    test('Apple builds offer the Mac and nothing else (guideline 2.3.10), '
        'even once every other computer has a listing', () {
      expect(
        desktopPromoTargets(
          isWeb: false,
          platform: TargetPlatform.iOS,
          urlOf: _allListed,
        ),
        [mac],
      );
    });

    test('Android offers every computer with a public listing', () {
      expect(
        desktopPromoTargets(
          isWeb: false,
          platform: TargetPlatform.android,
          urlOf: _allListed,
        ),
        [windows, mac, linux],
      );
    });

    test('a computer with no public listing yet is left out', () {
      String? noWindows(NativeAppPlatform p) =>
          p == NativeAppPlatform.windows ? null : _allListed(p);
      expect(
        desktopPromoTargets(
          isWeb: false,
          platform: TargetPlatform.android,
          urlOf: noWindows,
        ),
        [mac, linux],
      );
    });

    test('Windows follows the launch switch (kWindowsAppUrl)', () {
      final targets = desktopPromoTargets(
        isWeb: false,
        platform: TargetPlatform.android,
      );
      expect(
        targets.contains(windows),
        nativeAppUrl(NativeAppPlatform.windows) != null,
      );
      expect(targets, containsAll([mac, linux]));
    });

    test('a computer, the web and a phone browser are offered nothing', () {
      for (final platform in TargetPlatform.values) {
        expect(
          desktopPromoTargets(
            isWeb: true,
            platform: platform,
            urlOf: _allListed,
          ),
          isEmpty,
          reason: 'web on $platform',
        );
      }
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          desktopPromoTargets(
            isWeb: false,
            platform: platform,
            urlOf: _allListed,
          ),
          isEmpty,
          reason: '$platform',
        );
      }
    });

    test('each target opens the web banner\'s download page for it', () {
      expect(desktopPromoUrl(mac), nativeAppUrl(NativeAppPlatform.mac));
      expect(desktopPromoUrl(linux), kLinuxAppUrl);
      expect(desktopPromoUrl(linux), contains('flathub.org'));
    });
  });

  group('desktopPromoStepKey', () {
    test('the Mac caption follows the link: TestFlight until the launch '
        'switch, the App Store after', () {
      expect(
        desktopPromoStepKey(mac, 'https://testflight.apple.com/join/abc'),
        'desktop_app_promo_mac_testflight_step',
      );
      expect(
        desktopPromoStepKey(mac, 'https://invoiceninja.com/app/mac'),
        'desktop_app_promo_mac_store_step',
      );
    });

    test('Windows and Linux name their own stores', () {
      expect(
        desktopPromoStepKey(windows, 'x'),
        'desktop_app_promo_windows_step',
      );
      expect(desktopPromoStepKey(linux, 'x'), 'desktop_app_promo_linux_step');
    });
  });

  group('desktopPromoEligible', () {
    test('a hosted or reachable self-hosted session is offered it', () {
      expect(desktopPromoEligible(_session()), isTrue);
      expect(
        desktopPromoEligible(
          _session(isHosted: false, baseUrl: 'https://in.example.com'),
        ),
        isTrue,
      );
      expect(
        desktopPromoEligible(
          _session(isHosted: false, baseUrl: 'http://192.168.1.20'),
        ),
        isTrue,
        reason: 'a computer on the same network reaches it',
      );
    });

    test('no session, the demo, or a server only this device reaches', () {
      expect(desktopPromoEligible(null), isFalse);
      expect(
        desktopPromoEligible(_session(isHosted: false, baseUrl: kDemoBaseUrl)),
        isFalse,
      );
      expect(desktopPromoEligible(_session(), isDemoBuild: true), isFalse);
      expect(desktopPromoEligible(_session(), demoMode: true), isFalse);
      for (final url in [
        'http://localhost:8000',
        'http://127.0.0.1',
        'http://10.0.2.2.localhost',
        'http://[::1]:8000',
      ]) {
        expect(
          desktopPromoEligible(_session(isHosted: false, baseUrl: url)),
          isFalse,
          reason: url,
        );
      }
    });
  });

  group('currentAppPromoKind', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    AppPromoKind? on(TargetPlatform p, [AuthSession? s]) {
      debugDefaultTargetPlatformOverride = p;
      final kind = currentAppPromoKind(s ?? _session());
      debugDefaultTargetPlatformOverride = null;
      return kind;
    }

    test('the desktop app on a phone, the phone app everywhere else — never '
        'both on one device', () {
      expect(on(TargetPlatform.iOS), AppPromoKind.desktop);
      expect(on(TargetPlatform.android), AppPromoKind.desktop);
      expect(on(TargetPlatform.macOS), AppPromoKind.mobile);
      expect(on(TargetPlatform.windows), AppPromoKind.mobile);
      expect(on(TargetPlatform.linux), AppPromoKind.mobile);
      expect(on(TargetPlatform.fuchsia), isNull);
    });

    test('an ineligible session gets neither', () {
      final local = _session(isHosted: false, baseUrl: 'http://localhost');
      expect(on(TargetPlatform.iOS, local), isNull);
      expect(on(TargetPlatform.windows, local), isNull);
    });
  });
}
