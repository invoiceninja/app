// A store build refuses a purchase page the DocuNinja embed asks to open (App
// Store 3.1.1(a), Play Payments 4) — and says so, so a tap in the page never
// just does nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/features/docuninja/views/docuninja_builder_screen.dart';

import '../../../_localization_helper.dart';

void main() {
  late ToastController toasts;
  late BuildContext context;
  late List<Uri> launched;

  Future<void> pump(WidgetTester tester) async {
    toasts = ToastController();
    launched = [];
    addTearDown(() {
      toasts.clearAll();
      toasts.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<ToastController>.value(
        value: toasts,
        child: MaterialApp(
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }

  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }

  final checkout = Uri.parse('https://checkout.stripe.com/c/pay/cs_live_x');

  tearDown(() => debugStoreBillingOverride = null);

  testWidgets('a store build refuses a checkout page, with a toast', (
    tester,
  ) async {
    debugStoreBillingOverride = true;
    await pump(tester);

    openDocuNinjaOffApp(context, checkout, launch: launch);
    await tester.pump();

    expect(launched, isEmpty);
    expect(
      toasts.toasts.single.message,
      "This page can't be opened from the app.",
    );
  });

  testWidgets('a store build still opens any other page', (tester) async {
    debugStoreBillingOverride = true;
    await pump(tester);

    final help = Uri.parse('https://invoiceninja.github.io/docs/');
    openDocuNinjaOffApp(context, help, launch: launch);
    await tester.pump();

    expect(launched, [help]);
    expect(toasts.toasts, isEmpty);
  });

  testWidgets('desktop and the web open the checkout', (tester) async {
    debugStoreBillingOverride = false;
    await pump(tester);

    openDocuNinjaOffApp(context, checkout, launch: launch);
    await tester.pump();

    expect(launched, [checkout]);
    expect(toasts.toasts, isEmpty);
  });
}
