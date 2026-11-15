import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/ui/features/settings/widgets/tap_to_pay_tile.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_offer.dart';
import 'package:admin/ui/features/terminal/view_models/tap_to_pay_enable_view_model.dart';
import 'package:admin/ui/features/terminal/views/tap_to_pay_enable_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import '../shell/_shell_test_helpers.dart';
import '_terminal_fakes.dart';

/// The Tap to Pay on iPhone enable screen, Device Settings' tile, and the
/// watch on Stripe Connect (docs/in-person-payments.md).
void main() {
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

  Future<(TapToPayEnableViewModel, FakeTerminalRepo, FakeTerminalPlatform)>
  pump(
    WidgetTester tester, {
    bool isAdmin = true,
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
      iPhone: true,
    );
    addTearDown(terminal.dispose);
    await terminal.refreshDevice();
    await terminal.markHowToTapShown();
    final vm = TapToPayEnableViewModel(
      companyId: 'co1',
      companyName: 'Acme Plumbing',
      isAdmin: isAdmin,
      merchantDisplayName: 'Acme',
      terminal: terminal,
      enableCardPresent: (_) async =>
          repo.configAnswer = FakeTerminalRepo.defaultConfig,
    );
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithShell(fixture.services, TapToPayEnableScreen(viewModel: vm)),
    );
    await tester.pump();
    await tester.pump();
    return (vm, repo, platform);
  }

  Finder turnOn() => find.text('Turn on Tap to Pay on iPhone');

  testWidgets('the intro names the company and lists only what is left, '
      'then one press reaches Ready', (tester) async {
    final (vm, _, platform) = await pump(
      tester,
      arrange: (_, p) => p.status = TerminalPermission.denied,
    );
    expect(
      find.text(
        'Set up Tap to Pay on iPhone for Acme Plumbing on this iPhone.',
      ),
      findsOneWidget,
    );
    expect(find.text('Allow location access'), findsOneWidget);
    expect(
      find.text("Review and accept Apple's terms and conditions"),
      findsOneWidget,
    );
    expect(
      find.text('Turn on Card present for the Stripe gateway'),
      findsNothing,
      reason: 'Card present is on already',
    );
    expect(find.byType(TapToPayIcon), findsOneWidget);

    await tester.tap(turnOn());
    await tester.pumpAndSettle();
    // The app's own word before iOS asks.
    expect(find.text('Allow location access'), findsWidgets);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(platform.permissionRequests, 1);
    expect(platform.connects, [true]);
    expect(vm.stage, TapToPayEnableStage.ready);
    expect(find.text("You're ready to take cards."), findsOneWidget);
    expect(
      find.text('Open an invoice and choose Tap to Pay on iPhone.'),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Open invoices'), findsOneWidget);
    expect(vm.terminal.tapToPayAnnounced, isTrue);
  }, variant: iOS);

  testWidgets('getting ready shows progress, and Close is quiet', (
    tester,
  ) async {
    final hold = Completer<void>();
    final (vm, _, platform) = await pump(
      tester,
      arrange: (_, p) => p.connectAnswers.add(hold),
    );
    await tester.tap(turnOn());
    await tester.pump();
    await tester.pump();
    expect(find.text('Getting Tap to Pay on iPhone ready…'), findsOneWidget);
    platform.events.onUpdateProgress!(0.42);
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('You can leave this screen: setup carries on.'), findsOne);
    expect(vm.stage, TapToPayEnableStage.preparing);
    hold.complete();
    await tester.pumpAndSettle();
  }, variant: iOS);

  testWidgets('an error is inline with Retry; blocked location offers '
      'Settings', (tester) async {
    final (_, _, platform) = await pump(
      tester,
      arrange: (_, p) => p.connectAnswers.add(
        const TerminalError(TerminalErrorCode.termsCanceled),
      ),
    );
    await tester.tap(turnOn());
    await tester.pumpAndSettle();
    expect(
      find.text(
        "The Tap to Pay on iPhone terms weren't accepted, so it can't take "
        'cards yet. Press Retry to review them.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text("You're ready to take cards."), findsOneWidget);
    expect(platform.connects, [true, true]);
  }, variant: iOS);

  testWidgets('location blocked: Open settings instead of Retry', (
    tester,
  ) async {
    await pump(
      tester,
      arrange: (_, p) => p.status = TerminalPermission.blocked,
    );
    await tester.tap(turnOn());
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  }, variant: iOS);

  testWidgets('a member with Card present off is told to ask an admin', (
    tester,
  ) async {
    await pump(
      tester,
      isAdmin: false,
      arrange: (r, _) => r.configAnswer = const TerminalConfig(
        enabled: true,
        planOk: true,
        gateways: [],
        setupGateways: [
          TerminalSetupGateway(
            companyGatewayId: 'cg_1',
            label: 'Stripe',
            accountCountry: 'US',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Ask an admin to turn on Tap to Pay on iPhone.'),
      findsOneWidget,
    );
    expect(turnOn(), findsNothing);
  }, variant: iOS);

  group('Device Settings tile', () {
    for (final (state, words, action) in [
      (TapToPayTileState.checking, 'Checking…', null),
      (TapToPayTileState.notSetUp, 'Not set up on this iPhone', 'Turn on'),
      (
        TapToPayTileState.preparing,
        'Getting Tap to Pay on iPhone ready…',
        null,
      ),
      (TapToPayTileState.ready, 'Ready', 'How to use'),
      (
        TapToPayTileState.askAdmin,
        'Ask an admin to turn on Tap to Pay on iPhone.',
        null,
      ),
      (
        TapToPayTileState.updateIos,
        'Tap to Pay on iPhone needs the latest version of iOS. Update in '
            'Settings, General, Software Update.',
        null,
      ),
    ]) {
      testWidgets('${state.name}: Apple’s name and symbol, and what stands', (
        tester,
      ) async {
        final fixture = await buildFixture(
          companies: [FakeCompany(id: 'co1', name: 'Acme', isAdmin: true)],
        );
        addTearDown(fixture.dispose);
        var turnedOn = 0;
        await tester.pumpWidget(
          wrapWithShell(
            fixture.services,
            Material(
              child: TapToPayTile(
                state: state,
                progress: state == TapToPayTileState.preparing ? 0.5 : null,
                onTurnOn: () => turnedOn++,
                onHowToUse: () {},
              ),
            ),
          ),
        );
        expect(find.text('Tap to Pay on iPhone'), findsOneWidget);
        expect(find.byType(TapToPayIcon), findsOneWidget);
        expect(find.text(words), findsOneWidget);
        if (action != null) {
          expect(find.text(action), findsOneWidget);
        }
        if (state == TapToPayTileState.notSetUp) {
          await tester.tap(find.text('Turn on'));
          expect(turnedOn, 1);
        }
        if (state == TapToPayTileState.preparing) {
          expect(find.text('50%'), findsOneWidget);
        }
      }, variant: iOS);
    }
  });

  group('Stripe Connect in the in-app browser', () {
    test('a new Stripe gateway, or one the server updated, closes the browser '
        'and says so', () async {
      final answers = <StripeGatewaySnapshot>[
        {'g1': 10},
        {'g1': 10},
        {'g1': 11},
      ];
      var closed = 0;
      final watcher = StripeConnectWatcher(
        snapshot: () async => answers.removeAt(0),
        closeBrowser: () async => closed++,
        interval: Duration.zero,
      );
      expect(await watcher.watch(before: {'g1': 10}), isTrue);
      expect(closed, 1);
      expect(answers, isEmpty, reason: 'the reused gateway counted');

      final fresh = StripeConnectWatcher(
        snapshot: () async => {'g1': 10, 'g2': 1},
        closeBrowser: () async => closed++,
        interval: Duration.zero,
      );
      expect(await fresh.watch(before: {'g1': 10}), isTrue);
    });

    test('nothing new before it stops: the browser is left alone', () async {
      var asked = 0;
      var closed = 0;
      final watcher = StripeConnectWatcher(
        snapshot: () async {
          asked++;
          return {'g1': 10};
        },
        closeBrowser: () async => closed++,
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 30),
      );
      expect(await watcher.watch(before: {'g1': 10}), isFalse);
      expect(closed, 0);
      expect(asked, greaterThan(0));
    });

    test('the screen left or the company changed: it stops', () async {
      var wanted = true;
      var asked = 0;
      final watcher = StripeConnectWatcher(
        snapshot: () async {
          asked++;
          wanted = false;
          return const {};
        },
        closeBrowser: () async {},
        stillWanted: () => wanted,
        interval: Duration.zero,
      );
      expect(await watcher.watch(before: const {}), isFalse);
      expect(asked, 1);
    });

    test('a failed check is tried again; cancel stops it', () async {
      var asked = 0;
      final watcher = StripeConnectWatcher(
        snapshot: () async {
          asked++;
          throw Exception('offline');
        },
        closeBrowser: () async {},
        interval: Duration.zero,
      );
      final watching = watcher.watch(before: const {});
      await pumpEventQueue();
      watcher.cancel();
      expect(await watching, isFalse);
      expect(asked, greaterThan(1));
    });
  });
}
