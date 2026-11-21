// A plan is bought for the whole account, so only the owner of the active
// company's account is offered the in-app purchase sheet; anyone else lands on
// the Plan screen.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';

import '_purchase_fakes.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(AuthSession s) : sess = ValueNotifier(s);

  final ValueNotifier<AuthSession?> sess;

  @override
  ValueListenable<AuthSession?> get session => sess;

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Only `auth` is real: the purchase sheet reaching for anything else (its
/// `apiClient`) throws, which is what a non-owner must never get to.
class _FakeServices implements Services {
  _FakeServices(this.auth);

  @override
  final AuthRepository auth;

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

AuthSession _session({required bool isOwner}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct_other',
  currentCompanyId: 'co_other',
  userId: 'u1',
  userFirstName: 'Ada',
  userLastName: 'Lovelace',
  companies: [
    AuthCompany(
      id: 'co_other',
      name: 'Other',
      displayName: 'Other',
      permissions: '',
      isAdmin: isOwner,
      isOwner: isOwner,
    ),
  ],
);

void main() {
  testWidgets('a member of a free account gets the Plan screen, not the '
      'purchase sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => launchUpgrade(context),
              child: const Text('upgrade'),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/account_management',
          builder: (_, _) => const Scaffold(body: Text('plan screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      Provider<Services>.value(
        value: _FakeServices(_FakeAuth(_session(isOwner: false))),
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('upgrade'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('plan screen'), findsOneWidget);
  });

  // The hosted config can change where Upgrade goes only for an owner's
  // active store plan on a Play build (`replaces_v1_play`): nobody else
  // waits for it, and a slow answer is no (the plan is managed in the store).
  group('replacementConfigFor', () {
    AuthSession storePlan({bool isOwner = true}) => AuthSession(
      baseUrl: 'https://invoicing.co',
      isHosted: true,
      accountId: 'acct',
      accountKey: 'acct-key',
      userAccountKey: 'acct-key',
      currentCompanyId: 'co',
      userId: 'me',
      plan: 'pro',
      planExpires: '2099-01-01',
      hasIapPlan: true,
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

    late FakeApi api;
    late PurchaseDelivery delivery;

    setUp(() {
      api = FakeApi()
        ..iapConfig = {
          'purchases_enabled': true,
          'app_account_token': kTestAccountToken,
          'account_key': 'acct-key',
          'replaces_v1_play': true,
        };
      delivery = PurchaseDelivery(
        apiClient: api,
        auth: FakeAuth(storePlan()),
        billing: FakeBilling(),
        platform: TargetPlatform.android,
      );
    });
    tearDown(() => delivery.dispose());

    Future<IapConfig?> ask({
      AuthSession? session,
      PurchaseStore? store = PurchaseStore.googlePlay,
      bool storeBilling = true,
      Duration timeout = kUpgradeConfigTimeout,
    }) => replacementConfigFor(
      storeBilling: storeBilling,
      store: store,
      session: session ?? storePlan(),
      purchases: () => delivery,
      timeout: timeout,
    );

    test("an owner's store plan on Play asks", () async {
      expect((await ask())!.replacesLegacyPlay, isTrue);
      expect(api.gets, hasLength(1));
    });

    test(
      'a non-owner, an Apple build or a non-store build never asks',
      () async {
        expect(await ask(session: storePlan(isOwner: false)), isNull);
        expect(await ask(store: PurchaseStore.appStore), isNull);
        expect(await ask(storeBilling: false), isNull);
        expect(api.gets, isEmpty);
      },
    );

    test('no answer in time is no', () async {
      api.getGate = Completer<void>();
      expect(await ask(timeout: const Duration(milliseconds: 20)), isNull);
      api.getGate!.complete();
    });
  });
}
