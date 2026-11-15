import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/terminal/views/tap_to_pay_enable_screen.dart';

/// The end of Stripe onboarding on an iPhone (App Review 3.4): once a Stripe
/// gateway exists — connected, or saved with API keys — Tap to Pay on iPhone
/// is offered straight away, to someone who can finish it. While Stripe is
/// still reviewing the account, the app says so instead. Nothing anywhere
/// else, and nothing once it is set up.
Future<void> offerTapToPayOnIPhone(BuildContext context) async {
  if (!isIPhonePlatform()) return;
  final services = context.read<Services>();
  final terminal = services.terminal;
  final companyId = services.auth.session.value?.currentCompanyId ?? '';
  if (companyId.isEmpty || !terminal.platformReady) return;
  if (terminal.tapToPayAnnounced || terminal.tapToPayLinked == true) return;
  final toasts = Notify.capture(context);
  final pendingText = context.tr('terminal_stripe_approval_pending', {
    'name': tapToPayNameFor(context, 'terminal_stripe_approval_pending'),
  });
  final config = await terminal.refreshConfig(companyId);
  if (config == null || !config.enabled || !context.mounted) return;
  bool inIPhoneCountry(String country) =>
      kTapToPayIPhoneCountries.contains(country);
  final pending =
      !config.gateways.any(
        (g) => g.cardPaymentsActive && inIPhoneCountry(g.accountCountry),
      ) &&
      (config.gateways.any(
            (g) => !g.cardPaymentsActive && inIPhoneCountry(g.accountCountry),
          ) ||
          config.setupGateways.any(
            (g) => !g.cardPaymentsActive && inIPhoneCountry(g.accountCountry),
          ));
  if (pending) {
    toasts?.info(pendingText);
    return;
  }
  if (!terminal.canSetUpTapToPayOnIPhone(companyId)) return;
  await showTapToPayEnableScreen(context);
}

/// Watches for a Stripe gateway to appear while Stripe Connect is open in
/// the in-app browser, which says nothing when it's done: every [interval]
/// it asks [countStripeGateways]; once there are more than [before], it
/// closes the browser ([closeBrowser]) and answers true. False when
/// [timeout] passes or [cancel] is called first.
class StripeConnectWatcher {
  StripeConnectWatcher({
    required this.countStripeGateways,
    required this.closeBrowser,
    this.interval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 30),
  });

  final Future<int> Function() countStripeGateways;
  final Future<void> Function() closeBrowser;
  final Duration interval;
  final Duration timeout;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<bool> watch({required int before}) async {
    final waited = Stopwatch()..start();
    while (!_cancelled && waited.elapsed < timeout) {
      await Future<void>.delayed(interval);
      if (_cancelled) return false;
      int count;
      try {
        count = await countStripeGateways();
      } catch (_) {
        continue;
      }
      if (_cancelled) return false;
      if (count > before) {
        try {
          await closeBrowser();
        } catch (_) {}
        return true;
      }
    }
    return false;
  }
}
