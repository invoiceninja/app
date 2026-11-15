import 'dart:async';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/login_response_api_model.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/terminal_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/auth_service.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/data/services/terminal_platform.dart';
import 'package:admin/data/services/token_storage.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

/// Same `_FakeAuthService` shape as `auth_repository_test.dart` — duplicated
/// here rather than imported because the test files own their own test
/// doubles in this codebase (search for the comment block at the top of
/// each repo test).
class _FakeAuthService implements AuthService {
  void queueLogin(LoginResponseApi response) => _outcomes.add(response);

  final List<Object> _outcomes = [];

  @override
  Future<LoginResponseApi> login({
    required String baseUrl,
    required bool isHosted,
    required String email,
    required String password,
    String? oneTimePassword,
    String? secret,
  }) async {
    if (_outcomes.isEmpty) {
      throw StateError('no login outcome queued');
    }
    final next = _outcomes.removeAt(0);
    if (next is LoginResponseApi) return next;
    throw next;
  }

  @override
  Future<void> recoverPassword({
    required String baseUrl,
    required bool isHosted,
    required String email,
    String? secret,
  }) async {}

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

LoginResponseApi _envelope() => const LoginResponseApi(
  data: [
    UserCompanyApi(
      isAdmin: true,
      isOwner: true,
      permissions: '',
      company: CompanyEnvelopeApi(id: 'co_a', name: 'Acme'),
      token: SessionTokenApi(token: 'tok_a'),
      account: AccountEnvelopeApi(id: 'acct_1', plan: 'pro'),
    ),
  ],
);

class _FakeRepo implements TerminalRepository {
  final List<String> calls = [];
  Object? configAnswer;

  @override
  Future<TerminalConfig> config(String companyId) async {
    calls.add('config:$companyId');
    final answer = configAnswer;
    if (answer is TerminalConfig) return answer;
    throw answer ?? const ServerException(404, 'Route does not exist');
  }

  @override
  Future<String> connectionToken(
    String companyId, {
    required String companyGatewayId,
    required String locationId,
  }) async {
    calls.add('token:$companyGatewayId/$locationId');
    return 'pst_test_x';
  }

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakePlatform implements TerminalPlatform {
  final List<String> calls = [];
  TerminalDeviceSupport support = const TerminalDeviceSupport(
    tapToPay: true,
    bluetooth: true,
  );
  Future<String> Function()? tokenSource;

  /// The controller's one events slot: tests fire reader events through it.
  TerminalReaderEvents events = const TerminalReaderEvents();

  TerminalPermission status = TerminalPermission.granted;

  /// Each connect answers the next of these (a [TerminalError] is thrown, a
  /// [Completer] waited for); a plain success once they run out.
  final List<Object> connectAnswers = [];

  @override
  Future<TerminalPermission> permissionStatus(TerminalReaderKind kind) async {
    calls.add('status');
    return status;
  }

  @override
  bool get isAvailable => true;

  @override
  Future<TerminalDeviceSupport> deviceSupport() async => support;

  @override
  Future<void> initialize({
    required String account,
    required Future<String> Function() fetchToken,
  }) async {
    calls.add('initialize:$account');
    tokenSource = fetchToken;
  }

  @override
  Future<void> reset() async => calls.add('reset');

  @override
  Stream<List<TerminalReader>> discover(
    TerminalReaderKind kind, {
    bool simulated = false,
  }) {
    calls.add('discover:${kind.name}:$simulated');
    return Stream.value([
      TerminalReader(
        serialNumber: 'ttp',
        label: 'This phone',
        kind: kind,
        simulated: simulated,
        batteryLevel: -1,
        hasAvailableUpdate: false,
      ),
    ]);
  }

  @override
  Future<TerminalReader> connect(
    TerminalReader reader, {
    required String locationId,
    required String merchantDisplayName,
    required bool tosAcceptancePermitted,
  }) async {
    calls.add(
      'connect:$locationId:$merchantDisplayName:$tosAcceptancePermitted',
    );
    if (connectAnswers.isNotEmpty) {
      final answer = connectAnswers.removeAt(0);
      if (answer is Completer) await answer.future;
      if (answer is TerminalError) throw answer;
    }
    return _connected = reader;
  }

  /// Like the SDK, answer the reader a connect left connected — only when a
  /// test asks: the older tests expect none.
  bool remembersReader = false;
  TerminalReader? _connected;

  @override
  Future<TerminalReader?> connectedReader() async =>
      remembersReader ? _connected : null;

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

TerminalGatewayConfig _gateway({
  bool livemode = false,
  String country = 'US',
}) => TerminalGatewayConfig(
  companyGatewayId: 'cg_1',
  label: 'Stripe',
  livemode: livemode,
  accountCountry: country,
  defaultCurrency: 'usd',
  cardPaymentsActive: true,
  surcharge: TerminalSurchargeConfig.fromJson(const {}),
  locations: const [TerminalLocation(id: 'tml_1', displayName: 'Main')],
);

TerminalConfig _config({bool planOk = true}) =>
    TerminalConfig(enabled: true, planOk: planOk, gateways: [_gateway()]);

void main() {
  late AppDatabase db;
  late AuthRepository auth;
  late DevicePrefsStore prefs;
  late _FakeRepo repo;
  late _FakePlatform platform;
  late TerminalController terminal;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final authService = _FakeAuthService();
    auth = AuthRepository(
      db: db,
      authService: authService,
      tokenStorage: InMemoryTokenStorage(),
      passwordCache: PasswordCache(),
    );
    authService.queueLogin(_envelope());
    await auth.login(
      baseUrl: 'https://test',
      isHosted: false,
      email: 'a',
      password: 'b',
    );
    prefs = DevicePrefsStore(db);
    await prefs.load();
    repo = _FakeRepo();
    platform = _FakePlatform();
    terminal = TerminalController(
      repository: repo,
      platform: platform,
      auth: auth,
      prefs: prefs,
      platformReady: true,
    );
  });
  tearDown(() async {
    terminal.dispose();
    await db.close();
  });

