import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'package:admin/app/arrival_gate.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';

/// Tells the user about a card payment that was declined while nobody was
/// watching — the app closed, or crashed, while the card was being charged
/// (App Review 5.12; docs/in-person-payments.md).
///
/// At company activation every payment this device still waits on is asked
/// about ([TerminalController.sweepPending]). A declined one is told once, in
/// a toast with Open (to the invoice); only then is its PaymentIntent
/// cancelled and the entry forgotten, so a notice that couldn't be shown —
/// the app locked, or closed again — is found at the next activation.
///
/// `late` on `Services` for the same reason as `DeepLinkRouter`: the router
/// it opens the invoice with exists only once the app is built, so the app
/// state calls [attach].
class TerminalDeclineNotices {
  TerminalDeclineNotices({
    required TerminalController terminal,
    required ToastController toasts,
    required ValueListenable<AuthSession?> session,
    required ValueListenable<ApiCredentials?> credentials,
    required ValueListenable<bool> requiresBiometricUnlock,
  }) : _terminal = terminal,
       _toasts = toasts,
       _session = session,
       _gate = ArrivalGate(
         session: session,
         credentials: credentials,
         requiresBiometricUnlock: requiresBiometricUnlock,
       );

  final TerminalController _terminal;
  final ToastController _toasts;
  final ValueListenable<AuthSession?> _session;
  final ArrivalGate _gate;
  final _log = Logger('TerminalDeclineNotices');

  void Function(String location)? _go;
  BuildContext? Function()? _contextOf;

  /// Found declined, not yet told.
  final List<UnseenDecline> _held = [];

  /// One sweep at a time, in order: two at once would tell the same
  /// decline twice.
  Future<void> _sweeping = Future<void>.value();

  void attach({
    required void Function(String location) go,
    required BuildContext? Function() contextOf,
  }) {
    _go = go;
    _contextOf = contextOf;
    _showHeld();
  }

  /// [companyId] became the active company.
  Future<void> sweep(String companyId) =>
      _sweeping = _sweeping.then((_) => _sweep(companyId));

  Future<void> _sweep(String companyId) async {
    final List<UnseenDecline> found;
    try {
      found = await _terminal.sweepPending(companyId);
    } catch (e) {
      _log.fine('sweep failed: ${e.runtimeType}');
      return;
    }
    for (final decline in found) {
      if (_held.every((h) => h.paymentIntentId != decline.paymentIntentId)) {
        _held.add(decline);
      }
    }
    _showHeld();
  }

  /// A session end: nothing held belongs to the next one.
  void reset() {
    _held.clear();
    _gate.cancel();
  }

  void _showHeld() {
    if (_held.isEmpty) return;
    if (!_gate.isOpen) {
      // Never over the lock screen: once the user is through.
      _gate.notifyWhenOpen(_showHeld);
      return;
    }
    final context = _contextOf?.call();
    final loc = context == null ? null : Localization.of(context);
    if (loc == null) {
      // Before the first frame: [attach], or the next activation, tries
      // again — the entries are still pending.
      return;
    }
    final current = _session.value?.currentCompany?.id;
    final held = List.of(_held);
    _held.clear();
    for (final decline in held) {
      // Another company's by now: left pending for its next activation.
      if (decline.companyId != current) continue;
      _toasts.info(
        decline.invoiceNumber.isEmpty
            ? loc.lookup('terminal_unseen_decline_plain')
            : loc.lookup('terminal_unseen_decline', {
                'number': decline.invoiceNumber,
              }),
        action: NotifyAction(loc.lookup('open'), () {
          // The toast outlives a company switch by seconds at most; the
          // invoice is only the company's it was declined in.
          if (_session.value?.currentCompany?.id != decline.companyId) return;
          _go?.call('/invoices/${decline.invoiceId}');
        }),
      );
      unawaited(_terminal.settleUnseenDecline(decline));
    }
  }
}
