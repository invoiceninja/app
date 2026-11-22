// The upgrade sheet's side of an in-app purchase: the products, the fail-closed
// config, and starting a purchase tied to the account. Delivery is
// `PurchaseDelivery`'s (purchase_delivery_test.dart); this checks that the
// sheet follows it.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/domain/upgrade/purchase_service.dart';

import '_purchase_fakes.dart';

void main() {
  late FakeBilling billing;
  late FakeApi api;
  late FakeAuth auth;
  late PurchaseDelivery delivery;
  late PurchaseService svc;

  setUp(() {
    billing = FakeBilling();
    api = FakeApi();
    auth = FakeAuth();
    delivery = PurchaseDelivery(
      apiClient: api,
      auth: auth,
      billing: billing,
      platform: TargetPlatform.iOS,
    )..start();
    svc = PurchaseService(auth: auth, delivery: delivery);
  });

  tearDown(() async {
    await svc.dispose();
    await delivery.dispose();
  });

  Future<void> emit(StorePurchase p) async {
    billing.purchases.add([p]);
    await pumpEventQueue();
  }

  group('buying', () {
    setUp(() async {
      await svc.loadConfig();
      await svc.init();
    });

    test('lists the store products', () {
      expect(svc.products.value.map((p) => p.id), [
        'pro_plan',
        'enterprise_plan_annual_5',
      ]);
    });

    test(
      'ties the purchase to the account with its app account token',
      () async {
        await svc.buy(svc.products.value.first);

        final (product, token) = billing.bought.single;
        expect(product.id, 'pro_plan');
        // Apple's appAccountToken / Play's obfuscatedAccountId. Never the
        // account key.
        expect(token, kTestAccountToken);
        expect(svc.busy.value, isTrue);
      },
    );

    test('while a company of another account is active, a purchase never '
        'starts: it would land on the user\'s own account', () async {
      auth.session.value = testSession(accountKey: 'company-acct');

      expect(svc.saleRefusal, SaleRefusal.otherAccount);
      expect(svc.sellsToActiveAccount, isFalse);
      await svc.buy(svc.products.value.first);

      expect(billing.bought, isEmpty);
      expect(svc.busy.value, isFalse);
    });

    test(
      'a purchase that never starts clears busy and says the store failed',
      () async {
        final outcomes = <PurchaseActivity>[];
        svc.outcomes.listen(outcomes.add);
        // StoreKit throws `storekit_duplicate_product_object` for a product that
        // still has an unfinished transaction; no stream event follows.
        billing.buyError = PlatformException(
          code: 'storekit_duplicate_product_object',
          message: 'There is a pending transaction for the same product.',
        );

        await svc.buy(svc.products.value.first);
        await pumpEventQueue();

        expect(svc.busy.value, isFalse);
        expect(billing.bought, isEmpty);
        expect(outcomes.single.kind, PurchaseActivityKind.failed);
        expect(
          outcomes.single.message,
          'There is a pending transaction for the same product.',
        );
      },
    );

    test('a cancelled store sheet clears busy', () async {
      await svc.buy(svc.products.value.first);
      expect(svc.busy.value, isTrue);

      await emit(
        const StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.canceled,
        ),
      );

      expect(svc.busy.value, isFalse);
      expect(api.posts, isEmpty);
    });

    test('a store error clears busy and is reported', () async {
      final outcomes = <PurchaseActivity>[];
      svc.outcomes.listen(outcomes.add);
      await svc.buy(svc.products.value.first);

      await emit(
        const StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.error,
          error: 'payment declined',
        ),
      );

      expect(svc.busy.value, isFalse);
      expect(outcomes.single.kind, PurchaseActivityKind.failed);
    });

    test('a delivered purchase is reported applied, through the app-wide '
        'delivery', () async {
      final outcomes = <PurchaseActivity>[];
      svc.outcomes.listen(outcomes.add);
      await svc.buy(svc.products.value.first);

      await emit(applePurchase());

      expect(api.posts, hasLength(1));
      expect(outcomes.single.kind, PurchaseActivityKind.applied);
      expect(svc.busy.value, isFalse);
    });

    test('a refused purchase is reported with the server message', () async {
      final outcomes = <PurchaseActivity>[];
      svc.outcomes.listen(outcomes.add);
      api.postError = const ConflictException(
        'Already linked to another account.',
        {'reason': 'linked'},
      );

      await emit(applePurchase());

      expect(outcomes.single.kind, PurchaseActivityKind.rejected);
      expect(outcomes.single.message, 'Already linked to another account.');
    });

    test(
      'restore asks the store; the delivery posts what it hands back',
      () async {
        await svc.restore();
        expect(billing.restores, 1);
      },
    );

    test(
      'the open sheet is known to the delivery until it is disposed',
      () async {
        expect(delivery.sheetOpen, isTrue);
        await svc.dispose();
        expect(delivery.sheetOpen, isFalse);
        // A fresh one for tearDown to dispose.
        svc = PurchaseService(auth: auth, delivery: delivery);
      },
    );
  });

  test('with no app account token, a purchase never starts', () async {
    api.iapConfig = const {
      'purchases_enabled': true,
      'account_key': 'acct-key',
    };
    expect(await svc.loadConfig(), isFalse);
    await svc.init();

    await svc.buy(svc.products.value.first);

    expect(billing.bought, isEmpty);
    expect(svc.busy.value, isFalse);
  });

  // Purchases fail closed: the store sheet opens only when the hosted
  // service says it takes in-app purchases and has given this account a
  // token. Until it can verify them, a sheet would take money for a plan
  // that can't be applied.
  // A live store plan is sold over only when the hosted config says the
  // purchase replaces a Legacy-app Play subscription (`replaces_v1_play`); anything else would bill twice.
  group('a live store plan', () {
    AuthSession storePlan() => testSession().copyWith(
      plan: 'pro',
      planExpires: '2099-01-01',
      hasIapPlan: true,
    );

    Future<PurchaseService> serviceOn(
      TargetPlatform platform, {
      bool replaces = true,
    }) async {
      final a = FakeAuth(storePlan());
      final d = PurchaseDelivery(
        apiClient: FakeApi()
          ..iapConfig = {
            'purchases_enabled': true,
            'app_account_token': kTestAccountToken,
            'account_key': 'acct-key',
            'replaces_v1_play': replaces,
          },
        auth: a,
        billing: FakeBilling(),
        platform: platform,
      );
      final s = PurchaseService(auth: a, delivery: d);
      addTearDown(() async {
        await s.dispose();
        await d.dispose();
      });
      await s.loadConfig();
      return s;
    }

    test('is refused when the config replaces nothing (a new-app '
        'subscriber), and a purchase never starts', () async {
      auth.session.value = storePlan();
      await svc.loadConfig();
      await svc.init();

      expect(svc.saleRefusal, SaleRefusal.activeStorePlan);
      expect(svc.replacesLegacyPlay, isFalse);
      await svc.buy(svc.products.value.first);
      expect(billing.bought, isEmpty);
    });

    test('is sold over on Play when the config replaces a Legacy '
        'subscription', () async {
      final s = await serviceOn(TargetPlatform.android);
      expect(s.saleRefusal, isNull);
      expect(s.replacesLegacyPlay, isTrue);
    });

    test('never on Apple, whatever the config says', () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final s = await serviceOn(platform);
        expect(s.saleRefusal, SaleRefusal.activeStorePlan, reason: '$platform');
        expect(s.replacesLegacyPlay, isFalse, reason: '$platform');
      }
    });

    test('a Play config that replaces nothing is refused too', () async {
      final s = await serviceOn(TargetPlatform.android, replaces: false);
      expect(s.saleRefusal, SaleRefusal.activeStorePlan);
    });

    test(
      'an account with no store plan is never told it replaces one',
      () async {
        await svc.loadConfig();
        expect(svc.saleRefusal, isNull);
        expect(svc.replacesLegacyPlay, isFalse);
      },
    );
  });

  group('loadConfig', () {
    test('asks the hosted config and opens when it says so', () async {
      expect(await svc.loadConfig(), isTrue);
      expect(api.gets, ['/api/admin/iap/config']);
      expect(svc.sellsToActiveAccount, isTrue);
    });

    test('a session that does not know its account key yet (a cache from '
        'before 5.1.14) is "not available yet", never "another account", and '
        'is not sold to', () async {
      auth.session.value = testSession(accountKey: '');
      expect(await svc.loadConfig(), isTrue);
      expect(svc.saleRefusal, SaleRefusal.unavailable);
      expect(svc.sellsToActiveAccount, isFalse);

      await svc.init();
      await svc.buy(svc.products.value.first);
      expect(billing.bought, isEmpty);
    });

    test('nothing to refuse once the config sells to this account', () async {
      expect(svc.saleRefusal, SaleRefusal.unavailable);
      await svc.loadConfig();
      expect(svc.saleRefusal, isNull);
    });

    test('reuses the delivery\'s answer: one request', () async {
      await delivery.config();
      expect(await svc.loadConfig(), isTrue);
      expect(api.gets, hasLength(1));
    });

    test('stays closed when the config names no account', () async {
      api.iapConfig = const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
      };
      expect(await svc.loadConfig(), isFalse);
    });

    test('stays closed when the config says no', () async {
      api.iapConfig = const {
        'purchases_enabled': false,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      };
      expect(await svc.loadConfig(), isFalse);
    });

    test('stays closed on a server with no such route', () async {
      api.iapConfig = const ServerException(404, 'Route does not exist');
      expect(await svc.loadConfig(), isFalse);
    });

    test('stays closed on an answer of the wrong shape', () async {
      api.iapConfig = const {
        'purchases_enabled': 'true',
        'app_account_token': kTestAccountToken,
      };
      expect(await svc.loadConfig(), isFalse);
      api.iapConfig = null;
      expect(await svc.loadConfig(), isFalse);
    });

    test(
      'stays closed without a UUID token — StoreKit would drop it',
      () async {
        api.iapConfig = const {
          'purchases_enabled': true,
          'app_account_token': 'acct-key',
          'account_key': 'acct-key',
        };
        expect(await svc.loadConfig(), isFalse);
        expect(
          IapConfig.fromJson(const {
            'purchases_enabled': true,
            'app_account_token': 7,
            'account_key': 'acct-key',
          }).canPurchase,
          isFalse,
        );
      },
    );
  });

  group('hasActiveStoreSubscription', () {
    test('true when the Apple Account holds one of our plans', () async {
      billing.entitlements = {'enterprise_plan_annual_10'};
      expect(await svc.hasActiveStoreSubscription(), isTrue);
      billing.entitlements = {'v2_pro_plan'};
      expect(await svc.hasActiveStoreSubscription(), isTrue);
    });

    test('false with none, or only something else', () async {
      expect(await svc.hasActiveStoreSubscription(), isFalse);
      billing.entitlements = {'some_other_product'};
      expect(await svc.hasActiveStoreSubscription(), isFalse);
    });
  });

  test('billingPeriodOf reads the period from the product id', () {
    for (final id in kProductPlans) {
      expect(
        billingPeriodOf(id),
        id.contains('annual')
            ? PlanBillingPeriod.yearly
            : PlanBillingPeriod.monthly,
        reason: id,
      );
    }
    expect(billingPeriodOf('v2_pro_plan_annual'), PlanBillingPeriod.yearly);
    expect(billingPeriodOf('v2_enterprise_plan_20'), PlanBillingPeriod.monthly);
  });
}
