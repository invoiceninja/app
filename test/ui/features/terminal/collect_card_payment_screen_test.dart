import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:admin/ui/features/terminal/views/collect_card_payment_screen.dart';
import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

import '../shell/_shell_test_helpers.dart';
import '_terminal_fakes.dart';

/// The collect screen renders every stage a counter can see, at a phone's
/// width and twice the text size, and holds Back while a card is charged
/// (docs/in-person-payments.md).
void main() {
  final invoice = emptyInvoice().copyWith(
    id: 'inv_1',
    number: '0042',
    statusId: InvoiceStatus.sent,
    amount: Decimal.fromInt(100),
    balance: Decimal.fromInt(100),
  );

  Future<(CollectCardPaymentViewModel, FakeTerminalRepo, FakeTerminalPlatform)>
  pump(
    WidgetTester tester, {
    double textScale = 1,
    bool iPhone = false,
    bool isAdmin = true,
    bool pressOnOpen = false,
    bool educated = false,
    Future<void> Function(String companyGatewayId)? enableCardPresent,
    void Function(FakeTerminalRepo, FakeTerminalPlatform)? arrange,
  }) async {
    final fixture = await buildFixture(
      companies: [
        FakeCompany(id: 'co1', name: 'Acme', isAdmin: true, isOwner: true),
      ],
    );
    addTearDown(fixture.dispose);
    final repo = FakeTerminalRepo();
    final platform = FakeTerminalPlatform();
    arrange?.call(repo, platform);
    final terminal = TerminalController(
      repository: repo,
      platform: platform,
      auth: fixture.services.auth,
      prefs: fixture.services.devicePrefs,
      platformReady: true,
      iPhone: iPhone,
    );
    addTearDown(terminal.dispose);
    // The invoice's action was offered: this phone's facts are known.
    if (iPhone) await terminal.refreshDevice();
    // Apple's education was already shown on this account.
    if (educated) await terminal.markHowToTapShown();
    final vm = CollectCardPaymentViewModel(
      companyId: 'co1',
      invoice: invoice,
      terminal: terminal,
      repository: repo,
      isAdmin: isAdmin,
      merchantDisplayName: 'Acme',
      precision: 2,
      pollDelay: Duration.zero,
      iPhone: iPhone,
      pressOnOpen: pressOnOpen,
      enableCardPresent: enableCardPresent,
    );
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: CollectCardPaymentScreen(
            companyId: 'co1',
            invoice: invoice,
            viewModel: vm,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (vm, repo, platform);
  }

  testWidgets('configure: test mode, the quoted total, and Collect once the '
      'reader is ready', (tester) async {
    final (vm, _, _) = await pump(tester);
    expect(vm.readerState, ReaderState.ready);
    expect(find.text('TEST MODE'), findsOneWidget);
    expect(find.textContaining('Customer pays'), findsOneWidget);
    expect(find.text('Tap to Pay on this phone'), findsOneWidget);
    final collect = find.ancestor(
      of: find.textContaining(RegExp(r'^Collect ')),
      matching: find.byType(FilledButton),
    );
    expect(collect, findsOneWidget);
    expect(tester.widget<FilledButton>(collect).onPressed, isNotNull);
  });

  testWidgets('every stage fits a phone at twice the text size', (
    tester,
  ) async {
    final (vm, repo, platform) = await pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);

    repo.creates.add(fakeIntent());
    final read = Completer<TerminalCollected>();
    platform.session.reads.add(read);
    unawaited(vm.collect());
    await tester.pump();
    await tester.pump();
    expect(vm.stage, CollectStage.waiting);
    expect(
      find.text('Hold the card near the back of the phone'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    repo.finalizes.add(fakeFinalize(10000));
    final confirm = Completer<TerminalPaymentOutcome>();
    platform.session.confirms.add(confirm);
    read.complete(fakeCard);
    await tester.pump();
    await tester.pump();
    expect(vm.stage, CollectStage.processing);
    expect(
      find.text('Charging the card. Keep this screen open.'),
      findsOneWidget,
    );
    // Nothing closes the screen while the card is being charged.
    final close = find.widgetWithIcon(IconButton, Icons.close);
    expect(tester.widget<IconButton>(close).onPressed, isNull);
    expect(tester.takeException(), isNull);

    repo.completes.add(fakeCompletion('recorded'));
    confirm.complete(
      const TerminalPaymentOutcome(
        paymentIntentId: 'pi_1',
        status: 'succeeded',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(vm.stage, CollectStage.approved);
    expect(find.text('Payment recorded'), findsOneWidget);
    expect(find.text('Send card receipt'), findsOneWidget);
    expect(find.text('VISA •• 4242'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown outcome says so, and offers only Check again', (
    tester,
  ) async {
    final (vm, repo, platform) = await pump(tester);
    repo.creates.add(fakeIntent());
    platform.session.reads.add(fakeCard);
    repo.finalizes.add(fakeFinalize(10000));
    platform.session.confirms.add(
      const TerminalError(TerminalErrorCode.outcomeUnknown),
    );
    for (var i = 0; i < 3; i++) {
      repo.completes.add(fakeCompletion('requires_confirmation'));
    }
    // Its retries wait on timers, which only a pump advances.
    unawaited(vm.collect());
    for (var i = 0; i < 20 && vm.stage != CollectStage.checking; i++) {
      await tester.pump(Duration.zero);
    }
    expect(vm.stage, CollectStage.checking);
    expect(find.textContaining("couldn't confirm whether"), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Try another card'), findsNothing);
  });

  group('Tap to Pay on iPhone', () {
    // The screen reads the platform for Apple's name and symbol.
    final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

    // Apple's own "How to Tap" can't show in a test: the app's instructions
    // stand in, as they do below iOS 18.
    const bridge = MethodChannel('invoice_ninja/stripe_terminal');
    setUp(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (_) async => false),
    );
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, null),
    );

    const howToTap = 'How to use Tap to Pay on iPhone';

    Finder button() => find.ancestor(
      of: find.text('Tap to Pay on iPhone'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );

    Future<void> press(WidgetTester tester) async {
      await tester.tap(button());
      await tester.pump();
      await tester.pump();
    }

    TerminalConfig setupOnly({String companyCountry = ''}) => TerminalConfig(
      enabled: true,
      planOk: true,
      gateways: const [],
      setupGateways: companyCountry.isEmpty
          ? const [
              TerminalSetupGateway(
                companyGatewayId: 'cg_1',
                label: 'Stripe',
                accountCountry: 'US',
              ),
            ]
          : const [],
      companyCountry: companyCountry,
    );

    testWidgets('the first frame already has Apple\'s button, never the '
        'greyed "Collect card payment" or the reader row', (tester) async {
      final config = Completer<TerminalConfig>();
      final (vm, _, _) = await pump(
        tester,
        iPhone: true,
        arrange: (r, _) => r.configAnswer = config,
      );
      expect(vm.starting, isTrue);
      expect(button(), findsOneWidget);
      expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);
      expect(
        find.ancestor(
          of: find.text('Collect card payment'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
        findsNothing,
      );
      expect(find.textContaining('Card payments need'), findsNothing);
      config.complete(FakeTerminalRepo.defaultConfig);
      await tester.pumpAndSettle();
    }, variant: iOS);

    testWidgets('a config that fails to load keeps Apple\'s button, and a '
        'press asks again', (tester) async {
      final (_, repo, _) = await pump(
        tester,
        iPhone: true,
        arrange: (r, _) => r.configAnswer = const NetworkException('offline'),
      );
      await tester.pumpAndSettle();
      expect(button(), findsOneWidget);
      final calls = repo.configCalls;
      repo.configAnswer = null; // the default config
      await press(tester);
      await tester.pumpAndSettle();
      expect(repo.configCalls, greaterThan(calls));
      expect(button(), findsOneWidget);
    }, variant: iOS);

    testWidgets('opening on the screen alone never prompts; the button is '
        'Apple\'s and there is no surcharge', (tester) async {
      final (vm, _, platform) = await pump(
        tester,
        iPhone: true,
        arrange: (_, p) => p.status = TerminalPermission.denied,
      );
      expect(platform.permissionRequests, 0);
      expect(platform.connects, isEmpty);
      expect(button(), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Collect .*\d')), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(
        find.text("Surcharges aren't available with Tap to Pay on iPhone yet."),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.contactless_outlined), findsNothing);
      expect(vm.tapToPayOnIPhone, isTrue);
    }, variant: iOS);

    testWidgets('a press explains location before iOS asks, then gets ready '
        'and waits for the next press', (tester) async {
      final (vm, repo, platform) = await pump(
        tester,
        iPhone: true,
        arrange: (_, p) => p.status = TerminalPermission.denied,
      );
      await press(tester);
      expect(find.text('Allow location access'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 0);

      await press(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(platform.permissionRequests, 1);
      expect(platform.connects, [true]);
      expect(vm.readerState, ReaderState.ready);
      // The first connect owed Apple's "How to Tap" (the fallback, here).
      expect(find.text(howToTap), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ready. Press Tap to Pay on iPhone to take the payment.'),
        findsOneWidget,
      );
      expect(repo.calls.where((c) => c.startsWith('create')), isEmpty);
    }, variant: iOS);

    testWidgets('location blocked for the app offers Settings; Location '
        'Services off says so', (tester) async {
      await pump(
        tester,
        iPhone: true,
        arrange: (_, p) => p.status = TerminalPermission.blocked,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Location access is off for this app. Turn it on in Settings to use '
          'Tap to Pay on iPhone.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open settings'), findsOneWidget);
    }, variant: iOS);

    testWidgets('Location Services off for the whole device', (tester) async {
      await pump(
        tester,
        iPhone: true,
        arrange: (_, p) {
          p.status = TerminalPermission.blocked;
          p.support = const TerminalDeviceSupport(
            tapToPay: true,
            bluetooth: true,
            locationServicesEnabled: false,
          );
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Location Services are off. Turn them on in Settings, Privacy & '
          'Security, Location Services.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open settings'), findsOneWidget);
    }, variant: iOS);

    testWidgets('Card present off: anyone but an admin is told to ask one, '
        'after the server is asked again', (tester) async {
      final (_, repo, _) = await pump(
        tester,
        iPhone: true,
        isAdmin: false,
        arrange: (r, _) => r.configAnswer = setupOnly(),
      );
      expect(button(), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      final calls = repo.configCalls;
      await press(tester);
      await tester.pumpAndSettle();
      expect(repo.configCalls, calls + 1);
      expect(
        find.text('Ask an admin to turn on Tap to Pay on iPhone.'),
        findsOneWidget,
      );
    }, variant: iOS);

    testWidgets('Card present off: one admin press turns it on and opens '
        'Apple\'s terms', (tester) async {
      final enabled = <String>[];
      late FakeTerminalRepo repository;
      final (vm, _, platform) = await pump(
        tester,
        iPhone: true,
        enableCardPresent: (id) async {
          enabled.add(id);
          repository.configAnswer = FakeTerminalRepo.defaultConfig;
        },
        arrange: (r, _) {
          repository = r;
          r.configAnswer = setupOnly();
        },
      );
      await press(tester);
      await tester.pumpAndSettle();
      expect(enabled, ['cg_1']);
      expect(platform.connects, [true]);
      expect(vm.readerState, ReaderState.ready);
    }, variant: iOS);

    testWidgets('no Stripe gateway: an admin is told to connect it', (
      tester,
    ) async {
      await pump(
        tester,
        iPhone: true,
        arrange: (r, _) => r.configAnswer = setupOnly(companyCountry: 'US'),
      );
      expect(button(), findsOneWidget);
      await press(tester);
      expect(
        find.text(
          'Connect Stripe first to use Tap to Pay on iPhone: Settings, '
          'Payment Settings.',
        ),
        findsOneWidget,
      );
    }, variant: iOS);

    for (final (code, words) in [
      (
        TerminalErrorCode.termsCanceled,
        "The Tap to Pay on iPhone terms weren't accepted, so it can't take "
            'cards yet. Press Retry to review them.',
      ),
      (
        TerminalErrorCode.termsNeedsAppleAccount,
        'To accept the Tap to Pay on iPhone terms, sign in with your Apple '
            'Account in Settings on this iPhone, then try again.',
      ),
      (
        TerminalErrorCode.termsFailed,
        "The Tap to Pay on iPhone terms couldn't be accepted. Try again.",
      ),
    ]) {
      testWidgets('${code.name}: its own words, and Retry opens the terms '
          'again', (tester) async {
        final (vm, _, platform) = await pump(
          tester,
          iPhone: true,
          arrange: (_, p) => p.connectAnswers
            ..add(const TerminalError(TerminalErrorCode.termsNotAccepted))
            ..add(TerminalError(code)),
        );
        await press(tester);
        await tester.pumpAndSettle();
        expect(find.text(words), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(platform.connects, [false, true, true]);
        expect(vm.readerState, ReaderState.ready);
      }, variant: iOS);
    }

    testWidgets('an iOS Apple wants updated says so when pressed', (
      tester,
    ) async {
      await pump(
        tester,
        iPhone: true,
        arrange: (_, p) => p.support = const TerminalDeviceSupport(
          tapToPay: true,
          bluetooth: true,
          osUpdateRequired: true,
        ),
      );
      expect(button(), findsOneWidget);
      await press(tester);
      expect(
        find.text(
          'Tap to Pay on iPhone needs the latest version of iOS. Update in '
          'Settings, General, Software Update.',
        ),
        findsOneWidget,
      );
    }, variant: iOS);

    testWidgets('while it gets ready the screen says so, with progress; the '
        'education follows the terms once their sheet has closed', (
      tester,
    ) async {
      final connecting = Completer<void>();
      final (vm, _, platform) = await pump(
        tester,
        iPhone: true,
        educated: true,
        arrange: (_, p) {
          p.connectAnswers
            ..add(const TerminalError(TerminalErrorCode.termsNotAccepted))
            ..add(connecting);
        },
      );
      await press(tester);
      expect(find.text('Getting Tap to Pay on iPhone ready…'), findsOneWidget);
      platform.events.onUpdateProgress!(0.5);
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);
      platform.events.onTermsAccepted!();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(howToTap), findsOneWidget);
      connecting.complete();
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(vm.readerState, ReaderState.ready);
      expect(find.text(howToTap), findsNothing, reason: 'shown once');
    }, variant: iOS);

    testWidgets('a connect that finishes right after the terms waits before '
        'the education, so it never covers the closing sheet', (tester) async {
      final (vm, _, platform) = await pump(
        tester,
        iPhone: true,
        educated: true,
        arrange: (_, p) {
          p.connectAnswers.add(
            const TerminalError(TerminalErrorCode.termsNotAccepted),
          );
        },
      );
      // The terms are accepted while this press connects, which then ends
      // at once.
      final pressed = tester.tap(button());
      platform.events.onTermsAccepted!();
      await pressed;
      await tester.pump();
      await tester.pump();
      expect(vm.readerState, ReaderState.ready);
      expect(find.text(howToTap), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(howToTap), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(howToTap), findsOneWidget);
    }, variant: iOS);

    testWidgets('no education when it was shown and no terms were accepted', (
      tester,
    ) async {
      final (vm, _, _) = await pump(
        tester,
        iPhone: true,
        educated: true,
        arrange: (_, p) => p.status = TerminalPermission.denied,
      );
      await press(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(vm.readerState, ReaderState.ready);
      expect(find.text(howToTap), findsNothing);
    }, variant: iOS);

    group('opened from the invoice\'s action', () {
      testWidgets('setup still needed: the press runs at once — the location '
          'explanation first', (tester) async {
        await pump(
          tester,
          iPhone: true,
          pressOnOpen: true,
          arrange: (_, p) => p.status = TerminalPermission.denied,
        );
        await tester.pumpAndSettle();
        expect(find.text('Allow location access'), findsWidgets);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }, variant: iOS);

      testWidgets('only a connect was needed: it goes straight on to the '
          'card, and nothing is charged until it is read', (tester) async {
        late FakeTerminalRepo repository;
        final (vm, _, platform) = await pump(
          tester,
          iPhone: true,
          educated: true,
          pressOnOpen: true,
          arrange: (r, p) {
            repository = r;
            r.creates.add(fakeIntent());
            p.session.reads.add(Completer<TerminalCollected>());
          },
        );
        await tester.pump();
        await tester.pump();
        expect(platform.connects, [true]);
        expect(vm.stage, CollectStage.waiting);
        expect(
          repository.calls.where((c) => c.startsWith('create')),
          hasLength(1),
        );
        expect(platform.session.calls, ['collect']);
        repository.cancels.add(fakeCompletion('canceled'));
        unawaited(vm.cancel());
        await tester.pumpAndSettle();
        expect(vm.stage, CollectStage.cancelled);
      }, variant: iOS);

      testWidgets('after Apple\'s terms it waits for a fresh press', (
        tester,
      ) async {
        late FakeTerminalRepo repository;
        final connecting = Completer<void>();
        final (vm, _, platform) = await pump(
          tester,
          iPhone: true,
          educated: true,
          pressOnOpen: true,
          arrange: (r, p) {
            repository = r;
            p.connectAnswers.add(connecting);
          },
        );
        platform.events.onTermsAccepted!();
        connecting.complete();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.text(howToTap), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(vm.readerState, ReaderState.ready);
        expect(repository.calls.where((c) => c.startsWith('create')), isEmpty);
        expect(
          find.text('Ready. Press Tap to Pay on iPhone to take the payment.'),
          findsOneWidget,
        );
      }, variant: iOS);
    });
  });
}
