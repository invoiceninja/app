import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/models/api/terminal_models.dart';
import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_setup.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';

/// Where turning on Tap to Pay on iPhone stands (App Review 3.6, 3.9).
enum TapToPayEnableStage {
  /// What will happen, before anything is asked.
  intro,

  /// Getting the reader ready — Apple's terms sheet may be up meanwhile.
  preparing,

  /// A step stopped; [TapToPayEnableViewModel.problem] says why.
  failed,

  /// Set up: the invitation to try it (3.9).
  ready,

  /// Not an admin, and the account isn't linked yet (3.8.1).
  askAdmin,
}

/// One step the intro lists; [done] once it no longer needs doing.
enum TapToPayEnableStep { cardPresent, location, terms, learn }

/// Drives `TapToPayEnableScreen`: turning Tap to Pay on iPhone on outside
/// checkout (App Review 3.6, 3.9) — the same steps as the collect screen's
/// button, through the same helpers (`requestTapToPayLocation`,
/// `enableCardPresent`, `TerminalController.ensureTapToPay`), then Ready.
///
/// The connect lives in the controller, so closing the screen never stops
/// it: setup carries on, and the next screen finds the reader ready.
class TapToPayEnableViewModel extends ChangeNotifier {
  TapToPayEnableViewModel({
    required this.companyId,
    required this.companyName,
    required this.isAdmin,
    required this.merchantDisplayName,
    required TerminalController terminal,
    required Future<void> Function(String companyGatewayId) enableCardPresent,
  }) : _terminal = terminal,
       _enableCardPresent = enableCardPresent;

  final String companyId;
  final String companyName;
  final bool isAdmin;
  final String merchantDisplayName;
  final TerminalController _terminal;
  final Future<void> Function(String companyGatewayId) _enableCardPresent;

  TerminalController get terminal => _terminal;

  /// The app's own words before iOS asks for location; set by the screen.
  Future<bool> Function()? askLocation;

  /// The reader is ready: the screen shows Apple's education (4.2).
  Future<void> Function()? onReady;

  TapToPayEnableStage get stage => _stage;
  TapToPayEnableStage _stage = TapToPayEnableStage.intro;

  /// The steps still needed when the screen opened, in order.
  Set<TapToPayEnableStep> get steps => _steps;
  Set<TapToPayEnableStep> _steps = const {};
  final Set<TapToPayEnableStep> _done = {};
  Set<TapToPayEnableStep> get doneSteps => _done;

  /// Why it stopped ([TapToPayEnableStage.failed]).
  CollectProblem? get problem => _problem;
  CollectProblem? _problem;

  /// The stop is location — off for the app, or Location Services off — and
  /// only Settings fixes it.
  bool get needsSettings => _needsSettings;
  bool _needsSettings = false;

  /// The intro is still finding out which steps are needed.
  bool get loading => _loading;
  bool _loading = true;

  /// Working through the steps.
  bool get busy => _busy;
  bool _busy = false;

  TerminalGatewayConfig? _gateway;
  TerminalSetupGateway? _setup;

  /// The Stripe account's country, for the education's PIN paragraph.
  String get accountCountry =>
      _gateway?.accountCountry ?? _setup?.accountCountry ?? '';

  bool _disposed = false;
  Future<void>? _loadFuture;