  final invoice = emptyInvoice().copyWith(
    id: 'inv_1',
    statusId: InvoiceStatus.sent,
  );

  Future<void> settle() => pumpEventQueue();

  test('asks the server once per company, and offers the action once it '
      'answers', () async {
    repo.configAnswer = _config();
    expect(
      terminal.availabilityFor('co_a', invoice),
      TerminalAvailability.hidden,
    );
    terminal.ensureConfig('co_a');
    terminal.ensureConfig('co_a');
    await settle();
    expect(repo.calls, ['config:co_a']);
    expect(
      terminal.availabilityFor('co_a', invoice),
      TerminalAvailability.available,
    );
  });

  test('a server without the route is asked once and stays quiet', () async {
    terminal.ensureConfig('co_a');
    await settle();
    terminal.ensureConfig('co_a');
    await settle();
    expect(repo.calls, ['config:co_a']);
    expect(terminal.configFor('co_a'), isNull);
    expect(
      terminal.availabilityFor('co_a', invoice),
      TerminalAvailability.hidden,
    );
  });

  test(
    'a failed fetch is tried again after a minute, an answer after five',
    () async {
      var now = DateTime(2026, 11, 11, 12);
      final timed = TerminalController(
        repository: repo,
        platform: platform,
        auth: auth,
        prefs: prefs,
        platformReady: true,
        clock: () => now,
      );
      repo.configAnswer = const ServerException(500, 'boom');
      timed.ensureConfig('co_a');
      await settle();
      timed.ensureConfig('co_a');
      await settle();
      expect(repo.calls, ['config:co_a']);

      now = now.add(const Duration(minutes: 2));
      repo.configAnswer = _config();
      timed.ensureConfig('co_a');
      await settle();
      expect(
        timed.availabilityFor('co_a', invoice),
        TerminalAvailability.available,
      );

      // A later failure keeps the last answer.
      now = now.add(const Duration(minutes: 6));
      repo.configAnswer = const ServerException(500, 'boom');
      timed.ensureConfig('co_a');
      await settle();
      expect(repo.calls, hasLength(3));
      expect(
        timed.availabilityFor('co_a', invoice),
        TerminalAvailability.available,
      );
      timed.dispose();
    },
  );

