// Account Management → Plan, the hosted "Change Plan" card. A store build
// never links to the web billing portal (App Store 3.1.1(a), Play Payments 4),
// manages an in-app plan in the store, and doesn't sell over a web-billed
// plan. Desktop, the web and F-Droid keep the portal button.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/ui/features/settings/views/basic/account_management/plan_screen.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../../../_localization_helper.dart';
import '../../../../../../domain/upgrade/_purchase_fakes.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(this._session);
  final ValueNotifier<AuthSession?> _session;
  @override
  ValueListenable<AuthSession?> get session => _session;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices({required this.auth, this.purchases});
  @override
  final AuthRepository auth;

  @override
  final PurchaseDelivery? purchases;

  @override
  Formatter? formatterIfReady(String companyId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AuthSession _session({
  String plan = '',
  String planExpires = '',
  bool hasIapPlan = false,
  int trialDaysLeft = -1,
  String ninjaPortalUrl =
      'https://invoiceninja.invoicing.co/client/key_login/x',
  bool isOwner = true,
  String userAccountKey = 'acct-key',
}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct',
  accountKey: 'acct-key',
  userAccountKey: userAccountKey,
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
  currentCompanyId: 'co',
  plan: plan,
  planExpires: planExpires,
  hasIapPlan: hasIapPlan,
  trialDaysLeft: trialDaysLeft,
  ninjaPortalUrl: ninjaPortalUrl,
);

final _activeIap = _session(
  plan: 'pro',
  planExpires: '2099-01-01',
  hasIapPlan: true,
);
final _webPaid = _session(plan: 'enterprise', planExpires: '2099-01-01');
final _trial = _session(plan: 'pro', trialDaysLeft: 7);
final _free = _session();

Future<void> _pump(
  WidgetTester tester,
  AuthSession session, {
  required bool storeBuild,
  PurchaseDelivery? purchases,
  AuthRepository? auth,
  bool settle = true,
  bool offered = true,
  bool? open,
}) async {
  debugStoreBillingOverride = storeBuild;
  // Whether the hosted service sells in-app to this account: yes unless a
  // test says otherwise, so the groups below are the card as it has been.
  debugInAppPurchasesOfferedOverride = offered;
  // `purchases_open`: null follows [offered].
  debugInAppStoreOpenOverride = open;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Provider<Services>.value(
        value: _FakeServices(
          auth: auth ?? _FakeAuth(ValueNotifier(session)),
          purchases: purchases,
        ),
        child: const Scaffold(body: AccountManagementPlanScreen()),
      ),
    ),
  );
  // An indeterminate progress bar never settles.
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

const _billedInStore =
    'Your plan is billed through the app store you subscribed in.';
const _billedOnWeb = 'Your plan is managed on the web.';

