// The app-lifetime delivery of paid store purchases to the hosted service
// (`POST /api/admin/subscription`), and the response contract it follows.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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

  PurchaseDelivery build(
    TargetPlatform platform, {
    FakeAuth? withAuth,
    DateTime Function()? now,
  }) {
    final delivery = PurchaseDelivery(
      apiClient: api,
      auth: withAuth ?? auth,
      billing: billing,
      platform: platform,
      timer: timers.call,
      now: now,
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

    // The hosted endpoint requires `inapp_transaction_id`
    // (InitialPurchaseRequest): a post without it is a 422.
    test('Google with no order id yet is not posted, not acknowledged, and '
        'logged once', () async {
      final warnings = <String>[];
      final sub = Logger.root.onRecord
          .where((r) => r.level >= Level.WARNING)
          .listen((r) => warnings.add(r.message));
      addTearDown(sub.cancel);
      build(TargetPlatform.android).start();
      final p = googlePurchase(orderId: null);
      await emit(p);
      await emit(p);

      expect(api.posts, isEmpty);
      // Play refunds it if it never gets an order id.
      expect(billing.completed, isEmpty);
      expect(kinds(), [
        PurchaseActivityKind.retryLater,
        PurchaseActivityKind.retryLater,
      ]);
      expect(
        warnings.where((m) => m.contains('no transaction id')),
        hasLength(1),
      );
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

    test('a purchase under another token, with the config naming one, says '
        'it is not applied yet, so an open sheet is not left busy', () async {
      build(TargetPlatform.iOS).start();
      await emit(
        applePurchase(appAccountToken: '11111111-2222-3333-4444-555555555555'),
      );

      expect(api.posts, isEmpty);
      expect(kinds(), [PurchaseActivityKind.retryLater]);
    });

    for (final (name, config) in [
      (
        'no token',
        const <String, Object?>{
          'purchases_enabled': false,
          'account_key': 'acct-key',
        },
      ),
      (
        'a non-UUID token',
        const <String, Object?>{
          'purchases_enabled': true,
          'app_account_token': 'not-a-uuid',
          'account_key': 'acct-key',
        },
      ),
    ]) {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        test('a config with $name still delivers a purchase that carries a '
            'token (${platform.name}): purchases_enabled gates only the '
            'sale', () async {
          api.iapConfig = config;
          build(platform).start();
          await emit(
            platform == TargetPlatform.iOS
                ? applePurchase(appAccountToken: kTestAccountToken)
                : googlePurchase(obfuscatedAccountId: kTestAccountToken),
          );

          expect(api.posts, hasLength(1));
          expect(kinds().last, PurchaseActivityKind.applied);
        });
      }
    }

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
  // `replaces_v1_play` answers for the plan the account had when it was
  // asked: once a purchase is delivered (it replaced that plan) or the plan
  // changes, the kept answer must not sell over the new store plan.
  group('the config after the plan changes', () {
    Map<String, Object?> configWith({required bool replaces}) => {
      'purchases_enabled': true,
      'app_account_token': kTestAccountToken,
      'account_key': 'acct-key',
      'replaces_v1_play': replaces,
    };

    test('a delivered purchase drops the kept offer, and asks nothing more '
        'to deliver the next', () async {
      api.iapConfig = configWith(replaces: true);
      final delivery = build(TargetPlatform.android)..start();
      expect((await delivery.config())!.replacesLegacyPlay, isTrue);
      final asked = api.gets.length;

      await emit(googlePurchase());
      expect(kinds(), contains(PurchaseActivityKind.applied));

      final after = (await delivery.config())!;
      expect(after.replacesLegacyPlay, isFalse);
      expect(after.accountKey, 'acct-key');
      expect(after.appAccountToken, kTestAccountToken);
      expect(api.gets.length, asked);
    });

    test('an answer asked before the delivery landed is never kept, and '
        'never offers the replacement', () async {
      api.iapConfig = configWith(replaces: true);
      final delivery = build(TargetPlatform.android)..start();
      await delivery.config();

      // The Play dialog closes (a resume) while the purchase is posted: the
      // resume's config request answers for the Legacy plan.
      api.postGate = Completer<void>();
      await emit(googlePurchase());
      api.getGate = Completer<void>();
      delivery.onAppResumed();
      final early = delivery.config();
      await pumpEventQueue();

      api.postGate!.complete();
      await pumpEventQueue();
      expect(kinds(), contains(PurchaseActivityKind.applied));

      api.iapConfig = configWith(replaces: false);
      api.getGate!.complete();
      api.getGate = null;
      expect((await early)?.replacesLegacyPlay ?? false, isFalse);

      final asked = api.gets.length;
      expect((await delivery.config())!.replacesLegacyPlay, isFalse);
      expect(api.gets.length, asked + 1);
    });

    test("a change of the session's store plan forgets it", () async {
      api.iapConfig = configWith(replaces: true);
      final delivery = build(TargetPlatform.android)..start();
      await delivery.config();
      final asked = api.gets.length;

      // The same plan, a fresh snapshot: kept.
      auth.session.value = auth.session.value!.copyWith();
      await delivery.config();
      expect(api.gets.length, asked);

      api.iapConfig = configWith(replaces: false);
      auth.session.value = auth.session.value!.copyWith(
        plan: 'enterprise',
        hasIapPlan: true,
        planExpires: '2099-01-01',
      );
      expect((await delivery.config())!.replacesLegacyPlay, isFalse);
      expect(api.gets.length, asked + 1);
    });
  });

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

            // Asked at sign-in (whether purchases are offered), and again
            // for the purchase: a failure is never kept.
            expect(api.gets, [
              '/api/admin/iap/config',
              '/api/admin/iap/config',
            ]);
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
      await emit(applePurchase(transactionId: 't1'));
      await emit(applePurchase(transactionId: 't2'));
      expect(api.gets, hasLength(1));
      expect(api.posts, hasLength(2));

      // A refresh of the same user and company: the same config.
      auth.session.value = testSession();
      await pumpEventQueue();
      await emit(applePurchase(transactionId: 't3'));
      expect(api.gets, hasLength(1));

      // The server answers for the token's company: another company is
      // asked afresh.
      auth.session.value = testSession(companyId: 'co2');
      await pumpEventQueue();
      await emit(applePurchase(transactionId: 't4'));
      expect(api.gets, hasLength(2));

      auth.session.value = testSession(userId: 'someone-else');
      await pumpEventQueue();
      await emit(applePurchase(transactionId: 't5'));
      expect(api.gets, hasLength(3));
    });

    test('a company with no account_key, then one with it: the switch sweeps '
        'and delivers', () async {
      // Not the owner here, or a company of another account.
      api.iapConfig = const {'purchases_enabled': false};
      final p = applePurchase();
      billing.unfinished = [p];
      build(TargetPlatform.iOS).start();
      await pumpEventQueue();
      expect(api.posts, isEmpty);

      api.iapConfig = const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      };
      auth.session.value = testSession(companyId: 'my-own-co');
      await pumpEventQueue();
      expect(api.gets, hasLength(2));
      expect(api.posts, hasLength(1));
      expect(billing.completed, [p]);
    });

    test('a 200 with no account_key is kept, not asked again on a timer, '
        'until the app returns to the foreground', () async {
      api.iapConfig = const {'purchases_enabled': false};
      final p = googlePurchase();
      billing.unfinished = [p];
      final delivery = build(TargetPlatform.android)..start();
      await pumpEventQueue();
      await emit(p);
      await emit(p);

      expect(api.gets, hasLength(1));
      expect(timers.scheduled, isEmpty);
      expect(api.posts, isEmpty);
      expect(billing.completed, isEmpty);
      expect(kinds().toSet(), {PurchaseActivityKind.retryLater});

      delivery.onAppResumed();
      await pumpEventQueue();
      expect(api.gets, hasLength(2));
      expect(timers.scheduled, isEmpty);
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
      // The sign-in's ask and the first purchase's failed; the second asks.
      expect(api.gets, hasLength(3));
      expect(api.posts, hasLength(1));
    });

    test('asked afresh after a sign-out and back in', () async {
      build(TargetPlatform.iOS).start();
      await emit(applePurchase(transactionId: 't1'));
      expect(api.gets, hasLength(1));

      auth.session.value = null;
      await pumpEventQueue();
      auth.session.value = testSession();
      await pumpEventQueue();
      await emit(applePurchase(transactionId: 't2'));
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

    test('a switch to another company sweeps again, but never re-posts what '
        'was applied', () async {
      billing.unfinished = [applePurchase()];
      auth.session.value = testSession(accountKey: 'my-acct');
      build(TargetPlatform.iOS).start();
      await pumpEventQueue();
      expect(api.posts, hasLength(1));

      auth.session.value = testSession(
        accountKey: 'company-acct',
        companyId: 'their-co',
      );
      await pumpEventQueue();
      expect(api.posts, hasLength(1));
    });

    test('a switch to another company re-posts a refusal left with the '
        'store', () async {
      api.postError = const ConflictException(
        'This purchase was posted for another account.',
        {'reason': 'account'},
      );
      billing.unfinished = [applePurchase()];
      build(TargetPlatform.iOS).start();
      await pumpEventQueue();
      expect(api.posts, hasLength(1));

      api.postError = null;
      auth.session.value = testSession(companyId: 'my-own-co');
      await pumpEventQueue();
      expect(api.posts, hasLength(2));
      expect(kinds().last, PurchaseActivityKind.applied);
    });
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

    test('a purchase applied but not acknowledged retries only the '
        'acknowledgement, with the backoff growing', () async {
      billing.completeResult = false;
      final p = googlePurchase();
      build(TargetPlatform.android).start();
      await emit(p);
      expect(api.posts, hasLength(1));
      expect(auth.refreshes, 1);

      // Play still lists it as unacknowledged.
      billing.unfinished = [p];
      for (var i = 0; i < 3; i++) {
        timers.fireLast();
        await pumpEventQueue();
      }
      // Never posted again, never refreshed again, nothing said again.
      expect(api.posts, hasLength(1));
      expect(auth.refreshes, 1);
      expect(billing.completed, hasLength(4));
      expect(timers.delays, const [
        Duration(seconds: 30),
        Duration(minutes: 2),
        Duration(minutes: 10),
        Duration(minutes: 10),
      ]);
      expect(kinds(), [
        PurchaseActivityKind.delivering,
        PurchaseActivityKind.applied,
      ]);

      // Play confirms: no more retries.
      billing.completeResult = true;
      timers.fireLast();
      await pumpEventQueue();
      expect(billing.completed, hasLength(5));
      expect(timers.scheduled, hasLength(4));
      expect(api.posts, hasLength(1));
    });
  });

  // A refusal that leaves the purchase with the store (Apple's with a reason
  // that may change, every Google one) must not be posted, and said, on every
  // return to the foreground.
  group('a refusal left with the store', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      StorePurchase purchase() =>
          platform == TargetPlatform.iOS ? applePurchase() : googlePurchase();

      test('${platform.name}: not re-posted on resume or a retry, re-posted '
          'quietly on a sign-in and on Restore, said once', () async {
        api.postError = const ConflictException('Bought for another account.', {
          'reason': 'token_mismatch',
        });
        final p = purchase();
        billing.unfinished = [p];
        final delivery = build(platform)..start();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));
        expect(
          kinds().where((k) => k == PurchaseActivityKind.rejected),
          hasLength(1),
        );

        for (var i = 0; i < 3; i++) {
          delivery.onAppResumed();
          await pumpEventQueue();
        }
        expect(api.posts, hasLength(1));

        // A retry scheduled for something else sweeps it past, too.
        billing.unfinished = [p, googlePurchase(orderId: null)];
        delivery.onAppResumed();
        await pumpEventQueue();
        timers.fireLast();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));
        billing.unfinished = [p];

        // A sign-in sweeps it again: the server's answer may have changed.
        auth.session.value = null;
        await pumpEventQueue();
        auth.session.value = testSession();
        await pumpEventQueue();
        expect(api.posts, hasLength(2));

        // Restore hands it back on the purchase stream.
        await emit(
          platform == TargetPlatform.iOS
              ? applePurchase(status: StorePurchaseStatus.restored)
              : googlePurchase(status: StorePurchaseStatus.restored),
        );
        expect(api.posts, hasLength(3));

        // Said once, and not even "delivering" on the quiet re-posts.
        for (final kind in [
          PurchaseActivityKind.delivering,
          PurchaseActivityKind.rejected,
        ]) {
          expect(
            kinds().where((k) => k == kind),
            hasLength(1),
            reason: '$kind',
          );
        }
        expect(billing.completed, isEmpty);
      });
    }

    test('a re-post the server then applies is said', () async {
      api.postError = const ConflictException('No account token.', {
        'reason': 'no_token',
      });
      billing.unfinished = [applePurchase()];
      build(TargetPlatform.iOS).start();
      await pumpEventQueue();

      api.postError = null;
      auth.session.value = null;
      await pumpEventQueue();
      auth.session.value = testSession();
      await pumpEventQueue();
      expect(api.posts, hasLength(2));
      expect(kinds(), [
        PurchaseActivityKind.delivering,
        PurchaseActivityKind.rejected,
        PurchaseActivityKind.applied,
      ]);
    });

    test('another user is told about their own refusal', () async {
      api.postError = const ConflictException('Posted for another account.', {
        'reason': 'account',
      });
      billing.unfinished = [applePurchase()];
      build(TargetPlatform.iOS).start();
      await pumpEventQueue();

      auth.session.value = testSession(userId: 'someone-else');
      await pumpEventQueue();
      expect(api.posts, hasLength(2));
      expect(
        kinds().where((k) => k == PurchaseActivityKind.rejected),
        hasLength(2),
      );
    });
  });

  // Closing the StoreKit / Play sheet resumes the app, so the resume sweep and
  // the purchase stream hand over the same transaction.
  group('the purchase sheet closing', () {
    test('a resume sweep after the stream applied it posts nothing', () async {
      final delivery = build(TargetPlatform.iOS)..start();
      await pumpEventQueue();
      final p = applePurchase();
      await emit(p);
      expect(api.posts, hasLength(1));

      // The store's list was read before the finish landed; a re-post would
      // be refused as `linked` and say "not applied" right after success.
      api.postError = const ConflictException('Already linked.', {
        'reason': 'linked',
      });
      billing.unfinished = [p];
      delivery.onAppResumed();
      await pumpEventQueue();

      expect(api.posts, hasLength(1));
      expect(auth.refreshes, 1);
      expect(kinds(), [
        PurchaseActivityKind.delivering,
        PurchaseActivityKind.applied,
      ]);
    });

    test('the stream handing it over after the resume sweep applied it posts '
        'nothing', () async {
      final delivery = build(TargetPlatform.android)..start();
      await pumpEventQueue();
      final p = googlePurchase();
      billing.unfinished = [p];
      api.postGate = Completer<void>();
      delivery.onAppResumed();
      await pumpEventQueue();
      expect(api.posts, hasLength(1));

      // While the sweep's post is out, and again after it was applied.
      billing.purchases.add([p]);
      await pumpEventQueue();
      api.postGate!.complete();
      await pumpEventQueue();
      await emit(p);

      expect(api.posts, hasLength(1));
      expect(auth.refreshes, 1);
      expect(billing.completed, [p]);
      expect(
        kinds().where((k) => k == PurchaseActivityKind.applied),
        hasLength(1),
      );
    });

    test('a renewal is a new transaction and is posted', () async {
      build(TargetPlatform.iOS).start();
      await emit(applePurchase(transactionId: 't1'));
      await emit(applePurchase(transactionId: 't2'));
      expect(api.posts, hasLength(2));
    });
  });

  group('from app start', () {
    test(
      'sweeps again after a sign-out and back in to the same account',
      () async {
        billing.unfinished = [applePurchase(transactionId: 't1')];
        build(TargetPlatform.iOS).start();
        await pumpEventQueue();
        expect(api.posts, hasLength(1));

        auth.session.value = null;
        await pumpEventQueue();
        billing.unfinished = [applePurchase(transactionId: 't2')];
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
      billing.unfinished = [applePurchase(transactionId: 'theirs')];
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
  // Whether a store build shows any way to buy (docs/in-app-purchases.md, "A
  // store build launches without purchases"): the hosted config's yes for
  // the active account, asked at sign-in and on a company switch, and false
  // on anything less.
  group('purchase offer', () {
    test('false until started, then the config\'s yes', () async {
      final delivery = build(TargetPlatform.iOS);
      expect(delivery.offer.offered, isFalse);
      delivery.start();
      expect(delivery.offer.offered, isFalse);
      await pumpEventQueue();
      expect(delivery.offer.offered, isTrue);
      expect(api.gets, ['/api/admin/iap/config']);
    });

    final noes = <String, Object?>{
      '404 (production before the hosted billing)': const ServerException(
        404,
        'Route does not exist',
      ),
      '500': const ServerException(500, 'Server Error'),
      'network': const NetworkException('offline'),
      'switched off': const {
        'purchases_enabled': false,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      },
      'a non-owner (no account_key)': const {'purchases_enabled': false},
      'no token': const {'purchases_enabled': true, 'account_key': 'acct-key'},
      "another account's key": const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
        'account_key': 'their-acct',
      },
    };
    for (final MapEntry(key: why, value: answer) in noes.entries) {
      test('not offered: $why', () async {
        api.iapConfig = answer;
        final delivery = build(TargetPlatform.android)..start();
        await pumpEventQueue();
        expect(delivery.offer.offered, isFalse);
      });
    }

    test('another company is not offered until its own answer', () async {
      final delivery = build(TargetPlatform.iOS)..start();
      await pumpEventQueue();
      expect(delivery.offer.offered, isTrue);

      final gate = api.getGate = Completer<void>();
      auth.session.value = testSession(companyId: 'co2');
      expect(delivery.offer.offered, isFalse);
      gate.complete();
      await pumpEventQueue();
      expect(delivery.offer.offered, isTrue);
      expect(api.gets, hasLength(2));
    });

    test('a refresh of the same session asks nothing more', () async {
      final delivery = build(TargetPlatform.iOS)..start();
      await pumpEventQueue();
      auth.session.value = testSession();
      await pumpEventQueue();
      expect(delivery.offer.offered, isTrue);
      expect(api.gets, hasLength(1));
      // The session now names another account: not sold to, no request.
      auth.session.value = testSession(accountKey: 'their-acct');
      await pumpEventQueue();
      expect(delivery.offer.offered, isFalse);
      expect(api.gets, hasLength(1));
    });

    test('a sign-out withdraws it', () async {
      final delivery = build(TargetPlatform.iOS)..start();
      await pumpEventQueue();
      auth.session.value = null;
      await pumpEventQueue();
      expect(delivery.offer.offered, isFalse);
    });

    test('a resume asks again only once the answer is old', () async {
      var clock = DateTime.utc(2026, 11, 23, 12);
      final delivery = build(TargetPlatform.iOS, now: () => clock)..start();
      await pumpEventQueue();
      expect(api.gets, hasLength(1));

      clock = clock.add(const Duration(minutes: 5));
      delivery.onAppResumed();
      await pumpEventQueue();
      expect(api.gets, hasLength(1));

      // Support switched purchases off.
      api.iapConfig = const {
        'purchases_enabled': false,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      };
      clock = clock.add(kPurchaseOfferMaxAge);
      delivery.onAppResumed();
      await pumpEventQueue();
      expect(api.gets, hasLength(2));
      expect(delivery.offer.offered, isFalse);
    });

    test('a failed ask is retried on the next resume, and a failure keeps '
        'the last answer', () async {
      var clock = DateTime.utc(2026, 11, 23, 12);
      api.iapConfig = const NetworkException('offline');
      final delivery = build(TargetPlatform.iOS, now: () => clock)..start();
      await pumpEventQueue();
      expect(delivery.offer.offered, isFalse);

      api.iapConfig = const {
        'purchases_enabled': true,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      };
      delivery.onAppResumed();
      await pumpEventQueue();
      expect(api.gets, hasLength(2));
      expect(delivery.offer.offered, isTrue);

      // Offline an hour later: the yes for this user and company stands.
      api.iapConfig = const NetworkException('offline');
      clock = clock.add(const Duration(hours: 1));
      delivery.onAppResumed();
      await pumpEventQueue();
      expect(api.gets, hasLength(3));
      expect(delivery.offer.offered, isTrue);
    });

    test('a change of the store plan asks again', () async {
      final delivery = build(TargetPlatform.android)..start();
      await pumpEventQueue();
      expect(delivery.offer.offered, isTrue);

      // A purchase applied: the server no longer sells over the live plan.
      api.iapConfig = const {
        'purchases_enabled': false,
        'app_account_token': kTestAccountToken,
        'account_key': 'acct-key',
      };
      auth.session.value = testSession().copyWith(
        plan: 'pro',
        planExpires: '2099-01-01',
        hasIapPlan: true,
      );
      await pumpEventQueue();
      expect(api.gets, hasLength(2));
      expect(delivery.offer.offered, isFalse);
    });

    test('notifies only on a change', () async {
      final delivery = build(TargetPlatform.iOS);
      var notes = 0;
      delivery.offer.addListener(() => notes++);
      delivery.start();
      await pumpEventQueue();
      auth.session.value = testSession();
      await pumpEventQueue();
      expect(notes, 1);
    });
  });
}