  test('nothing is asked when the platform is not ready', () async {
    final off = TerminalController(
      repository: repo,
      platform: platform,
      auth: auth,
      prefs: prefs,
      platformReady: false,
    );
    off.ensureConfig('co_a');
    await settle();
    expect(repo.calls, isEmpty);
    off.dispose();
  });

  test(
    'a phone without Tap to Pay offers it only after a reader was used',
    () async {
      platform.support = const TerminalDeviceSupport(
        tapToPay: false,
        bluetooth: true,
      );
      repo.configAnswer = _config();
      terminal.ensureConfig('co_a');
      await settle();
      expect(
        terminal.availabilityFor('co_a', invoice),
        TerminalAvailability.hidden,
      );
      await terminal.noteReaderUsed();
      expect(
        terminal.availabilityFor('co_a', invoice),
        TerminalAvailability.available,
      );
      expect(prefs.read(DevicePrefKeys.cardReaderUsed), isTrue);
    },
  );

  test('the SDK session is per gateway and Location, and only an admin may '
      'accept Tap to Pay terms', () async {
    final gateway = _gateway();
    final location = gateway.locations.single;
    await terminal.prepare(
      companyId: 'co_a',
      gateway: gateway,
      location: location,
    );
    expect(platform.calls, ['initialize:co_a/cg_1/tml_1']);
    expect(await platform.tokenSource!(), 'pst_test_x');
    expect(repo.calls, ['token:cg_1/tml_1']);

    await terminal.connectTapToPay(
      gateway: gateway,
      location: location,
      merchantDisplayName: 'Acme',
      isAdmin: false,
    );
    expect(platform.calls.skip(1), [
      'discover:tapToPay:false',
      'connect:tml_1:Acme:false',
    ]);
  });

  test('the simulated reader is only used on a test-mode gateway', () async {
    terminal.simulated = true;
    final location = _gateway().locations.single;
    await terminal.connectTapToPay(
      gateway: _gateway(livemode: true),
      location: location,
      merchantDisplayName: 'Acme',
      isAdmin: true,
    );
    await terminal.connectTapToPay(
      gateway: _gateway(),
      location: location,
      merchantDisplayName: 'Acme',
      isAdmin: true,
    );
    expect(platform.calls.where((c) => c.startsWith('discover')), [
      'discover:tapToPay:false',
      'discover:tapToPay:true',
    ]);
  });

  test('reset waits for a charge in flight before resetting the SDK', () async {
    repo.configAnswer = _config();
    terminal.ensureConfig('co_a');
    await settle();
    final gateway = _gateway();
    await terminal.prepare(
      companyId: 'co_a',
      gateway: gateway,
      location: gateway.locations.single,
    );
    final charge = Completer<String>();
    final guarded = terminal.guardCharge(() => charge.future);
    var resetDone = false;
    final reset = terminal.reset().then((_) => resetDone = true);
    await settle();
    expect(resetDone, isFalse);
    expect(platform.calls, isNot(contains('reset')));
    charge.complete('succeeded');
    expect(await guarded, 'succeeded');
    await reset;
    expect(platform.calls, contains('reset'));
    expect(terminal.configFor('co_a'), isNull);
  });

  test('a sign-out on a phone that never opened a card session leaves the '
      'SDK alone', () async {
    await terminal.reset();
    expect(platform.calls, isNot(contains('reset')));
  });

