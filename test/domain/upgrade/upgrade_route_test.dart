// Where Upgrade goes, per build and account. A store build (App Store, Play,
// Mac App Store) may not send anyone to an external purchase (App Store
// 3.1.1(a), Play Payments 4), and must not sell a second subscription while
// one may still bill. The F-Droid / GitHub APKs, desktop and the web keep the
// billing portal (docs/fdroid.md).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';

final _now = DateTime.utc(2026, 11, 19, 12);

String _daysAgo(int days) =>
    _now.subtract(Duration(days: days)).toIso8601String().substring(0, 10);

AuthSession _session({
  bool isHosted = true,
  String plan = '',
  String planExpires = '',
  bool hasIapPlan = false,
  int trialDaysLeft = -1,
  bool isOwner = true,
}) => AuthSession(
  baseUrl: isHosted ? 'https://invoicing.co' : 'https://in.example.test',
  isHosted: isHosted,
  accountId: 'acct',
  currentCompanyId: 'co',
  plan: plan,
  planExpires: planExpires,
  hasIapPlan: hasIapPlan,
  trialDaysLeft: trialDaysLeft,
  companies: [
    AuthCompany(
      id: 'co',
      name: 'Co',
      displayName: 'Co',
      permissions: '',
      isAdmin: isOwner,
      isOwner: isOwner,
    ),
  ],
);

/// Every account shape the routing distinguishes.
final _accounts = <String, AuthSession>{
  'free': _session(),
  'trial': _session(plan: 'pro', trialDaysLeft: 7),
  'web-paid': _session(plan: 'enterprise', planExpires: '2027-06-01'),
  'active IAP': _session(
    plan: 'pro',
    planExpires: '2026-12-19',
    hasIapPlan: true,
  ),
  // The server blanks `plan` once `plan_expires` has passed.
  'lapsed IAP, recent': _session(planExpires: _daysAgo(10), hasIapPlan: true),
  'lapsed IAP, >60 days': _session(planExpires: _daysAgo(90), hasIapPlan: true),
  'lapsed IAP, no date': _session(hasIapPlan: true),
  'self-hosted': _session(isHosted: false),
  'non-owner, free': _session(isOwner: false),
};

UpgradeRoute _route(bool storeBilling, String account) => resolveUpgradeRoute(
  storeBilling: storeBilling,
  session: _accounts[account],
  now: _now,
);