  /// What is set up already, so the intro lists only what is left. Never
  /// prompts.
  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    _loading = true;
    _notify();
    try {
      // App Review 1.4: below iOS 17.6, say to update — before any prompt
      // or any change to Card present.
      final device = _terminal.device ?? await _terminal.refreshDevice();
      if (_disposed) return;
      if (device.osUpdateRequired) {
        _fail(const CollectProblem(code: TerminalErrorCode.unsupportedOs));
        return;
      }
      if (_terminal.reader?.kind == TerminalReaderKind.tapToPay) {
        // Already connected for this company: nothing left to set up.
        _stage = TapToPayEnableStage.ready;
        unawaited(_terminal.markTapToPayAnnounced());
        return;
      }
      if (!await _pickGateway()) return;
      final permission = await _terminal.platform.permissionStatus(
        TerminalReaderKind.tapToPay,
      );
      if (_disposed) return;
      _steps = {
        if (_gateway == null && _setup != null) TapToPayEnableStep.cardPresent,
        if (permission != TerminalPermission.granted)
          TapToPayEnableStep.location,
        // Only an admin may accept Apple's terms (3.8).
        if (isAdmin && _terminal.tapToPayLinked != true)
          TapToPayEnableStep.terms,
        TapToPayEnableStep.learn,
      };
      if (_gateway == null && !isAdmin) {
        // Card present off: only an admin can turn it on (3.8.1).
        _stage = TapToPayEnableStage.askAdmin;
      }
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// The Stripe gateway in an iPhone country to set up with; false (with the
  /// stage set) when there is none.
  Future<bool> _pickGateway({bool refresh = false}) async {
    TerminalConfig? config = refresh ? null : _terminal.configFor(companyId);
    if (config == null) {
      try {
        config = await _terminal.refreshConfig(companyId);
      } catch (_) {}
    }
    if (_disposed) return false;
    if (config == null) {
      _fail(const CollectProblem(code: TerminalErrorCode.network));
      return false;
    }
    _gateway = config.gateways
        .where(
          (g) =>
              g.cardPaymentsActive &&
              kTapToPayIPhoneCountries.contains(g.accountCountry),
        )
        .firstOrNull;
    _setup = _gateway != null
        ? null
        : config.setupGateways
              .where((g) => kTapToPayIPhoneCountries.contains(g.accountCountry))
              .firstOrNull;
    if (_gateway != null || _setup != null) return true;
    _fail(
      CollectProblem(
        serverCode:
            isAdmin && config.gateways.isEmpty && config.setupGateways.isEmpty
            ? 'connect_stripe_first'
            : TerminalServerError.notEnabled,
      ),
    );
    return false;
  }

  /// "Turn on Tap to Pay on iPhone" and Retry: every step still needed, in
  /// order, straight on to Apple's terms (3.5).
  Future<void> start() async {
    if (_busy || _disposed) return;
    await load();
    if (_disposed || _stage == TapToPayEnableStage.ready) return;
    if (_problem?.code == TerminalErrorCode.unsupportedOs) {
      // Retry looks again: the phone may have been updated meanwhile.
      final device = await _terminal.refreshDevice();
      if (_disposed || device.osUpdateRequired) return;
      _loadFuture = null;
      _problem = null;
      _stage = TapToPayEnableStage.intro;
      await load();
      if (_disposed || _stage != TapToPayEnableStage.intro) return;
    }
    _busy = true;
    _problem = null;
    _needsSettings = false;
    if (_stage == TapToPayEnableStage.failed) {
      _stage = TapToPayEnableStage.intro;
    }
    _notify();
    try {
      await _run();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _run() async {
    // 1. Card present, by an admin.
    if (_gateway == null) {
      final setup = _setup;
      if (setup == null) {
        if (!await _pickGateway(refresh: true)) return;
        if (_gateway == null && _setup == null) return;
      }
      if (_gateway == null) {
        if (!isAdmin) {
          _stage = TapToPayEnableStage.askAdmin;
          return;
        }
        _stage = TapToPayEnableStage.preparing;
        _notify();
        try {
          await _enableCardPresent(_setup!.companyGatewayId);
        } catch (e) {
          _fail(collectProblemOf(e));
          return;
        }
        if (_disposed) return;
        if (!await _pickGateway(refresh: true)) return;
        if (_gateway == null) {
          // Listed with Card present on, but Stripe hasn't let it take cards.
          _fail(
            const CollectProblem(serverCode: TerminalServerError.notEnabled),
          );
          return;
        }
        _done.add(TapToPayEnableStep.cardPresent);
        _stage = TapToPayEnableStage.intro;
        _notify();
      }
    }
    final gateway = _gateway!;

    // 2. Location: the app's word first, then iOS.
    final ask = askLocation;
    final access = await requestTapToPayLocation(
      _terminal,
      askLocation: ask ?? () async => false,
      stillWanted: () => !_disposed,
    );
    if (_disposed) return;
    switch (access) {
      case LocationAccess.servicesOff:
        _needsSettings = true;
        _fail(
          const CollectProblem(
            code: TerminalErrorCode.locationServicesDisabled,
          ),
        );
        return;
      case LocationAccess.blocked:
        _needsSettings = true;
        _fail(const CollectProblem(code: TerminalErrorCode.permissionDenied));
        return;
      case LocationAccess.declined:
        return;
      case LocationAccess.granted:
        _done.add(TapToPayEnableStep.location);
        _notify();
    }

    // 3. The Stripe Location: an admin's is created quietly.
    var location = gateway.locations.firstOrNull;
    if (location == null) {
      if (!isAdmin) {
        _fail(const CollectProblem(serverCode: 'location_needs_admin'));
        return;
      }
      try {
        location = await _terminal.repository.createLocation(
          companyId,
          companyGatewayId: gateway.companyGatewayId,
        );
        unawaited(_terminal.refreshConfig(companyId));
      } catch (e) {
        _fail(collectProblemOf(e));
        return;
      }
      if (_disposed) return;
    }

    // 4. The reader, with Apple's terms if they're owed (3.5, 3.9.1).
    _stage = TapToPayEnableStage.preparing;
    _notify();
    try {
      await _terminal.ensureTapToPay(
        companyId: companyId,
        gateway: gateway,
        location: location,
        merchantDisplayName: merchantDisplayName,
        admin: isAdmin,
      );
    } on TerminalError catch (e) {
      if (_disposed) return;
      if (e.code == TerminalErrorCode.termsNotAccepted && !isAdmin) {
        _stage = TapToPayEnableStage.askAdmin;
        return;
      }
      _fail(collectProblemOf(_terminal.takeTokenError() ?? e));
      return;
    } catch (e) {
      if (_disposed) return;
      _fail(collectProblemOf(_terminal.takeTokenError() ?? e));
      return;
    }
    if (_disposed) return;
    _done.add(TapToPayEnableStep.terms);
    _notify();

    // 5. Apple's education, then Ready (4.2, 3.9).
    await onReady?.call();
    if (_disposed) return;
    _done.add(TapToPayEnableStep.learn);
    _stage = TapToPayEnableStage.ready;
    await _terminal.markTapToPayAnnounced();
  }

  /// Back from Settings: location may be allowed now — run again from there.
  void appResumed() {
    if (_stage != TapToPayEnableStage.failed || !_needsSettings || _busy) {
      return;
    }
    unawaited(start());
  }

  void _fail(CollectProblem problem) {
    _problem = problem;
    _stage = TapToPayEnableStage.failed;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
