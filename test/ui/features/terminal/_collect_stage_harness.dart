import 'dart:async';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/company_gateway_api_model.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/models/domain/billing/invitation.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:admin/ui/features/terminal/views/collect_card_payment_screen.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import '../../../_localization_helper.dart';
import '../shell/_shell_test_helpers.dart';
import '_terminal_fakes.dart';

/// Every theme the app can show (docs/in-person-payments.md § Themes): the
/// six presets of `InTheme` — the user picks one per side in Device Settings
/// — and the per-user accent colour laid over either side, here at its two
/// extremes: a pale accent and a near-black one.
final List<(String, ThemeData Function())> kAllAppThemes = [
  ('light_sand', () => buildInTheme(InTheme.lightSand)),
  ('light_mist', () => buildInTheme(InTheme.lightMist)),
  ('light_paper', () => buildInTheme(InTheme.lightPaper)),
  ('dark_espresso', () => buildInTheme(InTheme.darkEspresso)),
  ('dark_midnight', () => buildInTheme(InTheme.darkMidnight)),
  ('dark_carbon', () => buildInTheme(InTheme.darkCarbon)),
  (
    'light_sand_accent_amber',
    () => buildInTheme(
      InTheme.lightSand,
      accentOverride: const Color(0xFFF2B705),
    ),
  ),
  (
    'dark_carbon_accent_plum',
    () => buildInTheme(
      InTheme.darkCarbon,
      accentOverride: const Color(0xFF4A1259),
    ),
  ),
];

const kPaymentLink = 'https://acme.invoicing.co/client/pay/7Hx2kQ';
const kReceiptUrl = 'https://pay.stripe.com/receipts/acct_1/ch_1';

/// A sent invoice for 120.00 with the portal's payment link.
final Invoice kHarnessInvoice = emptyInvoice().copyWith(
  id: 'inv_1',
  number: '0042',
  clientId: 'cl_1',
  statusId: InvoiceStatus.sent,
  amount: Decimal.fromInt(120),
  balance: Decimal.fromInt(120),
  invitations: const [Invitation(link: kPaymentLink)],
);

final Client kHarnessClient = emptyClient().copyWith(
  id: 'cl_1',
  name: 'Northwind Bakery',
  displayName: 'Northwind Bakery',
);

/// Where a scene leaves the collect screen.
enum CollectScene {
  configure,

  /// A surcharge quoted: its breakdown under the amount.
  surcharge,
  waiting,

  /// Charged and declined: the fallback and the decline receipt apply.
  declined,

  /// The card couldn't be read: nothing was charged or declined.
  unread,
  cancelled,
  approved,
  recording,
  checking,
  unrecorded,
}

/// A real collect screen over fakes, for the fallback, receipt and theme
/// tests (and the review renders).
class CollectHarness {
  CollectHarness._(
    this.fixture,
    this.repo,
    this.platform,
    this.terminal,
    this.vm,
    this._invoice,
    this._enterPayment,
  );

  final ShellFixture fixture;
  final FakeTerminalRepo repo;
  final FakeTerminalPlatform platform;
  final TerminalController terminal;
  final CollectCardPaymentViewModel vm;
  final Invoice _invoice;
  final EnterPaymentByHand? _enterPayment;

  /// How often the view model fetched the invoice again, and what it got.
  int refetches = 0;
  Invoice? refetched;

  Services get services => fixture.services;

  static Future<CollectHarness> start(
    WidgetTester tester, {
    bool iPhone = false,
    bool link = true,
    bool gateway = true,
    Size size = const Size(390, 844),
    double textScale = 1,
    ThemeData? theme,
    EnterPaymentByHand? enterPayment,
  }) async {
    final fixture = await buildFixture(
      closeStreamsSynchronously: true,
      companies: [
        FakeCompany(
          id: 'co1',
          name: 'Acme',
          isAdmin: true,
          isOwner: true,
          settings: const {'currency_id': '1'},
        ),
      ],
    );
    addTearDown(fixture.dispose);
    // Each in a run of its own: a second Drift write in the same one never
    // returns under the test's clock.
    await tester.runAsync(
      () => fixture.services.statics.applyStatic(<String, dynamic>{
        'currencies': [
          {
            'id': '1',
            'name': 'US Dollar',
            'code': 'USD',
            'symbol': r'$',
            'precision': 2,
            'thousand_separator': ',',
            'decimal_separator': '.',
            'swap_currency_symbol': false,
            'exchange_rate': 1,
          },
        ],
      }),
    );
    if (gateway) {
      await tester.runAsync(
        () => fixture.services.companyGateways.applyBundle(
          companyId: 'co1',
          bundle: const [CompanyGatewayApi(id: 'cg1', gatewayKey: 'stripe')],
        ),
      );
    }
    final repo = FakeTerminalRepo();
    final platform = FakeTerminalPlatform()..remembersReader = true;
    final terminal = TerminalController(
      repository: repo,
      platform: platform,
      auth: fixture.services.auth,
      prefs: fixture.services.devicePrefs,
      platformReady: true,
      iPhone: iPhone,
    );
    addTearDown(terminal.dispose);
    await terminal.refreshDevice();
    await terminal.markHowToTapShown();
    final invoice = link
        ? kHarnessInvoice
        : kHarnessInvoice.copyWith(invitations: const []);
    late final CollectHarness harness;
    final vm = CollectCardPaymentViewModel(
      companyId: 'co1',
      invoice: invoice,
      terminal: terminal,
      repository: repo,
      isAdmin: true,
      merchantDisplayName: 'Acme',
      precision: 2,
      pollDelay: Duration.zero,
      iPhone: iPhone,
      clientEmail: 'sam@example.com',
      refetchInvoice: () async {
        harness.refetches++;
        return harness.refetched;
      },
    );
    harness = CollectHarness._(
      fixture,
      repo,
      platform,
      terminal,
      vm,
      invoice,
      enterPayment,
    );
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await harness.show(tester, theme ?? buildInTheme(InTheme.light));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return harness;
  }

