import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/domain/gateway_constants.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/terminal/views/tap_to_pay_enable_screen.dart';

/// The end of Stripe onboarding on an iPhone (App Review 3.4): once a Stripe
/// gateway exists — connected, or saved with API keys — Tap to Pay on iPhone
/// is offered straight away, to someone who can finish it. While Stripe is
/// still reviewing the account, the app says so instead.
///
/// Nothing at all — no call, no toast — unless this phone can take Tap to
/// Pay on iPhone (Release builds without Apple's entitlement, iPads, older
/// iPhones and every other platform are unchanged), and nothing once it
/// works for this company. [onlyGatewayId]: offer only when the server's
/// answer lists that gateway (a just-saved one).
Future<void> offerTapToPayOnIPhone(
  BuildContext context, {
  String? onlyGatewayId,
  @visibleForTesting TerminalController? terminalOverride,
}) async {
  if (!isIPhonePlatform()) return;
  final services = context.read<Services>();
  final terminal = terminalOverride ?? services.terminal;
  final companyId = services.auth.session.value?.currentCompanyId ?? '';
  if (companyId.isEmpty || !terminal.platformReady) return;
  final device = terminal.device ?? await terminal.refreshDevice();
  if (!device.tapToPay || !context.mounted) return;
  if (terminal.tapToPayReadyFor(companyId)) return;
  final toasts = Notify.capture(context);
  final pendingText = context.tr('terminal_stripe_approval_pending', {
    'name': tapToPayNameFor(context, 'terminal_stripe_approval_pending'),
  });
  final config = await terminal.refreshConfig(companyId);
  if (config == null || !context.mounted) return;
  // Eligible first (create_payment, the release flag, the plan, a gateway in
  // an iPhone country); only then is "approval pending" worth saying.
  if (!terminal.canSetUpTapToPayOnIPhone(companyId)) return;
  if (onlyGatewayId != null &&
      !config.gateways.any((g) => g.companyGatewayId == onlyGatewayId) &&
      !config.setupGateways.any((g) => g.companyGatewayId == onlyGatewayId)) {
    return;
  }
  bool inIPhoneCountry(String country) =>
      kTapToPayIPhoneCountries.contains(country);
  final active = config.gateways.any(
    (g) => g.cardPaymentsActive && inIPhoneCountry(g.accountCountry),
  );
  final pending =
      !active &&
      config.setupGateways.any((g) => inIPhoneCountry(g.accountCountry)) &&
      !config.setupGateways.any(
        (g) => g.cardPaymentsActive && inIPhoneCountry(g.accountCountry),
      );
  if (pending) {
    toasts?.info(pendingText);
    return;
  }
  await showTapToPayEnableScreen(context);
}

/// Stripe Connect opens in the in-app browser, watched, only on an iPhone
/// that can take Tap to Pay on iPhone and someone who can finish turning it
/// on ([TerminalController.canSetUpTapToPayOnIPhone]). Everyone else keeps
/// the system browser, exactly as before.
Future<bool> watchesStripeConnect(
  TerminalController terminal, {
  required String gatewayKey,
  required String companyId,
  bool? iPhone,
}) async {
  if (!(iPhone ?? isIPhonePlatform()) ||
      gatewayKey != kGatewayStripeConnect ||
      !terminal.platformReady) {
    return false;
  }
  try {
    final device = terminal.device ?? await terminal.refreshDevice();
    if (!device.tapToPay) return false;
    if (terminal.configFor(companyId) == null) {
      await terminal.refreshConfig(companyId);
    }
  } catch (_) {
    return false;
  }
  return terminal.canSetUpTapToPayOnIPhone(companyId);
}

/// The company's Stripe Connect gateways as id → `updatedAt`: the server
/// reuses an existing one when Connect completes, so a change counts as much
/// as a new one.
typedef StripeGatewaySnapshot = Map<String, int>;

/// Watches for Stripe Connect to finish while it is open in the in-app
/// browser, which says nothing when it's done: every [interval] it takes a
/// [snapshot]; once a gateway is new, or its `updatedAt` moved, it closes the
/// browser ([closeBrowser]) and answers true. False when [timeout] passes,
/// [stillWanted] says no (the screen left, the company changed), or
/// [cancel] is called first.
class StripeConnectWatcher {
  StripeConnectWatcher({
    required this.snapshot,
    required this.closeBrowser,
    this.stillWanted,
    this.interval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 10),
  });

  final Future<StripeGatewaySnapshot> Function() snapshot;
  final Future<void> Function() closeBrowser;
  final bool Function()? stillWanted;
  final Duration interval;
  final Duration timeout;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  bool get _stop => _cancelled || stillWanted?.call() == false;

  Future<bool> watch({required StripeGatewaySnapshot before}) async {
    final waited = Stopwatch()..start();
    while (!_stop && waited.elapsed < timeout) {
      await Future<void>.delayed(interval);
      if (_stop) return false;
      StripeGatewaySnapshot now;
      try {
        now = await snapshot();
      } catch (_) {
        continue;
      }
      if (_stop) return false;
      final changed = now.entries.any((e) => before[e.key] != e.value);
      if (changed) {
        try {
          await closeBrowser();
        } catch (_) {}
        return true;
      }
    }
    return false;
  }
}
