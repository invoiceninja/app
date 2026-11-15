import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/env.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/terminal_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/terminal_platform.dart';
import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';

final _log = Logger('TerminalController');

/// In-person card payments for the session (docs/in-person-payments.md):
/// which companies can take a card, what this phone can read cards with, and
/// the card reader's connection, kept across collections.
///
/// The server decides who may collect and on which gateway
/// (`terminal/config`); this only asks once per company per session, and
/// remembers a server that has no such route so an older one is never asked
/// again. A session end or a company switch [reset]s everything — after any
/// charge in flight has been answered.
class TerminalController extends ChangeNotifier {
  TerminalController({
    required TerminalRepository repository,
    required TerminalPlatform platform,
    required AuthRepository auth,
    required DevicePrefsStore prefs,
    bool? platformReady,
    bool? iPhone,
    DateTime Function()? clock,
    Future<void> Function()? afterFrame,
  }) : _clock = clock ?? DateTime.now,
       _repo = repository,
       _platform = platform,
       _auth = auth,
       _prefs = prefs,
       _platformReady = platformReady,
       _iPhone = iPhone ?? isIPhonePlatform(),
       _afterFrame = afterFrame {
    _readerUsed = prefs.read(DevicePrefKeys.cardReaderUsed) ?? false;
    prefs.addListener(_syncPrefs);
    // The one slot the SDK has: every screen subscribes here instead.
    _platform.events = TerminalReaderEvents(
      onDisplayMessage: (m) => _fanOut((e) => e.onDisplayMessage?.call(m)),
      onInputOptions: (o) => _fanOut((e) => e.onInputOptions?.call(o)),
      onUpdateAvailable: () => _fanOut((e) => e.onUpdateAvailable?.call()),
      onUpdateProgress: (p) {
        _setProgress(p);
        _fanOut((e) => e.onUpdateProgress?.call(p));
      },
      onUpdateFinished: (error) {
        _setProgress(null);
        _fanOut((e) => e.onUpdateFinished?.call(error));
      },
      onReconnecting: () => _fanOut((e) => e.onReconnecting?.call()),
      onReconnected: () => _fanOut((e) => e.onReconnected?.call()),
      onDisconnected: () {
        if (_reader != null) {
          _reader = null;
          if (!_disposed) notifyListeners();
        }
        _fanOut((e) => e.onDisconnected?.call());
      },
      onLowBattery: () => _fanOut((e) => e.onLowBattery?.call()),
      onTermsAccepted: () {
        _linked = true;
        _linkedCompany = _account?.split('/').first;
        _fanOut((e) => e.onTermsAccepted?.call());
      },
    );
  }

  final TerminalRepository _repo;
  final TerminalPlatform _platform;
  final AuthRepository _auth;
  final DevicePrefsStore _prefs;
  final bool? _platformReady;
  final DateTime Function() _clock;

  /// An iPhone: Tap to Pay on iPhone's own rules apply (warm-up, the linked
  /// state). Injected by tests.
  final bool _iPhone;

  /// Waits for the frame after a company switch; tests inject it.
  final Future<void> Function()? _afterFrame;

  /// How long an answer stands: an admin who turns Card present on sees it
  /// within minutes, and a failed fetch is tried again.
  static const configLifetime = Duration(minutes: 5);
  static const failedConfigRetry = Duration(minutes: 1);

  TerminalPlatform get platform => _platform;
  TerminalRepository get repository => _repo;

  // ------------------------------------------------------------- events

  final List<TerminalReaderEvents> _listeners = [];