  /// Pumps the screen under [theme]: the same screen and state on a second
  /// call, so one scene can be looked at in every theme.
  Future<void> show(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      Provider<Services>.value(
        value: fixture.services,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          localizationsDelegates: kTestLocalizationsDelegates,
          home: Stack(
            children: [
              Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('invoice below')),
                ),
                onGenerateInitialRoutes: (navigator, _) => [
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('invoice below')),
                  ),
                  MaterialPageRoute<void>(
                    builder: (_) => CollectCardPaymentScreen(
                      companyId: 'co1',
                      invoice: _invoice,
                      client: kHarnessClient,
                      viewModel: vm,
                      enterPayment: _enterPayment,
                    ),
                  ),
                ],
              ),
              Positioned.fill(
                child: ToastHost(controller: fixture.services.toasts),
              ),
            ],
          ),
        ),
      ),
    );
    // A theme change animates.
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Takes the screen to [scene].
  Future<void> drive(WidgetTester tester, CollectScene scene) async {
    const charged = TerminalPaymentOutcome(
      paymentIntentId: 'pi_1',
      status: 'succeeded',
    );
    void readAndFinalize() {
      repo.creates.add(fakeIntent());
      platform.session.reads.add(fakeRead(12000));
      repo.finalizes.add(fakeFinalize(12000));
    }

    switch (scene) {
      case CollectScene.configure:
        break;
      case CollectScene.surcharge:
        vm.setSurcharge(true);
      case CollectScene.waiting:
        repo.creates.add(fakeIntent());
        platform.session.reads.add(Completer<TerminalCollected>());
        unawaited(vm.collect());
      case CollectScene.declined || CollectScene.cancelled:
        readAndFinalize();
        platform.session.confirms.add(
          const TerminalError(TerminalErrorCode.declined),
        );
        unawaited(vm.collect());
      case CollectScene.unread:
        repo.creates.add(fakeIntent());
        platform.session.reads.add(
          const TerminalError(TerminalErrorCode.cardNotRead),
        );
        unawaited(vm.collect());
      case CollectScene.approved:
        readAndFinalize();
        platform.session.confirms.add(charged);
        repo.completes.add(
          TerminalCompletion(
            status: 'recorded',
            paymentId: 'pay_1',
            applied: Decimal.fromInt(120),
            unapplied: Decimal.zero,
            invoiceBalance: Decimal.zero,
            brand: 'visa',
            last4: '4242',
            receiptUrl: kReceiptUrl,
          ),
        );
        unawaited(vm.collect());
      case CollectScene.recording:
        readAndFinalize();
        platform.session.confirms.add(charged);
        repo.completes.add(fakeCompletion('recording'));
        unawaited(vm.collect());
      case CollectScene.checking:
        readAndFinalize();
        platform.session.confirms.add(
          const TerminalError(TerminalErrorCode.outcomeUnknown),
        );
        for (var i = 0; i < 3; i++) {
          repo.completes.add(fakeCompletion('requires_confirmation'));
        }
        unawaited(vm.collect());
      case CollectScene.unrecorded:
        readAndFinalize();
        platform.session.confirms.add(charged);
        repo.completes.add(fakeCompletion('rejected'));
        unawaited(vm.collect());
    }
    await settle(tester);
    if (scene == CollectScene.cancelled) {
      repo.cancels.add(fakeCompletion('canceled'));
      unawaited(vm.cancel());
      await settle(tester);
    }
  }

  /// Lets timers and the view model's awaits run out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Taps "Pay another way" and waits for the one read of the gateways —
  /// a real Drift read, which only real time finishes.
  Future<void> openFallback(WidgetTester tester) async {
    final row = find.text('Pay another way');
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
    // The read's own timeout, when the read never answered.
    await tester.pump(const Duration(seconds: 3));
  }

  /// Unmounts the screen and lets what it left (a cancel, a toast) run out.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }
}
