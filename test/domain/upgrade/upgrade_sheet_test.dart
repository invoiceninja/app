// The purchase sheet's disclosure — App Review 3.1.2 / Schedule 2 and Play's
// subscriptions policy want each plan's name, its billing period and the
// billed amount, the store's auto-renew and cancel terms, and the privacy
// policy and terms next to the buy buttons — and the sheet closing once a
// purchase is applied.

import 'package:flutter/rendering.dart';
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
  }) async {
    billing = FakeBilling();
    api = FakeApi();
    final auth = FakeAuth();
    delivery = PurchaseDelivery(
      apiClient: api,
      auth: auth,
      billing: billing,
      platform: platform,
    )..start();
    svc = PurchaseService(apiClient: api, auth: auth, delivery: delivery);
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
}
