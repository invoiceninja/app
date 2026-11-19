// The upgrade sheet's side of an in-app purchase: the products, the fail-closed
// config, and starting a purchase tied to the account. Delivery is
// `PurchaseDelivery`'s (purchase_delivery_test.dart); this checks that the
// sheet follows it.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

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
    svc = PurchaseService(apiClient: api, auth: auth, delivery: delivery);
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

    test('with no account key yet, a purchase never starts', () async {
      auth.session.value = testSession(accountKey: '');

      await svc.buy(svc.products.value.first);

      expect(billing.bought, isEmpty);
      expect(svc.busy.value, isFalse);
    });

    test(
      'a purchase that never starts clears busy instead of throwing',
      () async {
        // StoreKit throws `storekit_duplicate_product_object` for a product that
        // still has an unfinished transaction; no stream event follows.
        billing.buyError = Exception('storekit_duplicate_product_object');

        await svc.buy(svc.products.value.first);

        expect(svc.busy.value, isFalse);
        expect(billing.bought, isEmpty);
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
        svc = PurchaseService(apiClient: api, auth: auth, delivery: delivery);
      },
    );
  });

  test('with no app account token, a purchase never starts', () async {
    api.iapConfig = const {'purchases_enabled': true};
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
  group('loadConfig', () {
    test('asks the hosted config and opens when it says so', () async {
      expect(await svc.loadConfig(), isTrue);
      expect(api.gets, ['/api/admin/iap/config']);
    });

    test('stays closed when the config says no', () async {
      api.iapConfig = const {
        'purchases_enabled': false,
        'app_account_token': kTestAccountToken,
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
        };
        expect(await svc.loadConfig(), isFalse);
        api.iapConfig = const {
          'purchases_enabled': true,
          'app_account_token': 7,
        };
        expect(await svc.loadConfig(), isFalse);
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
