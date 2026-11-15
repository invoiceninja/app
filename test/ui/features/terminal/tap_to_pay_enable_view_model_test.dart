import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/token_storage.dart';
import 'package:admin/ui/features/terminal/view_models/tap_to_pay_enable_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

import '_terminal_fakes.dart';

/// Turning Tap to Pay on iPhone on outside checkout (docs/in-person-payments.md):
/// the collect button's steps, only those still needed, then Ready.
void main() {
  late AppDatabase db;
  late AuthRepository auth;
  late DevicePrefsStore prefs;
  late FakeTerminalRepo repo;
  late FakeTerminalPlatform platform;
  late TerminalController terminal;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final authService = FakeAuthService();
    auth = AuthRepository(
      db: db,
      authService: authService,
      tokenStorage: InMemoryTokenStorage(),
      passwordCache: PasswordCache(),
    );
    authService.queueLogin(fakeEnvelope());
    await auth.login(
      baseUrl: 'https://test',
      isHosted: false,
      email: 'a',
      password: 'b',
    );
    prefs = DevicePrefsStore(db);
    await prefs.load();
    repo = FakeTerminalRepo();
    platform = FakeTerminalPlatform();
    terminal = TerminalController(
      repository: repo,
      platform: platform,
      auth: auth,
      prefs: prefs,
      platformReady: true,
      iPhone: true,
    );
    await terminal.refreshDevice();
  });
  tearDown(() async {
    terminal.dispose();
    await db.close();
  });

  const setupOnly = TerminalConfig(
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
  );

  final enabled = <String>[];
  var asked = 0;
  var educated = 0;

  TapToPayEnableViewModel vm({bool isAdmin = true, bool allow = true}) {
    enabled.clear();
    asked = 0;
    educated = 0;
    final model =
        TapToPayEnableViewModel(
            companyId: 'co_a',
            companyName: 'Acme',
            isAdmin: isAdmin,
            merchantDisplayName: 'Acme',
            terminal: terminal,
            enableCardPresent: (id) async {
              enabled.add(id);
              repo.configAnswer = FakeTerminalRepo.defaultConfig;
            },
          )
          ..askLocation = () async {
            asked++;
            return allow;
          }
          ..onReady = () async => educated++;
    addTearDown(model.dispose);
    return model;
  }

  test('the intro lists only the steps still needed', () async {
    final ready = vm();
    await ready.load();
    expect(ready.stage, TapToPayEnableStage.intro);
    expect(ready.steps, {TapToPayEnableStep.terms, TapToPayEnableStep.learn});

    platform.status = TerminalPermission.denied;
    repo.configAnswer = setupOnly;
    await terminal.refreshConfig('co_a');
    final fresh = vm();
    await fresh.load();
    expect(fresh.steps, TapToPayEnableStep.values.toSet());
    expect(platform.permissionRequests, 0, reason: 'opening never prompts');

    final member = vm(isAdmin: false);
    await member.load();
    expect(
      member.stage,
      TapToPayEnableStage.askAdmin,
      reason: 'only an admin can turn Card present on',
    );
    expect(member.steps, isNot(contains(TapToPayEnableStep.terms)));
  });

  test('an admin goes from Card present to Ready in one press, and it is '
      'remembered', () async {
    platform.status = TerminalPermission.denied;
    repo.configAnswer = setupOnly;
    final model = vm();
    await model.start();
    expect(enabled, ['cg_1']);
    expect(asked, 1, reason: 'the app explains before iOS asks');
    expect(platform.permissionRequests, 1);
    expect(platform.connects, [true], reason: 'Apple’s terms may open');
    expect(educated, 1);
    expect(model.stage, TapToPayEnableStage.ready);
    expect(model.doneSteps, TapToPayEnableStep.values.toSet());
    expect(terminal.tapToPayAnnounced, isTrue);
  });

  test('no Stripe Location yet: an admin’s is created quietly', () async {
    repo.configAnswer = TerminalConfig(
      enabled: true,
      planOk: true,
      gateways: [
        TerminalGatewayConfig(
          companyGatewayId: 'cg_1',
          label: 'Stripe',
          livemode: false,
          accountCountry: 'US',
          defaultCurrency: 'usd',
          cardPaymentsActive: true,
          surcharge: TerminalSurchargeConfig.fromJson(const {}),
          locations: const [],
        ),
      ],
    );
    final model = vm();
    await model.start();
    expect(repo.locationsCreated, 1);
    expect(model.stage, TapToPayEnableStage.ready);
  });

  test('a member whose account isn’t linked is told to ask an admin', () async {
    platform.connectAnswers.add(
      const TerminalError(TerminalErrorCode.termsNotAccepted),
    );
    final model = vm(isAdmin: false);
    await model.start();
    expect(platform.connects, [false], reason: 'never the terms sheet');
    expect(model.stage, TapToPayEnableStage.askAdmin);
    expect(terminal.tapToPayAnnounced, isFalse);
  });

  test('location blocked, or off for the device: Settings, and back from '
      'them it runs again', () async {
    platform.status = TerminalPermission.blocked;
    final model = vm();
    await model.start();
    expect(model.stage, TapToPayEnableStage.failed);
    expect(model.needsSettings, isTrue);
    expect(model.problem?.code, TerminalErrorCode.permissionDenied);

    platform.status = TerminalPermission.granted;
    model.appResumed();
    await pumpEventQueue();
    expect(model.stage, TapToPayEnableStage.ready);

    await terminal.disconnect();
    platform.support = const TerminalDeviceSupport(
      tapToPay: true,
      bluetooth: true,
      locationServicesEnabled: false,
    );
    final off = vm();
    await off.start();
    expect(off.problem?.code, TerminalErrorCode.locationServicesDisabled);
    expect(off.needsSettings, isTrue);
  });

  test(
    'declining the explanation stays on the intro, asking nothing',
    () async {
      platform.status = TerminalPermission.denied;
      final model = vm(allow: false);
      await model.start();
      expect(model.stage, TapToPayEnableStage.intro);
      expect(platform.permissionRequests, 0);
      expect(platform.connects, isEmpty);
    },
  );

  test('the terms cancelled: the error inline, and Retry runs again', () async {
    platform.connectAnswers.add(
      const TerminalError(TerminalErrorCode.termsCanceled),
    );
    final model = vm();
    await model.start();
    expect(model.stage, TapToPayEnableStage.failed);
    expect(model.problem?.code, TerminalErrorCode.termsCanceled);
    expect(model.needsSettings, isFalse);
    await model.start();
    expect(model.stage, TapToPayEnableStage.ready);
  });

  test('a reader already connected is Ready at once', () async {
    final gateway = FakeTerminalRepo.defaultConfig.gateways.single;
    await terminal.ensureTapToPay(
      companyId: 'co_a',
      gateway: gateway,
      location: gateway.locations.single,
      merchantDisplayName: 'Acme',
      admin: true,
    );
    final model = vm();
    await model.load();
    expect(model.stage, TapToPayEnableStage.ready);
  });

  test('no Stripe gateway: an admin is told to connect Stripe', () async {
    repo.configAnswer = const TerminalConfig(
      enabled: true,
      planOk: true,
      gateways: [],
      companyCountry: 'US',
    );
    final model = vm();
    await model.load();
    expect(model.stage, TapToPayEnableStage.failed);
    expect(model.problem?.serverCode, 'connect_stripe_first');
  });

  test('closing never stops the connect: it carries on in the controller', () {
    final hold = Completer<void>();
    platform.connectAnswers.add(hold);
    // Disposed by the test itself, as the screen does when it closes.
    final model = TapToPayEnableViewModel(
      companyId: 'co_a',
      companyName: 'Acme',
      isAdmin: true,
      merchantDisplayName: 'Acme',
      terminal: terminal,
      enableCardPresent: (_) async {},
    )..askLocation = () async => true;
    final running = model.start();
    return Future<void>(() async {
      await pumpEventQueue();
      expect(model.stage, TapToPayEnableStage.preparing);
      model.dispose();
      expect(terminal.tapToPayConnecting, isTrue);
      hold.complete();
      await running;
      await pumpEventQueue();
      expect(terminal.reader, isNotNull);
    });
  });
}
