// A store purchase refused while no purchase sheet is open is told app-wide,
// in the server's own words under a localized title; nothing else is.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/purchase_notices.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';

import '../_localization_helper.dart';
import '../domain/upgrade/_purchase_fakes.dart';

void main() {
  late FakeBilling billing;
  late FakeApi api;
  late PurchaseDelivery delivery;
  late ToastController toasts;
  BuildContext? context;

  // Built inside the test body, so the purchase stream's callbacks run in
  // the fake-async zone that `pump` drains.
  Future<PurchaseNotices> mount(WidgetTester tester) async {
    billing = FakeBilling();
    api = FakeApi();
    delivery = PurchaseDelivery(
      apiClient: api,
      auth: FakeAuth(),
      billing: billing,
      platform: TargetPlatform.iOS,
    )..start();
    toasts = ToastController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final notices = PurchaseNotices(
      delivery: delivery,
      toasts: toasts,
      contextOf: () => context,
    );
    addTearDown(() async {
      await notices.dispose();
      toasts.clearAll();
      toasts.dispose();
      await delivery.dispose();
    });
    return notices;
  }

  testWidgets('a refusal in the background is told with the server message', (
    tester,
  ) async {
    await mount(tester);
    api.postError = const ConflictException(
      'Test purchases are not applied to this account.',
      {'reason': 'sandbox'},
    );

    billing.purchases.add([applePurchase()]);
    await tester.pump();

    final toast = toasts.toasts.single;
    expect(toast.message, "Your purchase wasn't applied to this account.");
    expect(toast.detail, 'Test purchases are not applied to this account.');
  });

  testWidgets('an open purchase sheet tells it instead', (tester) async {
    await mount(tester);
    final release = delivery.holdSheet();
    addTearDown(release);
    api.postError = const ConflictException('Linked', {'reason': 'linked'});

    billing.purchases.add([applePurchase()]);
    await tester.pump();

    expect(toasts.toasts, isEmpty);
  });

  testWidgets('a renewal applied in the background, or one left for the next '
      'launch, says nothing', (tester) async {
    await mount(tester);

    billing.purchases.add([applePurchase()]);
    await tester.pump();
    api.postError = const ServerException(503, 'Service Unavailable');
    billing.purchases.add([applePurchase()]);
    await tester.pump();

    expect(api.posts, hasLength(2));
    expect(toasts.toasts, isEmpty);
  });
}