void main() {
  tearDown(() {
    debugStoreBillingOverride = null;
    debugInAppPurchasesOfferedOverride = null;
    debugInAppStoreOpenOverride = null;
  });

  group('store build', () {
    testWidgets('an active in-app plan gets Manage subscription', (
      tester,
    ) async {
      await _pump(tester, _activeIap, storeBuild: true);

      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Manage Plan'), findsOneWidget); // the card title only
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a web-billed plan says so, with no button to the portal', (
      tester,
    ) async {
      await _pump(tester, _webPaid, storeBuild: true);

      expect(find.text(_billedOnWeb), findsOneWidget);
      expect(find.bySubtype<FilledButton>(), findsNothing);
      expect(find.bySubtype<OutlinedButton>(), findsNothing);
      expect(find.text('Manage subscription'), findsNothing);
    });

    testWidgets('a trial (a web card trial) is billed on the web too', (
      tester,
    ) async {
      await _pump(tester, _trial, storeBuild: true);

      expect(find.text(_billedOnWeb), findsOneWidget);
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a free account gets Upgrade, enabled without a portal URL', (
      tester,
    ) async {
      await _pump(tester, _session(ninjaPortalUrl: ''), storeBuild: true);

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Upgrade Plan'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text(_billedOnWeb), findsNothing);
    });
  });

  // the hosted config offers a Legacy-app Play subscriber a purchase
  // (`replaces_v1_play`), and the server cancels and refunds the Legacy
  // subscription once the new one is applied.
  group('store build, a Legacy Play subscriber', () {
    const legacyNotice =
        'If you subscribe here, your Invoice Ninja Legacy subscription is '
        'cancelled for you once the new one is active, and its unused time is '
        "refunded. You don't need to cancel it yourself.";

    PurchaseDelivery deliveryWith({required bool replaces}) {
      final delivery = PurchaseDelivery(
        apiClient: FakeApi()
          ..iapConfig = {
            'purchases_enabled': true,
            'app_account_token': kTestAccountToken,
            'account_key': 'acct-key',
            'replaces_v1_play': replaces,
          },
        auth: FakeAuth(_activeIap),
        billing: FakeBilling(),
        platform: defaultTargetPlatform,
      );
      addTearDown(delivery.dispose);
      return delivery;
    }

    testWidgets('on Play, the offer gets a plan in this app, the notice, and '
        'the store, each labelled for what it does', (tester) async {
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: deliveryWith(replaces: true),
      );

      expect(find.text(legacyNotice), findsOneWidget);
      // Not "Manage Plan" beside "Manage subscription": the two buttons
      // read the same, and only one of them moves the plan to this app.
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Choose a plan in this app'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button, isA<FilledButton>());
      expect(button.onPressed, isNotNull);
      expect(find.text('Manage in Google Play'), findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
      expect(find.text(_billedInStore), findsNothing);
    });

    testWidgets('offers nothing while the config is asked', (tester) async {
      // A slow answer: Manage subscription, then the offer swapping in under
      // the user's finger, sent a tap meant for one to the other.
      final api = FakeApi()
        ..iapConfig = {
          'purchases_enabled': true,
          'app_account_token': kTestAccountToken,
          'account_key': 'acct-key',
          'replaces_v1_play': true,
        }
        ..getGate = Completer<void>();
      final delivery = PurchaseDelivery(
        apiClient: api,
        auth: FakeAuth(_activeIap),
        billing: FakeBilling(),
        platform: defaultTargetPlatform,
      );
      addTearDown(delivery.dispose);
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: delivery,
        settle: false,
      );

      expect(
        find.byKey(const ValueKey('plan_actions_loading')),
        findsOneWidget,
      );
      expect(find.text('Manage subscription'), findsNothing);
      expect(find.bySubtype<FilledButton>(), findsNothing);

      api.getGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plan_actions_loading')), findsNothing);
      expect(find.text('Choose a plan in this app'), findsOneWidget);
    });

    testWidgets('a config that replaces nothing (a new-app subscriber) '
        'keeps Manage subscription only', (tester) async {
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: deliveryWith(replaces: false),
      );

      expect(find.text(legacyNotice), findsNothing);
      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.bySubtype<FilledButton>(), findsNothing);
    });

    testWidgets('stops offering it once a purchase is delivered', (
      tester,
    ) async {
      final api = FakeApi()
        ..iapConfig = {
          'purchases_enabled': true,
          'app_account_token': kTestAccountToken,
          'account_key': 'acct-key',
          'replaces_v1_play': true,
        };
      final billing = FakeBilling();
      final auth = FakeAuth(_activeIap);
      final delivery = PurchaseDelivery(
        apiClient: api,
        auth: auth,
        billing: billing,
        platform: defaultTargetPlatform,
        timer: FakeTimers().call,
      )..start();
      addTearDown(delivery.dispose);
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: delivery,
        auth: auth,
      );
      expect(find.text(legacyNotice), findsOneWidget);

      // Applied: the server revoked the Legacy subscription, and the
      // refresh hands over a new snapshot of the (unchanged) store plan.
      api.iapConfig = {...api.iapConfig! as Map, 'replaces_v1_play': false};
      billing.purchases.add([googlePurchase()]);
      await tester.pumpAndSettle();
      expect(api.posts, hasLength(1));
      auth.session.value = _activeIap.copyWith();
      await tester.pumpAndSettle();

      expect(find.text(legacyNotice), findsNothing);
      expect(find.text(_billedInStore), findsOneWidget);
    });

    testWidgets('one Upgrade at a time: a second tap while the config is '
        'asked does nothing', (tester) async {
      final api = FakeApi()
        ..iapConfig = {
          'purchases_enabled': true,
          'app_account_token': kTestAccountToken,
          'account_key': 'acct-key',
          'replaces_v1_play': true,
        };
      final auth = FakeAuth(_activeIap);
      final delivery = PurchaseDelivery(
        apiClient: api,
        auth: auth,
        billing: FakeBilling(),
        platform: defaultTargetPlatform,
        timer: FakeTimers().call,
      )..start();
      addTearDown(delivery.dispose);
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: delivery,
        auth: auth,
      );
      final context = tester.element(find.text(legacyNotice));

      // The config is asked afresh (a resume), and is slow to answer.
      api.iapConfig = {...api.iapConfig! as Map, 'replaces_v1_play': false};
      api.getGate = Completer<void>();
      delivery.onAppResumed();
      final first = launchUpgrade(context);
      await tester.pump();
      expect(upgradeInProgress, isTrue);

      var secondDone = false;
      unawaited(launchUpgrade(context).then((_) => secondDone = true));
      await tester.pump();
      expect(secondDone, isTrue);
      expect(upgradeInProgress, isTrue);

      // It replaces nothing now: Manage subscription, and the guard lets go.
      // The config's answer runs on the test's clock; the store page opens
      // through a platform channel, which answers on the real one.
      api.getGate!.complete();
      for (var i = 0; i < 20 && upgradeInProgress; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(upgradeInProgress, isFalse);
      await first;
    });

    testWidgets('the button spins and takes no tap while an Upgrade decides', (
      tester,
    ) async {
      // It can take seconds (the name prompt, the config, the store) before
      // anything shows; a button that looked dead was tapped again.
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: deliveryWith(replaces: true),
      );
      FilledButton button() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('plan_upgrade')),
      );
      expect(button().onPressed, isNotNull);

      upgradeBusy.value = true;
      addTearDown(() => upgradeBusy.value = false);
      await tester.pump();
      expect(button().onPressed, isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plan_upgrade')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      upgradeBusy.value = false;
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('never on an Apple build', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        purchases: deliveryWith(replaces: true),
      );

      expect(find.text(legacyNotice), findsNothing);
      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.bySubtype<FilledButton>(), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('store build, not the owner', () {
    // Which account a purchase lands on is the hosted config's answer, read
    // when the sheet opens; only the owner check is the card's.
    for (final MapEntry(key: name, value: session) in {
      'a member': _session(isOwner: false),
    }.entries) {
      testWidgets('$name gets a disabled Upgrade that says why', (
        tester,
      ) async {
        await _pump(tester, session, storeBuild: true);

        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('Upgrade Plan'),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        expect(button.onPressed, isNull);
        expect(
          find.text('Only the account owner can change the plan.'),
          findsOneWidget,
        );
      });
    }
  });

  // Restore lives outside the purchase sheet too: it only re-delivers what
  // was paid for. Not while the hosted service sells nothing here (below).
  group('Restore Purchases', () {
    final restore = find.byKey(const ValueKey('plan_restore_purchases'));

    for (final MapEntry(key: name, value: session) in {
      'free': _free,
      'active in-app plan': _activeIap,
      'web-billed': _webPaid,
    }.entries) {
      testWidgets('offered to the owner on a store build ($name)', (
        tester,
      ) async {
        await _pump(tester, session, storeBuild: true);
        expect(restore, findsOneWidget);
      });
    }

    testWidgets('asks the store, whatever the delivery\'s config says', (
      tester,
    ) async {
      final billing = FakeBilling();
      final api = FakeApi()
        ..iapConfig = const {'purchases_enabled': false, 'account_key': 'k'};
      final delivery = PurchaseDelivery(
        apiClient: api,
        auth: FakeAuth(),
        billing: billing,
        platform: TargetPlatform.iOS,
      );
      addTearDown(delivery.dispose);
      await _pump(tester, _free, storeBuild: true, purchases: delivery);

      await tester.tap(restore);
      await tester.pump();
      expect(billing.restores, 1);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('not offered to a member', (tester) async {
      await _pump(tester, _session(isOwner: false), storeBuild: true);
      expect(restore, findsNothing);
    });

    testWidgets('not offered off a store build', (tester) async {
      await _pump(tester, _free, storeBuild: false);
      expect(restore, findsNothing);
    });
  });

  // Until the hosted config sells to the account (production before the
  // hosted billing ships), a store build offers no way to buy: the card is
  // left out unless it has a store plan to manage or a web plan to explain.
  group('store build that sells nothing', () {
    Future<void> pumpWithheld(WidgetTester tester, AuthSession s) =>
        _pump(tester, s, storeBuild: true, offered: false);

    final restore = find.byKey(const ValueKey('plan_restore_purchases'));

    for (final MapEntry(key: name, value: session) in {
      'a free owner': _free,
      'a member': _session(isOwner: false),
    }.entries) {
      testWidgets('$name gets no Change Plan card at all', (tester) async {
        await pumpWithheld(tester, session);

        expect(find.text('Manage Plan'), findsNothing);
        expect(find.text('Upgrade Plan'), findsNothing);
        expect(find.byKey(const ValueKey('plan_upgrade')), findsNothing);
        expect(restore, findsNothing);
        expect(
          find.text('Only the account owner can change the plan.'),
          findsNothing,
        );
        // The plan itself is still said.
        expect(find.text('Free'), findsWidgets);
      });
    }

    testWidgets('an active in-app plan keeps Manage subscription, no Restore', (
      tester,
    ) async {
      await pumpWithheld(tester, _activeIap);

      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(restore, findsNothing);
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a lapsed in-app plan is said to have ended, not where to '
        'renew it', (tester) async {
      final ended = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);
      await pumpWithheld(
        tester,
        _session(planExpires: ended, hasIapPlan: true),
      );

      expect(find.text('Your in-app subscription has ended.'), findsOneWidget);
      expect(find.textContaining('renew'), findsNothing);
      expect(restore, findsNothing);
      expect(find.bySubtype<ButtonStyleButton>(), findsNothing);
    });

    for (final MapEntry(key: name, value: session) in {
      'a web-billed plan': _webPaid,
      'a trial': _trial,
    }.entries) {
      testWidgets('$name keeps "managed on the web", no Restore', (
        tester,
      ) async {
        await pumpWithheld(tester, session);

        expect(find.text(_billedOnWeb), findsOneWidget);
        expect(restore, findsNothing);
        expect(find.bySubtype<ButtonStyleButton>(), findsNothing);
      });
    }
  });

  // `purchases_open`: the store sells, though not to this account. Restore is
  // offered (App Review requires one wherever subscriptions are sold), and a
  // member is told only the owner can change the plan; still nothing to buy.
  group('store build, the store open but nothing sold to this account', () {
    Future<void> pumpOpen(WidgetTester tester, AuthSession s) =>
        _pump(tester, s, storeBuild: true, offered: false, open: true);

    final restore = find.byKey(const ValueKey('plan_restore_purchases'));

    testWidgets('an in-app subscriber gets Manage subscription and Restore', (
      tester,
    ) async {
      await pumpOpen(tester, _activeIap);

      expect(find.text('Manage subscription'), findsOneWidget);
      expect(restore, findsOneWidget);
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a web-billed owner gets Restore beside "managed on the web"', (
      tester,
    ) async {
      await pumpOpen(tester, _webPaid);

      expect(find.text(_billedOnWeb), findsOneWidget);
      expect(restore, findsOneWidget);
    });

    testWidgets('an owner sold nothing here gets Restore alone', (
      tester,
    ) async {
      await pumpOpen(tester, _free);

      expect(restore, findsOneWidget);
      expect(find.byKey(const ValueKey('plan_upgrade')), findsNothing);
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a member is told only the owner can change the plan, with '
        'no button', (tester) async {
      await pumpOpen(tester, _session(isOwner: false));

      expect(
        find.text('Only the account owner can change the plan.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('plan_upgrade')), findsNothing);
      expect(restore, findsNothing);
    });

    testWidgets('closed (an older server, a 404): no Restore', (tester) async {
      await _pump(
        tester,
        _activeIap,
        storeBuild: true,
        offered: false,
        open: false,
      );

      expect(find.text('Manage subscription'), findsOneWidget);
      expect(restore, findsNothing);
    });
  });

  group('desktop, web and F-Droid', () {
    testWidgets('an active in-app plan is text only: no Manage, no portal', (
      tester,
    ) async {
      await _pump(tester, _activeIap, storeBuild: false);

      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
      expect(find.bySubtype<FilledButton>(), findsNothing);
      // The old copy told a Mac or web user to "use your phone".
      expect(find.textContaining('phone'), findsNothing);
    });

    testWidgets('a web-billed plan keeps Change Plan to the portal', (
      tester,
    ) async {
      await _pump(tester, _webPaid, storeBuild: false);

      expect(find.text(_billedOnWeb), findsNothing);
      expect(find.text('Manage Plan'), findsNWidgets(2));
    });

    testWidgets('a free account keeps Upgrade Plan', (tester) async {
      await _pump(tester, _free, storeBuild: false);

      expect(find.text('Upgrade Plan'), findsOneWidget);
    });

    testWidgets('the hosted offer changes nothing here', (tester) async {
      await _pump(tester, _free, storeBuild: false, offered: false);

      expect(find.text('Upgrade Plan'), findsOneWidget);
    });

    // The store may still renew a lapsed in-app plan for 60 days: no web plan
    // is sold on top meanwhile.
    testWidgets('an in-app plan that ended recently is not sold a web plan', (
      tester,
    ) async {
      final ended = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);
      await _pump(
        tester,
        _session(planExpires: ended, hasIapPlan: true),
        storeBuild: false,
      );

      expect(
        find.textContaining('Your in-app subscription has ended'),
        findsOneWidget,
      );
      expect(find.bySubtype<FilledButton>(), findsNothing);
    });
  });
}
