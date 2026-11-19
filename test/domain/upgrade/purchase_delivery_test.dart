// The app-lifetime delivery of paid store purchases to the hosted service
// (`POST /api/admin/subscription`), and the response contract it follows.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/services/api_exception.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';

import '_purchase_fakes.dart';

void main() {
  late FakeBilling billing;
  late FakeApi api;
  late FakeAuth auth;
  late List<PurchaseActivity> activity;

  PurchaseDelivery build(TargetPlatform platform, {FakeAuth? withAuth}) {
    final delivery = PurchaseDelivery(
      apiClient: api,
      auth: withAuth ?? auth,
      billing: billing,
      platform: platform,
    );
    delivery.activity.listen(activity.add);
    addTearDown(delivery.dispose);
    return delivery;
  }

  setUp(() {
    billing = FakeBilling();
    api = FakeApi();
    auth = FakeAuth();
    activity = [];
  });

  Future<void> emit(StorePurchase p) async {
    billing.purchases.add([p]);
    // Let the stream callback and its awaits run.
    await pumpEventQueue();
  }

  List<PurchaseActivityKind> kinds() => [for (final a in activity) a.kind];

  group('delivery', () {
    test('posts the StoreKit 2 original id, its JWS, the store and the '
        'bundle; finishes; refreshes', () async {
      build(TargetPlatform.iOS).start();
      final p = applePurchase(productId: 'enterprise-plan');
      await emit(p);

      final (path, body) = api.posts.single;
      expect(path, '/api/admin/subscription');
      expect(body, {
        'inapp_transaction_id': '2000000111111',
        // The account's key, never its id: the hosted endpoint looks the
        // account up by key.
        'key': 'acct-key',
        'plan': 'enterprise_plan',
        'verification_data': 'eyJhbGciOiJFUzI1NiJ9.apple-jws.sig',
        'source': 'app_store',
        'bundle_id': 'com.invoiceninja.admin',
      });
      expect(billing.completed, [p]);
      expect(auth.refreshes, 1);
      expect(kinds(), [
        PurchaseActivityKind.delivering,
        PurchaseActivityKind.applied,
      ]);
    });

    test(
      'Google sends the order id, the purchase token and google_play',
      () async {
        build(TargetPlatform.android).start();
        await emit(googlePurchase());

        final body = api.posts.single.$2!;
        expect(body['inapp_transaction_id'], 'GPA.3123-4567-8901-23456');
        expect(body['verification_data'], 'play-purchase-token');
        expect(body['source'], 'google_play');
        expect(body['bundle_id'], 'com.invoiceninja.admin');
      },
    );

    test('strips the v2_ prefix from the plan it sends', () async {
      build(TargetPlatform.iOS).start();
      await emit(applePurchase(productId: 'v2_enterprise_plan_annual_10'));

      expect(api.posts.single.$2!['plan'], 'enterprise_plan_annual_10');
    });

    test('StoreKit 1 uses the original transaction when present', () async {
      build(TargetPlatform.iOS).start();
      await emit(
        const StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.restored,
          purchaseId: 'per-transaction',
          isStoreKit1: true,
          storeKit1OriginalTransactionId: 'original',
        ),
      );

      expect(api.posts.single.$2?['inapp_transaction_id'], 'original');
      // No verification data, so none is sent.
      expect(api.posts.single.$2, isNot(contains('verification_data')));
    });

    test('Apple delivers a restored transaction', () async {
      build(TargetPlatform.iOS).start();
      await emit(applePurchase(status: StorePurchaseStatus.restored));

      expect(api.posts, hasLength(1));
      expect(auth.refreshes, 1);
      // StoreKit 2 never marks a restored transaction finishable.
      expect(billing.completed, isEmpty);
    });

    test(
      'Play delivers a restored purchase only while unacknowledged',
      () async {
        build(TargetPlatform.android).start();
        await emit(
          googlePurchase(
            status: StorePurchaseStatus.restored,
            acknowledged: true,
          ),
        );
        expect(api.posts, isEmpty);

        final unacked = googlePurchase(status: StorePurchaseStatus.restored);
        await emit(unacked);
        expect(api.posts, hasLength(1));
        expect(billing.completed, [unacked]);
      },
    );

    test('skips delivery with no transaction id, but finishes', () async {
      build(TargetPlatform.iOS).start();
      const p = StorePurchase(
        productId: 'pro_plan',
        status: StorePurchaseStatus.purchased,
        pendingCompletePurchase: true,
      );
      await emit(p);

      expect(api.posts, isEmpty);
      expect(auth.refreshes, 0);
      expect(billing.completed, [p]);
    });

    test('a refresh failing after delivery still finishes', () async {
      build(TargetPlatform.android).start();
      auth.refreshError = Exception('offline');
      final p = googlePurchase();
      await emit(p);

      expect(billing.completed, [p]);
      expect(kinds().last, PurchaseActivityKind.applied);
    });

    test('a store error or a cancel delivers nothing', () async {
      build(TargetPlatform.iOS).start();
      await emit(
        const StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.error,
          error: 'storekit_error',
        ),
      );
      await emit(
        const StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.canceled,
        ),
      );

      expect(api.posts, isEmpty);
      expect(kinds(), [
        PurchaseActivityKind.failed,
        PurchaseActivityKind.canceled,
      ]);
      expect(activity.first.message, 'storekit_error');
    });
  });

  // The hosted service's answer decides whether the purchase is finished
  // with the store. Finished too early, a purchase the account never got is
  // gone for good: Apple never hands a finished transaction back, and Google
  // never refunds an acknowledged one.
  group('response contract', () {
    final permanent = <String, Object>{
      '409 sandbox': const ConflictException(
        'Test purchases are not applied to this account.',
        {'message': 'Test purchases are not applied.', 'reason': 'sandbox'},
      ),
      '409 linked': const ConflictException(
        'Already linked to another account.',
        {'reason': 'linked'},
      ),
      '422 unverified': const ValidationException(
        'The purchase could not be verified.',
        {},
        body: {'reason': 'unverified'},
      ),
      '403': const ServerException(403, 'Invalid token', {}),
    };

    for (final MapEntry(key: name, value: error) in permanent.entries) {
      test('$name: Apple finishes it and shows the server message', () async {
        build(TargetPlatform.iOS).start();
        api.postError = error;
        final p = applePurchase();
        await emit(p);

        expect(billing.completed, [p]);
        expect(auth.refreshes, 0);
        expect(kinds().last, PurchaseActivityKind.rejected);
        expect(activity.last.message, (error as ApiException).message);
      });

      test(
        '$name: Google leaves it unacknowledged, so Play refunds it',
        () async {
          build(TargetPlatform.android).start();
          api.postError = error;
          await emit(googlePurchase());

          expect(api.posts, hasLength(1));
          expect(billing.completed, isEmpty);
          expect(auth.refreshes, 0);
          expect(kinds().last, PurchaseActivityKind.rejected);
        },
      );
    }

    final transient = <String, Object>{
      '500': const ServerException(500, 'Server Error'),
      'network': const NetworkException('Connection reset'),
      '404 (no route yet)': const ServerException(404, 'Route does not exist'),
      'a 400 entity-missing': const NotFoundException('No query results'),
    };
    for (final MapEntry(key: name, value: error) in transient.entries) {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        test('$name on ${platform.name}: left unfinished for the next '
            'launch', () async {
          build(platform).start();
          api.postError = error;
          await emit(
            platform == TargetPlatform.iOS ? applePurchase() : googlePurchase(),
          );

          expect(api.posts, hasLength(1));
          expect(billing.completed, isEmpty);
          expect(auth.refreshes, 0);
          expect(kinds().last, PurchaseActivityKind.retryLater);
        });
      }
    }
  });

  group('who it is delivered to', () {
    test('signed out: left unfinished, nothing posted', () async {
      build(TargetPlatform.iOS).start();
      auth.session.value = null;
      await emit(applePurchase());

      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);
      expect(kinds(), [PurchaseActivityKind.retryLater]);
    });

    test('no account key yet: left unfinished', () async {
      build(TargetPlatform.android).start();
      auth.session.value = testSession(accountKey: '');
      await emit(googlePurchase());

      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);
    });

    test('a self-hosted session never posts it (wrong server)', () async {
      build(TargetPlatform.android).start();
      auth.session.value = testSession(
        isHosted: false,
        baseUrl: 'https://billing.example.com',
      );
      await emit(googlePurchase());

      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);
    });
  });

  group('from app start', () {
    test(
      'listens as soon as a hosted session exists, and never before',
      () async {
        final signedOut = FakeAuth()..session.value = null;
        build(TargetPlatform.iOS, withAuth: signedOut).start();
        await pumpEventQueue();
        expect(billing.streamListens, 0);

        signedOut.session.value = testSession();
        await pumpEventQueue();
        expect(billing.streamListens, 1);

        // A refresh of the same session subscribes nothing new.
        signedOut.session.value = testSession();
        await pumpEventQueue();
        expect(billing.streamListens, 1);
      },
    );

    test('delivers a purchase left unfinished by an earlier launch', () async {
      final p = googlePurchase();
      billing.unfinished = [p];
      build(TargetPlatform.android).start();
      await pumpEventQueue();

      expect(api.posts.single.$2!['inapp_transaction_id'], p.purchaseId);
      expect(billing.completed, [p]);
      expect(auth.refreshes, 1);
    });

    test(
      'sweeps again when another account signs in, not on a refresh',
      () async {
        final p = applePurchase();
        billing.unfinished = [p];
        // Signed out at launch: nothing to deliver it to yet.
        final launchAuth = FakeAuth()..session.value = null;
        build(TargetPlatform.iOS, withAuth: launchAuth).start();
        await pumpEventQueue();
        expect(api.posts, isEmpty);

        launchAuth.session.value = testSession();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        launchAuth.session.value = testSession();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        launchAuth.session.value = testSession(accountKey: 'other-acct');
        await pumpEventQueue();
        expect(api.posts, hasLength(2));
        expect(api.posts.last.$2!['key'], 'other-acct');
      },
    );

    test(
      'the same purchase handed over twice at once is posted once',
      () async {
        final p = applePurchase();
        billing.unfinished = [p];
        api.postGate = Completer<void>();
        build(TargetPlatform.iOS).start();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        // `Transaction.updates` hands it over while the sweep's POST is out.
        billing.purchases.add([p]);
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        api.postGate!.complete();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));
        expect(billing.completed, [p]);
      },
    );
  });

  group('helpers', () {
    test('isPermanentRejection', () {
      expect(isPermanentRejection(const ConflictException()), isTrue);
      expect(isPermanentRejection(const ValidationException('x', {})), isTrue);
      expect(isPermanentRejection(const ServerException(403)), isTrue);
      expect(isPermanentRejection(const NotFoundException()), isFalse);
      expect(isPermanentRejection(const ServerException(500)), isFalse);
      expect(isPermanentRejection(const ServerException(401)), isFalse);
      expect(isPermanentRejection(const NetworkException('x')), isFalse);
      expect(isPermanentRejection(Exception('x')), isFalse);
    });

    test('planSlugOf', () {
      expect(planSlugOf('pro_plan'), 'pro_plan');
      expect(planSlugOf('enterprise-plan'), 'enterprise_plan');
      expect(planSlugOf('v2_pro_plan_annual'), 'pro_plan_annual');
      // Only a leading prefix.
      expect(planSlugOf('pro_v2_plan'), 'pro_v2_plan');
    });
  });

  group('appleOriginalTransactionId', () {
    test('reads the original id, not the per-transaction id', () {
      expect(
        appleOriginalTransactionId(appleTransactionJson()),
        '2000000111111',
      );
    });

    test('coerces a numeric original id to a string', () {
      expect(
        appleOriginalTransactionId(
          appleTransactionJson(originalTransactionId: 2000000111111),
        ),
        '2000000111111',
      );
    });

    test('returns null when absent, empty, or not a JSON object', () {
      expect(
        appleOriginalTransactionId(
          appleTransactionJson(originalTransactionId: null),
        ),
        isNull,
      );
      expect(
        appleOriginalTransactionId(
          appleTransactionJson(originalTransactionId: ''),
        ),
        isNull,
      );
      expect(appleOriginalTransactionId(''), isNull);
      expect(appleOriginalTransactionId('{not json'), isNull);
      expect(appleOriginalTransactionId('[1,2,3]'), isNull);
      expect(appleOriginalTransactionId('"a string"'), isNull);
    });

    test(
      "returns null for Google's purchase JSON, so Android keeps orderId",
      () {
        final googleJson = jsonEncode({
          'orderId': 'GPA.3123-4567-8901-23456',
          'packageName': 'com.invoiceninja.admin',
          'productId': 'pro_plan',
          'purchaseTime': 1751000000000,
          'purchaseState': 0,
          'purchaseToken': 'abcdef.AO-J1Oy...',
          'acknowledged': false,
        });

        expect(appleOriginalTransactionId(googleJson), isNull);
      },
    );
  });
}