  /// Reader prompts, updates and disconnects, for as long as the caller
  /// listens: call the result to stop. The controller owns the SDK's one
  /// events slot, so screens never set it.
  VoidCallback addEventListener(TerminalReaderEvents listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _fanOut(void Function(TerminalReaderEvents listener) call) {
    for (final listener in List.of(_listeners)) {
      call(listener);
    }
  }

  /// 0–1 while the reader configures or updates (Tap to Pay on iPhone's
  /// first preparation among them), else null — App Review 3.9.1's progress.
  ValueListenable<double?> get setupProgress => _progress;
  final ValueNotifier<double?> _progress = ValueNotifier(null);

  void _setProgress(double? value) {
    if (!_disposed) _progress.value = value;
  }

  /// The build has the feature, this is the mobile app with Stripe's SDK, and
  /// not the demo.
  bool get platformReady =>
      _platformReady ??
      (kCardPresentEnabled &&
          Env.isMobile &&
          !Env.demoMode &&
          _platform.isAvailable);

  final Map<String, _ConfigEntry> _configs = {};
  TerminalDeviceSupport? _device;
  Future<void>? _deviceLoading;

  /// Stripe's simulated reader, from the Debug Panel; honoured only on a
  /// test-mode gateway.
  bool get simulated => _simulated;
  bool _simulated = false;
  set simulated(bool value) {
    if (_simulated == value) return;
    _simulated = value;
    // A reader connected the other way must not serve the next collection.
    unawaited(disconnect());
    notifyListeners();
  }

  /// A Bluetooth reader has been connected in this app.
  bool get readerUsed => _readerUsed;
  bool _readerUsed = false;

  Future<void> noteReaderUsed() async {
    if (_readerUsed) return;
    _readerUsed = true;
    notifyListeners();
    await _prefs.write(DevicePrefKeys.cardReaderUsed, true);
  }

  void _syncPrefs() {
    final used = _prefs.read(DevicePrefKeys.cardReaderUsed) ?? false;
    if (used == _readerUsed) return;
    _readerUsed = used;
    notifyListeners();
  }

  // ------------------------------------------------- payments being checked

  Map<String, dynamic> _pending() {
    final raw = _prefs.read(DevicePrefKeys.pendingCardPayments);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePending(Map<String, dynamic> pending) => _prefs.write(
    DevicePrefKeys.pendingCardPayments,
    pending.isEmpty ? null : jsonEncode(pending),
  );

  /// A charge is about to start: until the server answers, the payment is
  /// remembered on the device, so a crash or a closed app can't lose it.
  Future<void> notePending({
    required String companyId,
    required String invoiceId,
    required String paymentIntentId,
    String invoiceNumber = '',
  }) => _savePending({
    ..._pending(),
    paymentIntentId: {
      'company': companyId,
      'invoice': invoiceId,
      // For the notice of a decline nobody saw ([sweepPending]).
      if (invoiceNumber.isNotEmpty) 'number': invoiceNumber,
    },
  });

  /// The server gave a final answer for it.
  Future<void> clearPending(String paymentIntentId) async {
    final pending = _pending();
    if (pending.remove(paymentIntentId) != null) await _savePending(pending);
  }

  /// Every payment on [invoiceId] still waiting for the server's answer —
  /// more than one when an attempt that couldn't be confirmed was followed by
  /// another.
  List<String> pendingAllFor(String companyId, String invoiceId) => [
    for (final e in _pending().entries)
      if (e.value case {
        'company': final c,
        'invoice': final i,
      } when c == companyId && i == invoiceId)
        e.key,
  ];

  /// The first payment on [invoiceId] still waiting for the server's answer.
  String? pendingFor(String companyId, String invoiceId) =>
      pendingAllFor(companyId, invoiceId).firstOrNull;

  /// Asks the server about every pending payment on [invoiceId], and says
  /// what came of them.
  Future<PendingRecovery> recoverPending(
    String companyId,
    String invoiceId,
  ) async {
    var recorded = false;
    var unknown = false;
    for (final pi in pendingAllFor(companyId, invoiceId)) {
      try {
        final result = await _repo.complete(
          companyId,
          pi,
          invoiceId: invoiceId,
        );
        if (isFinalCompletion(result.status)) {
          await clearPending(pi);
          if (result.isRecorded) recorded = true;
        } else {
          unknown = true;
        }
      } catch (_) {
        unknown = true;
      }
    }
    if (unknown) return PendingRecovery.unknown;
    return recorded ? PendingRecovery.recorded : PendingRecovery.none;
  }

  /// A company became the active one: asks the server about every payment
  /// of its that this device still waits on (a charge under way when the app
  /// was closed, or crashed). A final answer clears the entry, as
  /// [recoverPending] does. A card that was declined with nobody watching is
  /// returned — still pending, so a notice that never reached the screen is
  /// found again — for [markDeclineTold] and [settleUnseenDecline] once the
  /// user has been told (App Review 5.12). Nothing is asked while a card is being charged.
  ///
  /// A server from before decline answers never says `declined`: its
  /// entries wait, as before, for the invoice's own check.
  Future<List<UnseenDecline>> sweepPending(String companyId) async {
    if (_charges.isNotEmpty) return const [];
    final declined = <UnseenDecline>[];
    for (final e in _pending().entries.toList()) {
      final entry = e.value;
      if (entry is! Map || entry['company'] != companyId) continue;
      final invoiceId = entry['invoice'];
      if (invoiceId is! String || invoiceId.isEmpty) continue;
      try {
        final result = await _repo.complete(
          companyId,
          e.key,
          invoiceId: invoiceId,
        );
        if (isFinalCompletion(result.status)) {
          await clearPending(e.key);
        } else if (result.declined) {
          final number = entry['number'];
          declined.add(
            UnseenDecline(
              companyId: companyId,
              invoiceId: invoiceId,
              invoiceNumber: number is String ? number : '',
              paymentIntentId: e.key,
              told: entry['told'] == true,
            ),
          );
        }
      } catch (e) {
        // Offline, or another company by now: asked again next time.
        _log.fine('pending sweep: ${e.runtimeType}');
      }
    }
    return declined;
  }

  /// The user has been told about [decline]: remembered on the entry, so
  /// one whose cancel hasn't gone through yet is never told a second time.
  Future<void> markDeclineTold(UnseenDecline decline) async {
    final pending = _pending();
    final entry = pending[decline.paymentIntentId];
    if (entry is! Map) return;
    pending[decline.paymentIntentId] = {...entry, 'told': true};
    await _savePending(pending);
  }

  /// After the user was told about [decline]: its PaymentIntent is cancelled
  /// (the invoice is free for another payment), and the entry is forgotten
  /// only on a final answer — `canceled`, or `recorded` if the card turned
  /// out charged after all. While the server says anything else (recording,
  /// processing), or the cancel can't be sent, the entry stays: the next
  /// sweep asks again, and tells nothing twice ([UnseenDecline.told]).
  Future<void> settleUnseenDecline(UnseenDecline decline) async {
    try {
      final result = await _repo.cancel(
        decline.companyId,
        decline.paymentIntentId,
        invoiceId: decline.invoiceId,
      );
      if (isFinalCompletion(result.status)) {
        await clearPending(decline.paymentIntentId);
      }
    } catch (e) {
      _log.fine('unseen decline cancel: ${e.runtimeType}');
    }
  }

  /// A `complete` answer after which nothing more will happen to the charge.
  static bool isFinalCompletion(String status) => const {
    'recorded',
    'unapplied',
    'canceled',
    'failed',
    'rejected',
    'orphaned',
  }.contains(status);

  /// Why the feature is, or isn't, here for [companyId] — Device Settings
  /// says so in words.
  TerminalConfigState configState(String companyId) {
    if (!platformReady) return TerminalConfigState.unavailable;
    if (!_canCreatePayment()) return TerminalConfigState.noPermission;
    final entry = _configs[companyId];
    if (entry == null || (entry.loading && entry.config == null)) {
      return TerminalConfigState.loading;
    }
    if (entry.unsupported) return TerminalConfigState.serverTooOld;
    final config = entry.config;
    if (config == null) return TerminalConfigState.unreachable;
    if (!config.enabled) return TerminalConfigState.switchedOff;
    if (config.gateways.isEmpty) return TerminalConfigState.notEnabled;
    if (config.usableGateway == null) {
      return TerminalConfigState.accountInactive;
    }
    if (!config.planOk) return TerminalConfigState.planRequired;
    return TerminalConfigState.ready;
  }

  /// What this phone can do, asked again — after a resume, or before a press
  /// that needs location services. Never prompts.
  Future<TerminalDeviceSupport> refreshDevice() async {
    try {
      final device = await _platform.deviceSupport();
      _device = lastKnownDevice = device;
      _deviceLoading = Future.value();
      return device;
    } catch (_) {
      return _device ?? TerminalDeviceSupport.none;
    }
  }

  /// The connected reader and the Stripe account it was connected under.
  TerminalReader? get reader => _reader;
  TerminalReader? _reader;
  String? _account;

  /// What this phone can do; null until asked.
  TerminalDeviceSupport? get device => _device;

  /// The last [device] any controller learned, for a check that has no
  /// Services to ask — settings search, which offers the Tap to Pay on
  /// iPhone row only where the row is drawn.
  static TerminalDeviceSupport? lastKnownDevice;

  /// The company's answer, or null while unknown or unsupported.
  TerminalConfig? configFor(String companyId) => _configs[companyId]?.config;

  bool _canCreatePayment() =>
      _auth.session.value?.currentCompany?.can('create_payment') ?? false;

  /// Asks the server (and this phone) when nothing cheaper rules the
  /// feature out. Never throws and never reports. A server without the route
  /// answers 404 — "not here", remembered for the session; any other failure
  /// is tried again after [failedConfigRetry], and an answer is refreshed
  /// after [configLifetime].
  void ensureConfig(String companyId) {
    if (!platformReady || !_canCreatePayment()) return;
    final entry = _configs[companyId];
    if (entry != null) {
      if (entry.loading || entry.unsupported) return;
      final age = _clock().difference(entry.fetchedAt);
      if (age < (entry.failed ? failedConfigRetry : configLifetime)) return;
    }
    unawaited(_load(companyId, keep: entry?.config));
  }

  /// Re-reads the company's answer — after an admin acknowledged the
  /// surcharge or created a Location.
  ///
  /// A load already under way may have been asked before the change this
  /// caller made (an acknowledgement, a new Location): it is waited out,
  /// then the config is read again.
  Future<TerminalConfig?> refreshConfig(String companyId) async {
    final running = _loading[companyId];
    if (running != null) await running;
    // The last answer stands while this one loads, and if it fails.
    await _load(companyId, keep: _configs[companyId]?.config);
    return configFor(companyId);
  }

  final Map<String, Future<void>> _loading = {};

  Future<void> _load(String companyId, {TerminalConfig? keep}) {
    final load = _loadOnce(companyId, keep: keep);
    _loading[companyId] = load;
    return load.whenComplete(() {
      if (identical(_loading[companyId], load)) _loading.remove(companyId);
    });
  }

  Future<void> _loadOnce(String companyId, {TerminalConfig? keep}) async {
    final entry = _configs[companyId] = _ConfigEntry(_clock())..config = keep;
    _deviceLoading ??= _platform
        .deviceSupport()
        .then((d) => _device = lastKnownDevice = d)
        .catchError((Object _) => _device = TerminalDeviceSupport.none);
    try {
      final config = await _repo.config(companyId);
      await _deviceLoading;
      if (!identical(_configs[companyId], entry)) return;
      entry
        ..config = config
        ..failed = false;
    } catch (e) {
      entry.failed = true;
      _log.fine('terminal/config unavailable for $companyId: ${e.runtimeType}');
      // An older server: forget any answer. Anything else keeps the last one.
      entry.unsupported = e is ServerException && e.statusCode == 404;
      if (entry.unsupported) entry.config = null;
    }
    entry
      ..loading = false
      ..fetchedAt = _clock();
    if (!_disposed && identical(_configs[companyId], entry)) {
      notifyListeners();
    }
  }

  /// Apple's "How to Tap" explainer is still owed before this account's first
  /// Tap to Pay on iPhone collection (docs/in-person-payments.md).
  bool get howToTapDue => !(_prefs.read(DevicePrefKeys.howToTapShown) ?? false);

  Future<void> markHowToTapShown() =>
      _prefs.write(DevicePrefKeys.howToTapShown, true);

  /// Tap to Pay on iPhone was turned on here, through to Ready, on this
  /// account (`DevicePrefKeys.tapToPayAnnounced`).
  bool get tapToPayAnnounced =>
      _prefs.read(DevicePrefKeys.tapToPayAnnounced) ?? false;

  Future<void> markTapToPayAnnounced() =>
      _prefs.write(DevicePrefKeys.tapToPayAnnounced, true);

  /// Someone here can finish turning Tap to Pay on iPhone on for [companyId]
  /// — the facts the invoice's action is offered on, without an invoice: an
  /// iPhone that can, the platform, `create_payment`, the release flag, the
  /// Pro plan, and a Stripe gateway in an iPhone country (Card present on or
  /// off), or for an admin with none a company in an iPhone country. For the
  /// enable screen's entry points (Device Settings, the checklist,
  /// onboarding). An iOS Apple wants updated still counts: those entry
  /// points then lead to the update message (1.4).
  bool canSetUpTapToPayOnIPhone(String companyId) {
    if (!_tapToPayIPhoneDevice || !platformReady || !_canCreatePayment()) {
      return false;
    }
    final config = configFor(companyId);
    // A hosted plan below Pro takes no card payments in person.
    if (config == null || !config.enabled || !config.planOk) return false;
    final iPhoneGateway = config.gateways.any(
      (g) =>
          g.cardPaymentsActive &&
          kTapToPayIPhoneCountries.contains(g.accountCountry),
    );
    final setup = config.setupGateways.any(
      (g) => kTapToPayIPhoneCountries.contains(g.accountCountry),
    );
    final newAdmin =
        _isAdmin() &&
        config.gateways.isEmpty &&
        config.setupGateways.isEmpty &&
        kTapToPayIPhoneCountries.contains(config.companyCountry);
    return iPhoneGateway || setup || newAdmin;
  }

  /// How a card can be read for [gateway] on this phone.
  TerminalReaderChoice readerChoiceFor(String accountCountry) {
    final device = _device;
    return terminalReaderChoice(
      tapToPayDevice: device?.tapToPay ?? false,
      osUpdateRequired: device?.osUpdateRequired ?? false,
      iPhone: _iPhone,
      accountCountry: accountCountry,
      bluetoothDevice: device?.bluetooth ?? false,
      readerUsed: _readerUsed || _reader?.kind == TerminalReaderKind.bluetooth,
    );
  }

  TerminalAvailability availabilityFor(String companyId, Invoice invoice) {
    final config = configFor(companyId);
    return terminalAvailability(
      platformReady: platformReady,
      canCreatePayment: _canCreatePayment(),
      invoice: invoice,
      configEnabled: config?.enabled ?? false,
      planOk: config?.planOk ?? false,
      accountCountry: config?.usableGateway?.accountCountry,
      readers: readerChoiceFor,
      tapToPayIPhone: _tapToPayIPhoneDevice,
      setupCountries: [
        for (final g in config?.setupGateways ?? const <TerminalSetupGateway>[])
          g.accountCountry,
      ],
      isAdmin: _isAdmin(),
      noStripeGateway:
          config != null &&
          config.gateways.isEmpty &&
          config.setupGateways.isEmpty,
      companyCountry: config?.companyCountry ?? '',
    );
  }

  /// The action [availabilityFor] offers is Tap to Pay on iPhone — named and
  /// drawn as Apple requires — rather than a Bluetooth reader.
  bool offersTapToPayOnIPhone(String companyId) {
    if (!_tapToPayIPhoneDevice) return false;
    final gateway = configFor(companyId)?.usableGateway;
    return gateway == null ||
        readerChoiceFor(gateway.accountCountry) ==
            TerminalReaderChoice.tapToPay ||
        (configFor(companyId)?.setupGateways.any(
              (g) => kTapToPayIPhoneCountries.contains(g.accountCountry),
            ) ??
            false);
  }

  /// An iPhone that can take Tap to Pay on iPhone — on an iOS Apple may
  /// still want updated ([TerminalDeviceSupport.osUpdateRequired]).
  bool get _tapToPayIPhoneDevice => _iPhone && (_device?.tapToPay ?? false);

  bool _isAdmin() {
    final company = _auth.session.value?.currentCompany;
    return (company?.isAdmin ?? false) || (company?.isOwner ?? false);
  }

  /// Starts the SDK for one Stripe account and Location — a connection token
  /// belongs to exactly one — dropping any reader connected under another.
  Future<void> prepare({
    required String companyId,
    required TerminalGatewayConfig gateway,
    required TerminalLocation location,
  }) async {
    final account = '$companyId/${gateway.companyGatewayId}/${location.id}';
    if (_account != account) _reader = null;
    _account = account;
    _prepared++;
    _tokenError = null;
    await _platform.initialize(
      account: account,
      fetchToken: () async {
        try {
          final token = await _repo.connectionToken(
            companyId,
            companyGatewayId: gateway.companyGatewayId,
            locationId: location.id,
          );
          _tokenError = null;
          return token;
        } catch (e) {
          // The SDK reports a failed token fetch as its own generic error;
          // the server's reason is kept for the screen. A gateway an admin
          // switched off (or a plan, or the platform switch) also means the
          // cached config is out of date.
          _tokenError = e;
          if (e is TerminalServerError) unawaited(refreshConfig(companyId));
          rethrow;
        }
      },
    );
  }

  /// Why the last connection-token fetch failed, if it did — taken once.
  Object? takeTokenError() {
    final e = _tokenError;
    _tokenError = null;
    return e;
  }

  Object? _tokenError;

  /// The reader already connected for this account, if it still is.
  Future<TerminalReader?> connectedReader() async {
    if (_reader == null) return null;
    try {
      final reader = await _platform.connectedReader();
      if (reader == null) _reader = null;
      return reader == null ? null : _reader;
    } catch (_) {
      return _reader = null;
    }
  }

  /// Finds this phone's Tap to Pay reader and connects it.
  Future<TerminalReader> connectTapToPay({
    required TerminalGatewayConfig gateway,
    required TerminalLocation location,
    required String merchantDisplayName,
    required bool isAdmin,
  }) async {
    final found = await _platform
        .discover(
          TerminalReaderKind.tapToPay,
          simulated: _simulated && !gateway.livemode,
        )
        .firstWhere((readers) => readers.isNotEmpty)
        .timeout(const Duration(seconds: 60));
    return _connect(found.first, location, merchantDisplayName, isAdmin);
  }

  // ------------------------------------------------- Tap to Pay on iPhone

  /// Whether this company's Stripe account has accepted Apple's Tap to Pay
  /// on iPhone terms, as the last connect found out; null when unknown. Held
  /// in memory only and dropped on resume and on a reset — Apple is the
  /// source (App Review 1.6), so a press always asks again.
  bool? get tapToPayLinked => _linked;
  bool? _linked;

  /// The company [tapToPayLinked] was found out for.
  String? _linkedCompany;

  /// [tapToPayLinked] for [companyId] only: null when the last answer was
  /// another company's.
  bool? tapToPayLinkedFor(String companyId) =>
      _linkedCompany == companyId ? _linked : null;

  /// Tap to Pay on iPhone works for [companyId] now: its Stripe account has
  /// accepted Apple's terms, or this phone's reader is connected for it.
  /// Per company — never the per-user `tapToPayAnnounced`.
  bool tapToPayReadyFor(String companyId) =>
      tapToPayLinkedFor(companyId) == true ||
      (_reader?.kind == TerminalReaderKind.tapToPay &&
          (_account?.startsWith('$companyId/') ?? false));

  /// Bumped by every [reset]: a connect that started before one gives up.
  int _session = 0;

  /// The [reset] under way, which a connect waits out.
  Future<void>? _resetting;

  final List<_Ensure> _ensuring = [];

  /// A connect is under way (a warm-up's, or a screen's).
  bool get tapToPayConnecting => _ensuring.isNotEmpty;

  /// Connects this phone's Tap to Pay reader for [gateway] and [location],
  /// or answers the one already connected. [admin] lets Apple's terms sheet
  /// open (only an admin may accept them, App Review 3.8).
  ///
  /// Single-flight per account (company, gateway, Location) and mode: a
  /// second call for the same shares the first, and an `admin: false` call
  /// shares an admin one for the same account. Any other call waits for
  /// every connect that came before it, then runs its own — an admin call
  /// after a quiet one runs again so the terms can open, and a call for
  /// another gateway never takes a reader connected for the wrong one.
  ///
  /// Bound to the session and company it was called in: it waits out a
  /// [reset] under way, and gives up (`sessionExpired`) when one starts or
  /// the company changes meanwhile, so a reader never outlives its company.
  Future<TerminalReader> ensureTapToPay({
    required String companyId,
    required TerminalGatewayConfig gateway,
    required TerminalLocation location,
    required String merchantDisplayName,
    required bool admin,
  }) {
    final account = '$companyId/${gateway.companyGatewayId}/${location.id}';
    for (final e in _ensuring) {
      if (e.account == account && (e.admin == admin || e.admin)) {
        return e.future;
      }
    }
    final session = _session;
    final before = [for (final e in _ensuring) e.future];
    final entry = _Ensure(account: account, admin: admin);
    entry.future =
        _ensure(
          session: session,
          before: before,
          companyId: companyId,
          gateway: gateway,
          location: location,
          merchantDisplayName: merchantDisplayName,
          admin: admin,
        ).whenComplete(() {
          _ensuring.remove(entry);
          _notifySoon();
        });
    _ensuring.add(entry);
    _notifySoon();
    return entry.future;
  }

  Future<TerminalReader> _ensure({
    required int session,
    required List<Future<TerminalReader>> before,
    required String companyId,
    required TerminalGatewayConfig gateway,
    required TerminalLocation location,
    required String merchantDisplayName,
    required bool admin,
  }) async {
    void check() {
      if (session != _session ||
          _auth.session.value?.currentCompanyId != companyId) {
        throw const TerminalError(TerminalErrorCode.sessionExpired, 'reset');
      }
    }

    // One connect at a time, in the order they were asked for.
    for (final earlier in before) {
      try {
        await earlier;
      } catch (_) {}
    }
    while (_resetting != null) {
      await _resetting;
    }
    check();
    await prepare(companyId: companyId, gateway: gateway, location: location);
    check();
    final connected = await connectedReader();
    check();
    if (connected != null && connected.kind == TerminalReaderKind.tapToPay) {
      _linked = true;
      _linkedCompany = companyId;
      return connected;
    }
    try {
      final reader = await connectTapToPay(
        gateway: gateway,
        location: location,
        merchantDisplayName: merchantDisplayName,
        isAdmin: admin,
      );
      try {
        check();
      } catch (_) {
        // Connected for a company that is gone: it never serves the next.
        if (identical(_reader, reader)) _reader = null;
        rethrow;
      }
      _linked = true;
      _linkedCompany = companyId;
      return reader;
    } on TerminalError catch (e) {
      if (session == _session && e.code == TerminalErrorCode.termsNotAccepted) {
        _linked = false;
        _linkedCompany = companyId;
      }
      rethrow;
    } finally {
      if (session == _session) _setProgress(null);
    }
  }

  /// [tapToPayConnecting] changed: told after the current task, so a connect
  /// started from a build never notifies during it.
  void _notifySoon() => scheduleMicrotask(() {
    if (!_disposed) notifyListeners();
  });

  /// Lets go of Tap to Pay for a Bluetooth reader: waits for every connect
  /// under way (a warm-up's), then disconnects a Tap to Pay reader. Never
  /// throws.
  Future<void> releaseTapToPay() async {
    for (final e in List.of(_ensuring)) {
      try {
        await e.future;
      } catch (_) {}
    }
    if (_reader?.kind == TerminalReaderKind.tapToPay) await disconnect();
  }

  int _screens = 0;

  /// A collect (or enable) screen is open: it prepares the reader itself, so
  /// no warm-up starts meanwhile. Call the result when it closes.
  VoidCallback holdWarmUp() {
    _screens++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _screens--;
    };
  }

  bool _warming = false;

  /// Gets Tap to Pay on iPhone ready ahead of the first press (App Review
  /// 1.5 and 5.6), on an iPhone only. Stops at the first check that fails —
  /// a capable phone on a current enough iOS, the platform, a usable
  /// gateway in an iPhone country with a Location, location already
  /// allowed, nothing connected or connecting, no collect screen open, an
  /// account not known to be unlinked — then connects without the terms
  /// (`admin: false`). Never prompts, shows a sheet or toasts, never throws.
  ///
  /// One at a time: a call while one runs is remembered, and runs once that
  /// one ends if the session or the company changed meanwhile — a company
  /// switch during a slow warm-up still gets its own.
  Future<void> warmUp(String companyId) async {
    if (!_iPhone || _disposed) return;
    if (_warming) {
      _warmAgain = companyId;
      return;
    }
    _warming = true;
    final session = _session;
    try {
      await _warmUp(companyId);
    } catch (e) {
      _log.fine('warm-up stopped: ${e.runtimeType}');
    } finally {
      _warming = false;
    }
    final again = _warmAgain;
    _warmAgain = null;
    if (again != null &&
        !_disposed &&
        (again != companyId || session != _session)) {
      await warmUp(again);
    }
  }

  /// The company a warm-up asked for while another ran.
  String? _warmAgain;

  Future<void> _warmUp(String companyId) async {
    final session = _session;
    bool stale() =>
        _disposed ||
        session != _session ||
        _auth.session.value?.currentCompanyId != companyId;
    final device = await refreshDevice();
    if (stale() || !device.tapToPay || device.osUpdateRequired) return;
    if (!platformReady || !_canCreatePayment()) return;
    // The same rules as anywhere else: an older server's 404 is not asked
    // again, and a failed fetch waits its minute.
    ensureConfig(companyId);
    final running = _loading[companyId];
    if (running != null) await running;
    if (stale()) return;
    final config = configFor(companyId);
    if (config == null || !config.enabled) return;
    TerminalGatewayConfig? gateway;
    for (final g in config.gateways) {
      if (g.cardPaymentsActive &&
          g.locations.isNotEmpty &&
          kTapToPayIPhoneCountries.contains(g.accountCountry)) {
        gateway = g;
        break;
      }
    }
    if (gateway == null) return;
    final permission = await _platform.permissionStatus(
      TerminalReaderKind.tapToPay,
    );
    if (stale() || permission != TerminalPermission.granted) return;
    if (_reader != null || tapToPayConnecting || _screens > 0) return;
    if (_linked == false) return;
    await ensureTapToPay(
      companyId: companyId,
      gateway: gateway,
      location: gateway.locations.first,
      merchantDisplayName: _auth.session.value?.currentCompany?.name ?? '',
      admin: false,
    );
  }

  /// [warmUp] once the frame after a company switch has drawn, so it never
  /// competes with the first paint.
  Future<void> warmUpAfterFirstFrame(String companyId) async {
    if (!_iPhone) return;
    try {
      await (_afterFrame?.call() ?? SchedulerBinding.instance.endOfFrame);
    } catch (_) {
      return;
    }
    await warmUp(companyId);
  }

  /// The app came back to the foreground: what Apple says may have changed
  /// (terms accepted on another phone, location allowed in Settings), so the
  /// linked state is forgotten, then the reader is warmed up again.
  Future<void> onResumed(String? companyId) async {
    if (!_iPhone) return;
    _linked = null;
    if (companyId == null || companyId.isEmpty) return;
    await warmUp(companyId);
  }

  /// Bluetooth readers in range, for the reader sheet.
  Stream<List<TerminalReader>> discoverBluetooth(
    TerminalGatewayConfig gateway,
  ) => _platform.discover(
    TerminalReaderKind.bluetooth,
    simulated: _simulated && !gateway.livemode,
  );

  Future<TerminalReader> connectBluetooth(
    TerminalReader reader, {
    required TerminalLocation location,
    required String merchantDisplayName,
  }) async {
    final connected = await _connect(
      reader,
      location,
      merchantDisplayName,
      false,
    );
    unawaited(noteReaderUsed());
    return connected;
  }

  Future<TerminalReader> _connect(
    TerminalReader reader,
    TerminalLocation location,
    String merchantDisplayName,
    bool isAdmin,
  ) async {
    final connected = await _platform.connect(
      reader,
      locationId: location.id,
      merchantDisplayName: merchantDisplayName,
      tosAcceptancePermitted: isAdmin,
    );
    _reader = connected;
    notifyListeners();
    return connected;
  }

  Future<void> disconnect() async {
    _reader = null;
    notifyListeners();
    try {
      await _platform.disconnect();
    } catch (_) {}
  }

  /// Wraps a confirm and the `complete` after it: nothing [reset]s the SDK
  /// while a card may be being charged.
  Future<T> guardCharge<T>(Future<T> Function() charge) {
    final future = charge();
    final settled = future.then<void>((_) {}, onError: (_) {});
    _charges.add(settled);
    settled.whenComplete(() => _charges.remove(settled));
    return future;
  }

  final Set<Future<void>> _charges = {};

  /// Bumped by every [prepare]: a [reset] that waited leaves a newer
  /// session alone.
  int _prepared = 0;

  /// Forgets every company's answer and the reader, and resets the SDK — a
  /// session end or a company switch. Waits up to a minute for a charge in
  /// flight to be answered first.
  Future<void> reset() {
    final done = Completer<void>();
    _resetting = done.future;
    // The session's own state goes now, so nothing new starts on it.
    _session++;
    _ensuring.clear();
    _linked = null;
    _setProgress(null);
    unawaited(
      _reset().whenComplete(() {
        if (identical(_resetting, done.future)) _resetting = null;
        done.complete();
      }),
    );
    return done.future;
  }

  Future<void> _reset() async {
    _configs.clear();
    _reader = null;
    _account = null;
    final prepared = _prepared;
    if (!_disposed) notifyListeners();
    // Until no charge is left: one that ends may have started another (a
    // read again after finalize). Real time, whatever the clock says.
    // Longer than the facade's bound on a confirm (2 minutes), so a confirm
    // is always answered before the reader goes.
    const limit = Duration(seconds: 150);
    final waited = Stopwatch()..start();
    while (_charges.isNotEmpty) {
      final left = limit - waited.elapsed;
      if (left <= Duration.zero) {
        _log.warning('reset while a card charge was still unanswered');
        break;
      }
      try {
        await Future.any(_charges.toList()).timeout(left);
      } catch (_) {}
    }
    // Nothing to reset when no card session was ever opened (most sign-outs).
    // A newer session prepared while this waited has already reset the SDK
    // for its own account: leave it alone.
    if (!platformReady || prepared == 0 || _prepared != prepared) return;
    try {
      await _platform.reset();
    } catch (_) {}
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _prefs.removeListener(_syncPrefs);
    _listeners.clear();
    _progress.dispose();
    super.dispose();
  }
}

/// A card payment that was declined while nobody was watching
/// ([TerminalController.sweepPending]).
@immutable
class UnseenDecline {
  const UnseenDecline({
    required this.companyId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.paymentIntentId,
    this.told = false,
  });

