import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/domain/gateway_constants.dart';
import 'package:admin/ui/features/gateways/views/company_gateway_edit_screen.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_offer.dart';
import 'package:admin/ui/features/terminal/views/tap_to_pay_enable_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import '../shell/_shell_test_helpers.dart';
import '_terminal_fakes.dart';

/// Tap to Pay on iPhone at the end of Stripe onboarding (App Review 3.4):
/// offered only where it can be finished — nothing changes for anyone else
/// (docs/in-person-payments.md).
void main() {
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  const bridge = MethodChannel('invoice_ninja/stripe_terminal');
  var blocker = 'entitlementMissing';
  setUp(() {
    blocker = 'entitlementMissing';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method != 'deviceSupport') return false;
          return <String, Object?>{
            'tapToPay': blocker.isEmpty,
            'bluetooth': true,
            'tapToPayBlocker': blocker.isEmpty ? null : blocker,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null),
  );

  late ShellFixture fixture;

  Future<TerminalController> eligible(
    WidgetTester tester, {
    TerminalDeviceSupport support = const TerminalDeviceSupport(
      tapToPay: true,
      bluetooth: true,
    ),
  }) async {
    fixture = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Acme', isAdmin: true, isOwner: true),
      ],
    );
    addTearDown(fixture.dispose);
    final platform = FakeTerminalPlatform()..support = support;
    final terminal = TerminalController(
      repository: FakeTerminalRepo(),
      platform: platform,
      auth: fixture.services.auth,
      prefs: fixture.services.devicePrefs,
      platformReady: true,
      iPhone: true,
    );
    addTearDown(terminal.dispose);
    await terminal.refreshDevice();
    await terminal.refreshConfig('co1');
    return terminal;
  }

  Future<void> offerFrom(
    WidgetTester tester, {
    TerminalController? terminal,
    String? onlyGatewayId,
  }) async {
    await tester.pumpWidget(
      wrapWithShell(fixture.services, const Scaffold(body: Text('gateways'))),
    );
    // Not awaited: an offer that opens the screen waits on it.
    unawaited(
      offerTapToPayOnIPhone(
        tester.element(find.text('gateways')),
        onlyGatewayId: onlyGatewayId,
        terminalOverride: terminal,
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Finder pendingToast() => find.textContaining('still reviewing');

  testWidgets('an iPhone build without Apple’s entitlement: no call, no '
      'toast, no screen', (tester) async {
    fixture = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Acme', isAdmin: true, isOwner: true),
      ],
    );
    addTearDown(fixture.dispose);
    await offerFrom(tester);
    expect(find.byType(TapToPayEnableScreen), findsNothing);
    expect(pendingToast(), findsNothing);
  }, variant: iOS);

  testWidgets('Android: nothing at all', (tester) async {
    final terminal = await eligible(tester);
    await offerFrom(tester, terminal: terminal);
    expect(find.byType(TapToPayEnableScreen), findsNothing);
    expect(pendingToast(), findsNothing);
  }, variant: android);

  testWidgets('an eligible iPhone gets the enable screen', (tester) async {
    final terminal = await eligible(tester);
    await offerFrom(tester, terminal: terminal);
    expect(find.byType(TapToPayEnableScreen), findsOneWidget);
  }, variant: iOS);

  testWidgets('a gateway the server doesn’t list (a create it hasn’t got): '
      'no offer', (tester) async {
    final terminal = await eligible(tester);
    await offerFrom(tester, terminal: terminal, onlyGatewayId: 'cg_9');
    expect(find.byType(TapToPayEnableScreen), findsNothing);
    await offerFrom(tester, terminal: terminal, onlyGatewayId: 'cg_1');
    expect(find.byType(TapToPayEnableScreen), findsOneWidget);
  }, variant: iOS);

  testWidgets('already working for this company: no offer', (tester) async {
    final terminal = await eligible(tester);
    final gateway = FakeTerminalRepo.defaultConfig.gateways.single;
    await terminal.ensureTapToPay(
      companyId: 'co1',
      gateway: gateway,
      location: gateway.locations.single,
      merchantDisplayName: 'Acme',
      admin: true,
    );
    await offerFrom(tester, terminal: terminal);
    expect(find.byType(TapToPayEnableScreen), findsNothing);
  }, variant: iOS);

  group('Stripe Connect: in-app browser or the system one', () {
    testWidgets('an eligible iPhone watches it in the in-app browser', (
      tester,
    ) async {
      final terminal = await eligible(tester);
      expect(
        await watchesStripeConnect(
          terminal,
          gatewayKey: kGatewayStripeConnect,
          companyId: 'co1',
          iPhone: true,
        ),
        isTrue,
      );
    });

    testWidgets('anyone else keeps the system browser, as before', (
      tester,
    ) async {
      final terminal = await eligible(tester);
      expect(
        await watchesStripeConnect(
          terminal,
          gatewayKey: kGatewayStripeConnect,
          companyId: 'co1',
          iPhone: false,
        ),
        isFalse,
        reason: 'Android and every other platform',
      );
      expect(
        await watchesStripeConnect(
          terminal,
          gatewayKey: kGatewayStripe,
          companyId: 'co1',
          iPhone: true,
        ),
        isFalse,
        reason: 'only Stripe Connect opens a browser',
      );
      final cannot = await eligible(
        tester,
        support: const TerminalDeviceSupport(tapToPay: false, bluetooth: true),
      );
      expect(
        await watchesStripeConnect(
          cannot,
          gatewayKey: kGatewayStripeConnect,
          companyId: 'co1',
          iPhone: true,
        ),
        isFalse,
        reason: 'an iPad, an older iPhone, a build without the entitlement',
      );
    });
  });

  test('only a new Stripe gateway saved with API keys leads to the offer', () {
    expect(
      offersTapToPayAfterSave(
        isCreate: true,
        gatewayKey: kGatewayStripe,
        iPhone: true,
      ),
      isTrue,
    );
    expect(
      offersTapToPayAfterSave(
        isCreate: false,
        gatewayKey: kGatewayStripe,
        iPhone: true,
      ),
      isFalse,
      reason: 'an edit never offers',
    );
    expect(
      offersTapToPayAfterSave(
        isCreate: true,
        gatewayKey: kGatewayStripe,
        iPhone: false,
      ),
      isFalse,
    );
    expect(
      offersTapToPayAfterSave(
        isCreate: true,
        gatewayKey: kGatewayStripeConnect,
        iPhone: true,
      ),
      isFalse,
    );
  });
}