  group('Tap to Pay on iPhone', () {
    late TerminalController phone;
    var frames = 0;

    setUp(() {
      frames = 0;
      platform.remembersReader = true;
      phone = TerminalController(
        repository: repo,
        platform: platform,
        auth: auth,
        prefs: prefs,
        platformReady: true,
        iPhone: true,
        afterFrame: () async => frames++,
      );
    });
    tearDown(() => phone.dispose());

    final gateway = _gateway();
    final location = gateway.locations.single;

    Future<TerminalReader> ensure({required bool admin}) =>
        phone.ensureTapToPay(
          companyId: 'co_a',
          gateway: gateway,
          location: location,
          merchantDisplayName: 'Acme',
          admin: admin,
        );

    List<String> connects() =>
        platform.calls.where((c) => c.startsWith('connect')).toList();

    test('single-flight per mode: a second call of the same mode shares the '
        'first connect', () async {
      final hold = Completer<void>();
      platform.connectAnswers.add(hold);
      final a = ensure(admin: false);
      final b = ensure(admin: false);
      await settle();
      hold.complete();
      expect(identical(await a, await b), isTrue);
      expect(connects(), ['connect:tml_1:Acme:false']);
    });

    test('an admin press during a quiet connect waits for it, then runs '
        'again so the terms can open', () async {
      final hold = Completer<void>();
      platform.connectAnswers
        ..add(hold)
        ..add(const TerminalError(TerminalErrorCode.termsNotAccepted));
      final quiet = ensure(admin: false);
      final press = ensure(admin: true);
      await settle();
      expect(connects(), ['connect:tml_1:Acme:false']);
      hold.complete();
      // The quiet connect still found the reader here (no terms needed): the
      // press uses it rather than connecting again.
      await quiet;
      await press;
      expect(connects(), ['connect:tml_1:Acme:false']);
      expect(phone.tapToPayLinked, isTrue);
    });

    test('an unlinked account: the quiet connect fails, the admin connect '
        'that follows may show the terms', () async {
      platform.connectAnswers.add(
        const TerminalError(TerminalErrorCode.termsNotAccepted),
      );
      final quiet = ensure(admin: false);
      final press = ensure(admin: true);
      await expectLater(
        quiet,
        throwsA(
          isA<TerminalError>().having(
            (e) => e.code,
            'code',
            TerminalErrorCode.termsNotAccepted,
          ),
        ),
      );
      await press;
      expect(connects(), [
        'connect:tml_1:Acme:false',
        'connect:tml_1:Acme:true',
      ]);
      expect(phone.tapToPayLinked, isTrue);
    });

    test('a reset while an admin connect waits behind a quiet one ends both '
        'before the terms could open', () async {
      final hold = Completer<void>();
      platform.connectAnswers.add(hold);
      final quiet = ensure(admin: false);
      final press = ensure(admin: true);
      final quietEnds = expectLater(quiet, throwsA(isA<TerminalError>()));
      final pressEnds = expectLater(
        press,
        throwsA(
          isA<TerminalError>().having(
            (e) => e.code,
            'code',
            TerminalErrorCode.sessionExpired,
          ),
        ),
      );
      await settle();
      final reset = phone.reset();
      hold.complete();
      await quietEnds;
      await pressEnds;
      await reset;
      expect(connects(), ['connect:tml_1:Acme:false']);
      expect(phone.reader, isNull);
    });

    test('a connect for another gateway never shares one under way: it waits, '
        'then connects its own', () async {
      final hold = Completer<void>();
      platform.connectAnswers.add(hold);
      final other = TerminalGatewayConfig(
        companyGatewayId: 'cg_2',
        label: 'Stripe EU',
        livemode: false,
        accountCountry: 'IE',
        defaultCurrency: 'eur',
        cardPaymentsActive: true,
        surcharge: TerminalSurchargeConfig.fromJson(const {}),
        locations: const [TerminalLocation(id: 'tml_2', displayName: 'EU')],
      );
      final warm = ensure(admin: false);
      final screen = phone.ensureTapToPay(
        companyId: 'co_a',
        gateway: other,
        location: other.locations.single,
        merchantDisplayName: 'Acme',
        admin: false,
      );
      expect(identical(warm, screen), isFalse);
      await settle();
      expect(connects(), ['connect:tml_1:Acme:false']);
      hold.complete();
      await warm;
      await screen;
      expect(platform.calls.where((c) => c.startsWith('initialize')), [
        'initialize:co_a/cg_1/tml_1',
        'initialize:co_a/cg_2/tml_2',
      ]);
      expect(connects(), [
        'connect:tml_1:Acme:false',
        'connect:tml_2:Acme:false',
      ]);
    });

    test('a quiet call during an admin connect shares it', () async {
      final hold = Completer<void>();
      platform.connectAnswers.add(hold);
      final press = ensure(admin: true);
      final quiet = ensure(admin: false);
      expect(identical(press, quiet), isTrue);
      hold.complete();
      await press;
      expect(connects(), ['connect:tml_1:Acme:true']);
    });

    test('a reset during a connect ends it: the reader never outlives its '
        'company', () async {
      final hold = Completer<void>();
      platform.connectAnswers.add(hold);
      final connecting = ensure(admin: true);
      await settle();
      final reset = phone.reset();
      hold.complete();
      await expectLater(
        connecting,
        throwsA(
          isA<TerminalError>().having(
            (e) => e.code,
            'code',
            TerminalErrorCode.sessionExpired,
          ),
        ),
      );
      await reset;
      expect(phone.tapToPayLinked, isNull);
      expect(phone.tapToPayConnecting, isFalse);
    });

    test('a connect waits for a reset under way before it starts', () async {
      repo.configAnswer = _config();
      await phone.prepare(
        companyId: 'co_a',
        gateway: gateway,
        location: location,
      );
      final charge = Completer<void>();
      unawaited(phone.guardCharge(() => charge.future));
      final reset = phone.reset();
      platform.calls.clear();
      final connecting = ensure(admin: false);
      await settle();
      expect(platform.calls, isEmpty, reason: 'still resetting');
      charge.complete();
      await reset;
      await connecting;
      expect(platform.calls.first, 'reset');
      expect(connects(), ['connect:tml_1:Acme:false']);
    });

    test(
      'the linked state is in memory only, and a resume forgets it',
      () async {
        platform.connectAnswers.add(
          const TerminalError(TerminalErrorCode.termsNotAccepted),
        );
        await expectLater(ensure(admin: false), throwsA(isA<TerminalError>()));
        expect(phone.tapToPayLinked, isFalse);
        await phone.onResumed(null);
        expect(phone.tapToPayLinked, isNull);
      },
    );

    test('reader events fan out to every listener; progress, disconnects and '
        'the terms are kept by the controller', () async {
      final seen = <String>[];
      final stopA = phone.addEventListener(
        TerminalReaderEvents(
          onDisplayMessage: (m) => seen.add('a:${m.name}'),
          onTermsAccepted: () => seen.add('a:terms'),
          onDisconnected: () => seen.add('a:gone'),
        ),
      );
      phone.addEventListener(
        TerminalReaderEvents(
          onDisplayMessage: (m) => seen.add('b:${m.name}'),
          onUpdateProgress: (p) => seen.add('b:$p'),
        ),
      );
      final events = platform.events;
      events.onDisplayMessage!(TerminalDisplayMessage.removeCard);
      events.onUpdateProgress!(0.4);
      expect(phone.setupProgress.value, 0.4);
      events.onUpdateFinished!(null);
      expect(phone.setupProgress.value, isNull);
      await ensure(admin: true);
      expect(phone.reader, isNotNull);
      events.onDisconnected!();
      expect(phone.reader, isNull);
      platform.connectAnswers.add(
        const TerminalError(TerminalErrorCode.termsNotAccepted),
      );
      await expectLater(ensure(admin: false), throwsA(isA<TerminalError>()));
      expect(phone.tapToPayLinked, isFalse);
      events.onTermsAccepted!();
      expect(phone.tapToPayLinked, isTrue);
      stopA();
      events.onDisplayMessage!(TerminalDisplayMessage.insertCard);
      expect(seen, [
        'a:removeCard',
        'b:removeCard',
        'b:0.4',
        'a:gone',
        'a:terms',
        'b:insertCard',
      ]);
    });

    group('warm-up', () {
      setUp(() => repo.configAnswer = _config());

      test('after the first frame, it connects without the terms', () async {
        await phone.warmUpAfterFirstFrame('co_a');
        expect(frames, 1);
        expect(connects(), ['connect:tml_1:Acme:false']);
        expect(
          platform.calls,
          isNot(contains(startsWith('requestPermissions'))),
        );
      });

      test('never on another platform', () async {
        final android = TerminalController(
          repository: repo,
          platform: platform,
          auth: auth,
          prefs: prefs,
          platformReady: true,
          iPhone: false,
          afterFrame: () async => frames++,
        );
        addTearDown(android.dispose);
        await android.warmUpAfterFirstFrame('co_a');
        await android.warmUp('co_a');
        expect(frames, 0);
        expect(connects(), isEmpty);
      });

      test('stops at the first check that fails', () async {
        Future<void> expectNoConnect(String reason) async {
          await phone.warmUp('co_a');
          expect(connects(), isEmpty, reason: reason);
        }

        platform.support = const TerminalDeviceSupport(
          tapToPay: true,
          bluetooth: true,
          osUpdateRequired: true,
        );
        await expectNoConnect('an iOS Apple wants updated');
        platform.support = const TerminalDeviceSupport(
          tapToPay: false,
          bluetooth: true,
        );
        await expectNoConnect('no Tap to Pay on this phone');
        platform.support = const TerminalDeviceSupport(
          tapToPay: true,
          bluetooth: true,
        );
        platform.status = TerminalPermission.denied;
        await expectNoConnect('location not allowed yet: never a prompt');
        platform.status = TerminalPermission.granted;
        final release = phone.holdWarmUp();
        await expectNoConnect('a collect screen gets its reader itself');
        release();
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
        await phone.refreshConfig('co_a');
        await expectNoConnect('no Location yet');
        repo.configAnswer = _config();
        await phone.refreshConfig('co_a');
        platform.connectAnswers.add(
          const TerminalError(TerminalErrorCode.termsNotAccepted),
        );
        await phone.warmUp('co_a');
        expect(connects(), hasLength(1));
        expect(phone.tapToPayLinked, isFalse);
        await phone.warmUp('co_a');
        expect(
          connects(),
          hasLength(1),
          reason: 'an account known to be unlinked is left for the press',
        );
        await phone.onResumed('co_a');
        expect(connects(), hasLength(2), reason: 'a resume asks Apple again');
      });

      test(
        'an older server is asked once, however often it warms up',
        () async {
          repo.configAnswer = null; // 404
          await phone.warmUp('co_a');
          await phone.onResumed('co_a');
          await phone.warmUpAfterFirstFrame('co_a');
          expect(repo.calls.where((c) => c.startsWith('config')), hasLength(1));
          expect(connects(), isEmpty);
        },
      );

      test(
        'a failed fetch waits its minute before a warm-up asks again',
        () async {
          repo.configAnswer = const NetworkException('offline');
          await phone.warmUp('co_a');
          await phone.onResumed('co_a');
          expect(repo.calls.where((c) => c.startsWith('config')), hasLength(1));
        },
      );

      test('a warm-up asked for while another runs gets its own once the '
          'session changed', () async {
        final hold = Completer<void>();
        platform.connectAnswers.add(hold);
        final first = phone.warmUp('co_a');
        await settle();
        expect(connects(), hasLength(1));
        // A company switch: the reset, then the next company's warm-up.
        final reset = phone.reset();
        await phone.warmUpAfterFirstFrame('co_a');
        hold.complete();
        await reset;
        await first;
        await settle();
        expect(connects(), hasLength(2));
        expect(phone.reader, isNotNull);
      });

      test('nothing when already connected or connecting', () async {
        await ensure(admin: false);
        await phone.warmUp('co_a');
        expect(connects(), hasLength(1));
      });
    });

    test('the action shows on an iPhone for a gateway whose Card present is '
        'still off, and on an iOS Apple wants updated', () async {
      platform.support = const TerminalDeviceSupport(
        tapToPay: true,
        bluetooth: true,
        osUpdateRequired: true,
      );
      repo.configAnswer = const TerminalConfig(
        enabled: true,
        planOk: true,
        gateways: [],
        setupGateways: [
          TerminalSetupGateway(
            companyGatewayId: 'cg_2',
            label: 'Stripe',
            accountCountry: 'US',
          ),
        ],
      );
      phone.ensureConfig('co_a');
      await settle();
      expect(
        phone.availabilityFor('co_a', invoice),
        TerminalAvailability.available,
      );
      expect(phone.offersTapToPayOnIPhone('co_a'), isTrue);
      terminal.ensureConfig('co_a');
      await settle();
      expect(
        terminal.availabilityFor('co_a', invoice),
        TerminalAvailability.hidden,
        reason: 'Android and every other platform are unchanged',
      );
    });
  });
}
