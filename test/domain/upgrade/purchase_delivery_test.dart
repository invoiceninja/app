// The app-lifetime delivery of paid store purchases to the hosted service
// (`POST /api/admin/subscription`), and the response contract it follows.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
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
  late FakeTimers timers;

  PurchaseDelivery build(TargetPlatform platform, {FakeAuth? withAuth}) {
    final delivery = PurchaseDelivery(
      apiClient: api,
      auth: withAuth ?? auth,
      billing: billing,
      platform: platform,
      timer: timers.call,
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
    timers = FakeTimers();
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
        // The config's `account_key`, never the account id: the hosted
        // endpoint looks the account up by key.
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

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      test('${platform.name}: no transaction id and nothing else to name it '
          'by: left unfinished, and the sheet hears it', () async {
        build(platform).start();
        const p = StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.purchased,
          pendingCompletePurchase: true,
        );
        await emit(p);

        expect(api.posts, isEmpty);
        expect(auth.refreshes, 0);
        // Play refunds an acknowledged purchase never, and a later hand-over
        // may carry the id.
        expect(billing.completed, isEmpty);
        expect(kinds(), [PurchaseActivityKind.retryLater]);
      });
    }

    test('Google with no order id yet posts by its purchase token', () async {
      build(TargetPlatform.android).start();
      final p = googlePurchase(orderId: null);
      await emit(p);

      final body = api.posts.single.$2!;
      expect(body, isNot(contains('inapp_transaction_id')));
      expect(body['verification_data'], 'play-purchase-token');
      expect(body['key'], 'acct-key');
      expect(billing.completed, [p]);
      expect(kinds().last, PurchaseActivityKind.applied);
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
    // The hosted service's final word: a finished Apple transaction is never
    // handed back, so only these finish it.
    final finalRefusals = <String, Object>{
      '409 sandbox': const ConflictException(
        'Test purchases are not applied to this account.',
        {'message': 'Test purchases are not applied.', 'reason': 'sandbox'},
      ),
      '409 linked': const ConflictException(
        'Already linked to another account.',
        {'reason': 'linked'},
      ),
      '409 expired': const ConflictException('Expired.', {'reason': 'expired'}),
      '409 revoked': const ConflictException('Refunded.', {
        'reason': 'revoked',
      }),
      '409 upgraded': const ConflictException('Upgraded.', {
        'reason': 'upgraded',
      }),
      '422 sandbox': const ValidationException(
        'A test purchase.',
        {},
        body: {'reason': 'sandbox'},
      ),
    };
    // Refusals that may change: the purchase stays with the store.
    final openRefusals = <String, Object>{
      '409 account': const ConflictException(
        'This purchase was posted for another account.',
        {'reason': 'account'},
      ),
      '409 token_mismatch': const ConflictException(
        'Bought for another account.',
        {'reason': 'token_mismatch'},
      ),
      '409 no_token': const ConflictException('No account token.', {
        'reason': 'no_token',
      }),
      '409 with no reason': const ConflictException('Conflict', {}),
      '409 with an unknown reason': const ConflictException('Conflict', {
        'reason': 'something_new',
      }),
      '422 unverified': const ValidationException(
        'The purchase could not be verified.',
        {},
        body: {'reason': 'unverified'},
      ),
    };

    for (final MapEntry(key: name, value: error) in finalRefusals.entries) {
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
    }

    for (final MapEntry(key: name, value: error) in openRefusals.entries) {
      test('$name: Apple leaves it unfinished and shows the server '
          'message', () async {
        build(TargetPlatform.iOS).start();
        api.postError = error;
        await emit(applePurchase());

        expect(api.posts, hasLength(1));
        expect(billing.completed, isEmpty);
        expect(auth.refreshes, 0);
        expect(kinds().last, PurchaseActivityKind.rejected);
      });
    }

    for (final MapEntry(key: name, value: error) in {
      ...finalRefusals,
      ...openRefusals,
    }.entries) {
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
      // The hosted token check answers 403 for a stale or invalid token, or
      // a locked user: the purchase is fine, the session is not.
      '403 (stale token)': const ServerException(403, 'Invalid token', {}),
      '429': const RateLimitedException(),
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

    test('a config that names no account: left unfinished', () async {
      api.iapConfig = const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
      };
      build(TargetPlatform.android).start();
      await emit(googlePurchase());

      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);
      expect(kinds(), [PurchaseActivityKind.retryLater]);
    });

    test(
      'a purchase bought under another account token is left alone',
      () async {
        build(TargetPlatform.iOS).start();
        await emit(
          applePurchase(
            appAccountToken: '11111111-2222-3333-4444-555555555555',
          ),
        );

        expect(api.posts, isEmpty);
        expect(billing.completed, isEmpty);
      },
    );

    test('Google: an obfuscatedAccountId of another account is left '
        'alone', () async {
      build(TargetPlatform.android).start();
      await emit(
        googlePurchase(
          obfuscatedAccountId: '11111111-2222-3333-4444-555555555555',
        ),
      );

      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);
    });

    test("this account's token (any case) is delivered", () async {
      build(TargetPlatform.iOS).start();
      await emit(
        applePurchase(appAccountToken: kTestAccountToken.toUpperCase()),
      );

      expect(api.posts, hasLength(1));
    });

    for (final (name, extra) in [
      ('revoked', <String, Object?>{'revocationDate': 1751000000000}),
      ('upgraded', <String, Object?>{'isUpgraded': true}),
    ]) {
      test('an Apple transaction $name is finished, not posted, and not '
          'said', () async {
        build(TargetPlatform.iOS).start();
        final p = applePurchase(extra: extra);
        await emit(p);

        expect(api.posts, isEmpty);
        expect(billing.completed, [p]);
        expect(activity, isEmpty);
      });
    }

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

  // The hosted service says it takes this app's purchases by answering
  // `GET /api/admin/iap/config` with a 200. Until it has, for this session,
  // nothing is posted and nothing paid is finished: a server without the
  // route must never be handed a purchase.
  group('the hosted config gate', () {
    final unknown = <String, Object>{
      '404 (no route)': const ServerException(404, 'Route does not exist'),
      '500': const ServerException(500, 'Server Error'),
      'network': const NetworkException('Connection reset'),
    };
    for (final MapEntry(key: name, value: error) in unknown.entries) {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        test(
          'config $name on ${platform.name}: nothing posted or finished',
          () async {
            api.iapConfig = error;
            build(platform).start();
            await emit(
              platform == TargetPlatform.iOS
                  ? applePurchase()
                  : googlePurchase(),
            );

            expect(api.gets, ['/api/admin/iap/config']);
            expect(api.posts, isEmpty);
            expect(billing.completed, isEmpty);
            expect(auth.refreshes, 0);
            expect(kinds(), [PurchaseActivityKind.retryLater]);
          },
        );
      }
    }

    test('the launch sweep posts nothing while the config is unknown, and '
        'delivers once a later session update finds it', () async {
      final p = googlePurchase();
      billing.unfinished = [p];
      api.iapConfig = const ServerException(404, 'Route does not exist');
      build(TargetPlatform.android).start();
      await pumpEventQueue();
      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);

      // The route is deployed; the next refresh of the same session sweeps.
      api.iapConfig = const {'purchases_enabled': false, 'account_key': 'k'};
      auth.session.value = testSession();
      await pumpEventQueue();
      expect(api.posts, hasLength(1));
      expect(billing.completed, [p]);
    });

    test('a purchase with no transaction id is not finished while the config '
        'is unknown', () async {
      api.iapConfig = const ServerException(404, 'Route does not exist');
      build(TargetPlatform.iOS).start();
      await emit(
        const StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.purchased,
          pendingCompletePurchase: true,
        ),
      );
      expect(billing.completed, isEmpty);
    });

    test('purchases switched off still deliver what was paid for', () async {
      api.iapConfig = const {
        'purchases_enabled': false,
        'account_key': 'acct-key',
      };
      build(TargetPlatform.iOS).start();
      await emit(applePurchase());
      expect(api.posts, hasLength(1));
      expect(kinds().last, PurchaseActivityKind.applied);
    });

    test('asked once per user, and again for another user', () async {
      build(TargetPlatform.iOS).start();
      await emit(applePurchase());
      await emit(applePurchase());
      expect(api.gets, hasLength(1));
      expect(api.posts, hasLength(2));

      // A company of another account: the same user, the same config.
      auth.session.value = testSession(accountKey: 'other-acct');
      await pumpEventQueue();
      await emit(applePurchase());
      expect(api.gets, hasLength(1));

      auth.session.value = testSession(userId: 'someone-else');
      await pumpEventQueue();
      await emit(applePurchase());
      expect(api.gets, hasLength(2));
    });

    test('the sheet reads the same answer, with no second request', () async {
      final delivery = build(TargetPlatform.iOS)..start();
      await emit(applePurchase());
      final config = await delivery.config();
      expect(config?.accountKey, 'acct-key');
      expect(api.gets, hasLength(1));
    });

    test('asked again after a failure', () async {
      api.iapConfig = const NetworkException('offline');
      build(TargetPlatform.iOS).start();
      await emit(applePurchase());
      expect(api.posts, isEmpty);

      api.iapConfig = const {'purchases_enabled': true, 'account_key': 'k'};
      await emit(applePurchase());
      expect(api.gets, hasLength(2));
      expect(api.posts, hasLength(1));
    });

    test('asked afresh after a sign-out and back in', () async {
      build(TargetPlatform.iOS).start();
      await emit(applePurchase());
      expect(api.gets, hasLength(1));

      auth.session.value = null;
      await pumpEventQueue();
      auth.session.value = testSession();
      await pumpEventQueue();
      await emit(applePurchase());
      expect(api.gets, hasLength(2));
    });

    test('Restore asks the store, whatever the config says', () async {
      api.iapConfig = const {'purchases_enabled': false, 'account_key': 'k'};
      final delivery = build(TargetPlatform.iOS)..start();
      await delivery.restore();
      expect(billing.restores, 1);
    });
  });

  // The hosted endpoint applies a purchase to the signed-in user's own
  // account (`user->account`), whichever company is active; the config names
  // it (`account_key`), and that is the key posted.
  group("the config's account key", () {
    test("posts the config's key, not a key the session guessed", () async {
      api.iapConfig = const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
        'account_key': 'my-acct',
      };
      auth.session.value = testSession(
        accountKey: 'company-acct',
        userAccountKey: 'some-guess',
      );
      build(TargetPlatform.iOS).start();
      await emit(applePurchase());

      expect(api.posts.single.$2!['key'], 'my-acct');
    });

    test(
      'a switch to a company of another account sweeps nothing new',
      () async {
        billing.unfinished = [applePurchase()];
        auth.session.value = testSession(accountKey: 'my-acct');
        build(TargetPlatform.iOS).start();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        auth.session.value = testSession(accountKey: 'company-acct');
        await pumpEventQueue();
        expect(api.posts, hasLength(1));
      },
    );
  });

  group('trying again', () {
    test('a purchase not applied yet is swept again with a backoff, capped, '
        'while the app runs', () async {
      api.postError = const ServerException(500, 'Server Error');
      final p = applePurchase();
      billing.unfinished = [p];
      build(TargetPlatform.iOS).start();
      await pumpEventQueue();
      expect(api.posts, hasLength(1));
      expect(timers.delays, [const Duration(seconds: 30)]);

      for (var i = 0; i < 3; i++) {
        timers.fireLast();
        await pumpEventQueue();
      }
      expect(api.posts, hasLength(4));
      expect(timers.delays, const [
        Duration(seconds: 30),
        Duration(minutes: 2),
        Duration(minutes: 10),
        Duration(minutes: 10),
      ]);

      // The server is back: applied, finished, and no more retries.
      api.postError = null;
      timers.fireLast();
      await pumpEventQueue();
      expect(billing.completed, [p]);
      expect(kinds().last, PurchaseActivityKind.applied);
      expect(timers.scheduled, hasLength(4));
    });

    test('a return to the foreground sweeps again', () async {
      final delivery = build(TargetPlatform.android)..start();
      await pumpEventQueue();
      final p = googlePurchase();
      billing.unfinished = [p];

      PurchaseResumeObserver(
        delivery,
      ).didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(api.posts, hasLength(1));
      expect(billing.completed, [p]);
    });

    test('a Google acknowledgement Play did not confirm is swept '
        'again', () async {
      billing.completeResult = false;
      build(TargetPlatform.android).start();
      await emit(googlePurchase());

      expect(billing.completed, hasLength(1));
      expect(timers.delays, [const Duration(seconds: 30)]);
    });
  });

  group('from app start', () {
    test(
      'sweeps again after a sign-out and back in to the same account',
      () async {
        billing.unfinished = [applePurchase()];
        build(TargetPlatform.iOS).start();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        auth.session.value = null;
        await pumpEventQueue();
        auth.session.value = testSession();
        await pumpEventQueue();
        expect(api.posts, hasLength(2));
      },
    );

    test('what the launch sweep did before anything listened reaches the '
        'first listener', () async {
      billing.unfinished = [applePurchase()];
      api.postError = const ConflictException('Sandbox', {'reason': 'sandbox'});
      final delivery = PurchaseDelivery(
        apiClient: api,
        auth: auth,
        billing: billing,
        platform: TargetPlatform.iOS,
      )..start();
      addTearDown(delivery.dispose);
      await pumpEventQueue();
      expect(api.posts, hasLength(1));

      final heard = <PurchaseActivity>[];
      delivery.activity.listen(heard.add);
      await pumpEventQueue();
      expect(
        [for (final a in heard) a.kind],
        [PurchaseActivityKind.delivering, PurchaseActivityKind.rejected],
      );

      // Handed over once: a second listener hears only what comes next.
      final later = <PurchaseActivity>[];
      delivery.activity.listen(later.add);
      await pumpEventQueue();
      expect(later, isEmpty);
    });

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

    test('sweeps again when another user signs in, not on a refresh', () async {
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

      api.iapConfig = const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
        'account_key': 'other-acct',
      };
      launchAuth.session.value = testSession(userId: 'someone-else');
      await pumpEventQueue();
      expect(api.posts, hasLength(2));
      expect(api.posts.last.$2!['key'], 'other-acct');
    });

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
      expect(isPermanentRejection(const ServerException(403)), isFalse);
      expect(isPermanentRejection(const NotFoundException()), isFalse);
      expect(isPermanentRejection(const ServerException(500)), isFalse);
      expect(isPermanentRejection(const ServerException(401)), isFalse);
      expect(isPermanentRejection(const NetworkException('x')), isFalse);
      expect(isPermanentRejection(Exception('x')), isFalse);
    });

    test('finishesOnRejection: only a final reason', () {
      for (final reason in kFinalRejectionReasons) {
        expect(
          finishesOnRejection(ConflictException('x', {'reason': reason})),
          isTrue,
          reason: reason,
        );
        expect(
          finishesOnRejection(
            ValidationException('x', const {}, body: {'reason': reason}),
          ),
          isTrue,
          reason: reason,
        );
      }
      for (final reason in ['account', 'token_mismatch', 'no_token', '']) {
        expect(
          finishesOnRejection(ConflictException('x', {'reason': reason})),
          isFalse,
        );
      }
      expect(finishesOnRejection(const ConflictException()), isFalse);
      expect(
        finishesOnRejection(const ServerException(503, 'x', {'reason': 'x'})),
        isFalse,
      );
    });

    test('purchaseAccountToken reads each store\'s own field', () {
      expect(
        purchaseAccountToken(
          applePurchase(appAccountToken: kTestAccountToken),
          PurchaseStore.appStore,
        ),
        kTestAccountToken,
      );
      expect(
        purchaseAccountToken(applePurchase(), PurchaseStore.appStore),
        isNull,
      );
      expect(
        purchaseAccountToken(
          googlePurchase(obfuscatedAccountId: kTestAccountToken),
          PurchaseStore.googlePlay,
        ),
        kTestAccountToken,
      );
      expect(
        purchaseAccountToken(googlePurchase(), PurchaseStore.googlePlay),
        isNull,
      );
    });

    test('IapConfig needs an account_key to deliver or sell', () {
      final ready = IapConfig.fromJson(const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      });
      expect(ready.canDeliver, isTrue);
      expect(ready.sellsTo(testSession()), isTrue);
      expect(ready.sellsTo(testSession(accountKey: 'other')), isFalse);

      final noKey = IapConfig.fromJson(const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
      });
      expect(noKey.canDeliver, isFalse);
      expect(noKey.canPurchase, isFalse);
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
