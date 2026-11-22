// The purchase sheet's disclosure — App Review 3.1.2 / Schedule 2 and Play's
// subscriptions policy want each plan's name, its billing period and the
// billed amount, the store's auto-renew and cancel terms, and the privacy
// policy and terms next to the buy buttons — and the sheet closing once a
// purchase is applied.

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/domain/upgrade/purchase_service.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';

import '../../_localization_helper.dart';
import '_purchase_fakes.dart';

const _appleTerms =
    'Subscriptions renew automatically at the price shown until cancelled. '
    'Cancel at least 24 hours before renewal in your Apple Account '
    'subscription settings.';
const _googleTerms =
    'Subscriptions renew automatically at the price shown until cancelled. '
    'Cancel at least 24 hours before renewal in your Google Play '
    'subscription settings.';

void main() {
  late FakeBilling billing;
  late FakeApi api;
  late PurchaseDelivery delivery;
  late PurchaseService svc;
  late ToastController toasts;

  Future<void> openSheet(
    WidgetTester tester,
    TargetPlatform platform, {
    bool alreadySubscribed = false,
    bool replacesLegacyPlay = false,
  }) async {
    billing = FakeBilling();
    api = FakeApi();
    final auth = FakeAuth();
    delivery = PurchaseDelivery(
      apiClient: api,
      auth: auth,
      billing: billing,
      platform: platform,
      // Retries are fired by hand; a real 30 s timer would outlive the test.
      timer: FakeTimers().call,
    )..start();
    svc = PurchaseService(auth: auth, delivery: delivery);
    toasts = ToastController();
    await svc.loadConfig();
    await svc.init();
    addTearDown(() async {
      toasts.clearAll();
      toasts.dispose();
      await svc.dispose();
      await delivery.dispose();
    });

    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<ToastController>.value(
        value: toasts,
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => UpgradeSheet(
                    service: svc,
                    store: delivery.store,
                    alreadySubscribed: alreadySubscribed,
                    replacesLegacyPlay: replacesLegacyPlay,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('${platform.name}: each plan with its period and price, '
        "Apple's renewal terms, and the legal links", (tester) async {
      await openSheet(tester, platform);

      expect(find.byType(UpgradeSheet), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('Billed monthly'), findsOneWidget);
      expect(find.text(r'$12.00'), findsOneWidget);
      expect(find.text('Enterprise (5 users)'), findsOneWidget);
      expect(find.text('Billed yearly'), findsOneWidget);
      expect(find.text(r'$180.00'), findsOneWidget);

      expect(find.text(_appleTerms), findsOneWidget);
      expect(find.textContaining('Google'), findsNothing);

      expect(
        find.byKey(const ValueKey('legal_privacy_policy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('legal_terms_of_service')),
        findsOneWidget,
      );
      expect(find.text('Restore Purchases'), findsOneWidget);
      expect(
        find.text('Restore brings back purchases made in this app.'),
        findsOneWidget,
      );
    });
  }

  testWidgets("android: Google's renewal terms, never Apple's", (tester) async {
    await openSheet(tester, TargetPlatform.android);

    expect(find.text(_googleTerms), findsOneWidget);
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.byKey(const ValueKey('legal_privacy_policy')), findsOneWidget);
  });

  // a Legacy-app Play subscriber's purchase replaces that subscription.
  const legacyNotice =
      'If you subscribe here, your Invoice Ninja Legacy subscription is '
      'cancelled for you once the new one is active, and its unused time is '
      "refunded. You don't need to cancel it yourself.";

  testWidgets('a purchase that replaces a Legacy Play subscription says it is '
      'cancelled and refunded, above the plans', (tester) async {
    await openSheet(tester, TargetPlatform.android, replacesLegacyPlay: true);

    expect(find.text(legacyNotice), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text(_googleTerms), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(legacyNotice)).dy,
      lessThan(tester.getTopLeft(find.text('Pro')).dy),
    );
  });

  testWidgets('no Legacy notice on any other sale', (tester) async {
    await openSheet(tester, TargetPlatform.android);
    expect(
      find.byKey(const ValueKey('store_replaces_legacy_play')),
      findsNothing,
    );
  });

  testWidgets('the billed amount is the most prominent figure on a plan', (
    tester,
  ) async {
    await openSheet(tester, TargetPlatform.iOS);

    double sizeOf(String text) => tester
        .renderObject<RenderParagraph>(find.text(text))
        .text
        .style!
        .fontSize!;
    expect(sizeOf(r'$12.00'), greaterThan(sizeOf('Billed monthly')));
    expect(sizeOf(r'$12.00'), greaterThanOrEqualTo(sizeOf('Pro')));
  });

  testWidgets('tapping a plan buys it, tied to the account', (tester) async {
    await openSheet(tester, TargetPlatform.android);

    await tester.tap(find.text('Pro'));
    await tester.pump();

    expect(billing.bought.single.$1.id, 'pro_plan');
    expect(billing.bought.single.$2, kTestAccountToken);
  });

  testWidgets('closes once a purchase is applied (200)', (tester) async {
    await openSheet(tester, TargetPlatform.iOS);

    billing.purchases.add([applePurchase()]);
    await tester.pumpAndSettle();

    expect(api.posts, hasLength(1));
    expect(find.byType(UpgradeSheet), findsNothing);
    expect(
      toasts.toasts.map((t) => t.message),
      contains('Thank you for your purchase!'),
    );
  });

  testWidgets('stays open on a refusal, and says why', (tester) async {
    await openSheet(tester, TargetPlatform.iOS);
    api.postError = const ConflictException(
      'Test purchases are not applied to this account.',
      {'reason': 'sandbox'},
    );

    billing.purchases.add([applePurchase()]);
    await tester.pumpAndSettle();

    expect(find.byType(UpgradeSheet), findsOneWidget);
    final toast = toasts.toasts.single;
    expect(toast.message, "Your purchase wasn't applied to this account.");
    expect(toast.detail, 'Test purchases are not applied to this account.');
  });

  testWidgets('a purchase the store refuses to start says so', (tester) async {
    await openSheet(tester, TargetPlatform.iOS);
    billing.buyError = PlatformException(
      code: 'storekit_duplicate_product_object',
      message: 'There is a pending transaction for the same product.',
    );

    await tester.tap(find.text('Pro'));
    await tester.pumpAndSettle();

    final toast = toasts.toasts.single;
    expect(toast.message, "The store couldn't complete the purchase.");
    expect(svc.busy.value, isFalse);
  });

  testWidgets('"applied later" is said once, however many tries fail', (
    tester,
  ) async {
    await openSheet(tester, TargetPlatform.iOS);
    api.postError = const ServerException(500, 'Server Error');

    billing.purchases.add([applePurchase()]);
    await tester.pumpAndSettle();
    billing.purchases.add([applePurchase()]);
    await tester.pumpAndSettle();

    expect(api.posts, hasLength(2));
    expect(toasts.toasts, hasLength(1));
    expect(find.byType(UpgradeSheet), findsOneWidget);
  });

  testWidgets('an Apple Account that already subscribes is offered Restore, '
      'not plans', (tester) async {
    await openSheet(tester, TargetPlatform.iOS, alreadySubscribed: true);

    expect(
      find.textContaining('already has an Invoice Ninja subscription'),
      findsOneWidget,
    );
    expect(find.text('Pro'), findsNothing);
    expect(find.text('Restore Purchases'), findsOneWidget);

    await tester.tap(find.text('Restore Purchases'));
    await tester.pump();
    expect(billing.restores, 1);
  });

  testWidgets('a Google account that already subscribes is told so in '
      "Google's words, and offered Restore, not plans", (tester) async {
    await openSheet(tester, TargetPlatform.android, alreadySubscribed: true);

    expect(
      find.text(
        'This Google account already has an Invoice Ninja subscription, so '
        "another one can't be bought here. If it was bought for this "
        'account, restore it.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.text('Pro'), findsNothing);
    expect(find.text('Restore Purchases'), findsOneWidget);
  });

  testWidgets('the title is announced as a heading', (tester) async {
    await openSheet(tester, TargetPlatform.iOS);

    final semantics = tester.widget<Semantics>(
      find
          .ancestor(of: find.text('Upgrade'), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics.properties.header, isTrue);
    expect(semantics.properties.headingLevel, 1);
  });

  testWidgets('a price reads left-to-right in a right-to-left language', (
    tester,
  ) async {
    await openSheet(tester, TargetPlatform.iOS);
    // Rebuild the open sheet under an RTL ambient direction.
    await tester.pumpWidget(
      ChangeNotifierProvider<ToastController>.value(
        value: toasts,
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: UpgradeSheet(service: svc, store: delivery.store),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final price = tester.widget<Text>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Directionality && w.textDirection == TextDirection.rtl,
        ),
        matching: find.text(r'$12.00'),
      ),
    );
    expect(price.textDirection, TextDirection.ltr);
  });
}