  final String companyId;
  final String invoiceId;

  /// '' when the entry was written before the number was kept.
  final String invoiceNumber;
  final String paymentIntentId;

  /// The user was already told; only its cancel is still owed.
  final bool told;
}

/// What asking the server about an invoice's pending card payments found.
enum PendingRecovery {
  /// None is left, and none of them was charged.
  none,

  /// None is left, and at least one was charged and has just been recorded:
  /// the invoice's balance isn't what the screen showed.
  recorded,

  /// At least one still can't be answered: it may have been charged.
  unknown,
}

/// Why "Collect card payment" is, or isn't, offered for a company.
enum TerminalConfigState {
  unavailable,
  noPermission,
  loading,
  serverTooOld,
  unreachable,
  switchedOff,
  notEnabled,
  accountInactive,
  planRequired,
  ready,
}

class _ConfigEntry {
  _ConfigEntry(this.fetchedAt);

  DateTime fetchedAt;
  TerminalConfig? config;
  bool loading = true;

  /// The server has no such route: an older one. Not asked again.
  bool unsupported = false;

  /// The last fetch failed (any answer kept is older): asked again sooner.
  bool failed = false;
}

/// One [TerminalController.ensureTapToPay] under way.
class _Ensure {
  _Ensure({required this.account, required this.admin});

  final String account;
  final bool admin;
  late final Future<TerminalReader> future;
}