void main() {
  group('storeBillingFor', () {
    bool store(TargetPlatform platform, {bool storeBuild = true}) =>
        storeBillingFor(
          isStoreBuild: storeBuild,
          isWeb: false,
          platform: platform,
        );

    test('store builds on iOS, Android and macOS sell in-app', () {
      expect(store(TargetPlatform.iOS), isTrue);
      expect(store(TargetPlatform.android), isTrue);
      // Every native macOS build is the Mac App Store build.
      expect(store(TargetPlatform.macOS), isTrue);
    });

    test('F-Droid / GitHub APKs (the FOSS twin) do not', () {
      expect(store(TargetPlatform.android, storeBuild: false), isFalse);
    });

    test('Windows, Linux and the web do not', () {
      expect(store(TargetPlatform.windows), isFalse);
      expect(store(TargetPlatform.linux), isFalse);
      for (final p in TargetPlatform.values) {
        expect(
          storeBillingFor(isStoreBuild: true, isWeb: true, platform: p),
          isFalse,
          reason: 'web on $p',
        );
      }
    });

    test('the test override wins', () {
      addTearDown(() => debugStoreBillingOverride = null);
      debugStoreBillingOverride = false;
      expect(isStoreBillingBuild, isFalse);
      debugStoreBillingOverride = true;
      expect(isStoreBillingBuild, isTrue);
    });
  });

  group('store builds', () {
    const expected = {
      'free': UpgradeRoute.purchaseSheet,
      'trial': UpgradeRoute.planScreen,
      'web-paid': UpgradeRoute.planScreen,
      'active IAP': UpgradeRoute.storeSubscriptions,
      'lapsed IAP, recent': UpgradeRoute.storeSubscriptionsEnded,
      'lapsed IAP, >60 days': UpgradeRoute.purchaseSheet,
      'lapsed IAP, no date': UpgradeRoute.storeSubscriptionsEnded,
      'self-hosted': UpgradeRoute.planScreen,
      'non-owner, free': UpgradeRoute.planScreen,
    };
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      final storeBilling = storeBillingFor(
        isStoreBuild: true,
        isWeb: false,
        platform: platform,
      );
      for (final MapEntry(key: account, value: route) in expected.entries) {
        test('${platform.name}, $account → ${route.name}', () {
          expect(_route(storeBilling, account), route);
        });
      }
    }

    test('never send anyone to the billing portal', () {
      for (final account in _accounts.keys) {
        expect(
          _route(true, account),
          isNot(UpgradeRoute.billingPortal),
          reason: account,
        );
      }
      expect(
        resolveUpgradeRoute(storeBilling: true, session: null, now: _now),
        isNot(UpgradeRoute.billingPortal),
      );
    });

    test('a lapsed in-app plan of a non-owner gets the Plan screen', () {
      final s = _session(
        planExpires: _daysAgo(10),
        hasIapPlan: true,
        isOwner: false,
      );
      expect(
        resolveUpgradeRoute(storeBilling: true, session: s, now: _now),
        UpgradeRoute.planScreen,
      );
    });
  });

  group('desktop, web and F-Droid builds', () {
    const expected = {
      'free': UpgradeRoute.billingPortal,
      'trial': UpgradeRoute.billingPortal,
      'web-paid': UpgradeRoute.billingPortal,
      // Bought in a store: managed there, never the portal.
      'active IAP': UpgradeRoute.planScreen,
      'lapsed IAP, recent': UpgradeRoute.billingPortal,
      'lapsed IAP, >60 days': UpgradeRoute.billingPortal,
      'self-hosted': UpgradeRoute.planScreen,
      'non-owner, free': UpgradeRoute.billingPortal,
    };
    final builds = {
      'F-Droid Android': storeBillingFor(
        isStoreBuild: false,
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      'Windows': storeBillingFor(
        isStoreBuild: true,
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      'Linux': storeBillingFor(
        isStoreBuild: true,
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      'web': storeBillingFor(
        isStoreBuild: true,
        isWeb: true,
        platform: TargetPlatform.iOS,
      ),
    };
    for (final MapEntry(key: build, value: storeBilling) in builds.entries) {
      for (final MapEntry(key: account, value: route) in expected.entries) {
        test('$build, $account → ${route.name}', () {
          expect(_route(storeBilling, account), route);
        });
      }
      test('$build never opens the purchase sheet', () {
        for (final account in _accounts.keys) {
          expect(
            _route(storeBilling, account),
            isNot(UpgradeRoute.purchaseSheet),
            reason: account,
          );
        }
      });
    }
  });

  group('iapPlanEndedLongAgo', () {
    test('60 days is the line, counted from the end of the paid day', () {
      // Paid through 2026-09-19 → over at 2026-09-20T00:00Z; 60 days on is
      // 2026-11-19T00:00Z, which "now" (noon) is past.
      expect(iapPlanEndedLongAgo('2026-09-19', now: _now), isTrue);
      expect(iapPlanEndedLongAgo('2026-09-20', now: _now), isFalse);
      expect(iapPlanEndedLongAgo(_daysAgo(30), now: _now), isFalse);
    });

    test('a timestamp-shaped value reads its day', () {
      expect(iapPlanEndedLongAgo('2026-01-01 00:00:00', now: _now), isTrue);
    });

    test('blank, garbage and sentinel dates read as recent', () {
      for (final raw in ['', '  ', 'soon', '0000-00-00', '1970-01-01']) {
        expect(iapPlanEndedLongAgo(raw, now: _now), isFalse, reason: raw);
      }
    });
  });

  group('isExternalPurchaseUri', () {
    test('Stripe payment pages and Invoice Ninja billing are purchases', () {
      for (final url in [
        'https://checkout.stripe.com/c/pay/cs_live_abc',
        'https://billing.stripe.com/p/session/abc',
        'https://buy.stripe.com/abc',
        'https://pay.stripe.com/invoice/abc',
        'https://invoice.stripe.com/i/abc',
        'https://invoiceninja.invoicing.co/client/key_login/abc',
        'https://invoiceninja.invoicing.co/client/subscriptions/O5xe7Rwd7r/purchase',
        'https://acme.invoicing.co/client/subscriptions/x/purchase',
        'https://invoiceninja.com/pricing/',
        'https://www.invoiceninja.com/pricing-update-january-1-2026/',
      ]) {
        expect(isExternalPurchaseUri(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('help pages, the web app and Stripe docs are not', () {
      for (final url in [
        'https://app.invoicing.co/#/documents',
        'https://invoiceninja.github.io/docs/user-guide/einvoicing',
        'https://invoiceninja.com/privacy-policy/',
        'https://docs.stripe.com/terminal',
        'https://dashboard.stripe.com/customers/cus_1',
      ]) {
        expect(isExternalPurchaseUri(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });
}
