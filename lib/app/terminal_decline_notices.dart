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
/// about ([TerminalController.sweepPending]). What was declined is told
/// once, in one toast with Open (to the invoice; to the invoices when there
/// are several), and only while the app is in front. Only then is each
/// PaymentIntent cancelled, and its entry forgotten once the server has
/// answered for good — so a notice that couldn't be shown (the app locked,
/// in the background, or closed again) is found at the next activation, and
/// one whose cancel is still owed is never told twice.
///
/// `late` on `Services` for the same reason as `DeepLinkRouter`: the router
/// it opens the invoice with exists only once the app is built, so the app
/// state calls [attach].
class TerminalDeclineNotices with WidgetsBindingObserver {
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

  /// Long enough to be read by someone who was doing something else: the
  /// notice arrives unasked.
  static const shownAtLeast = Duration(seconds: 12);

  final TerminalController _terminal;
  final ToastController _toasts;
  final ValueListenable<AuthSession?> _session;
  final ArrivalGate _gate;
  final _log = Logger('TerminalDeclineNotices');

  void Function(String location)? _go;
  BuildContext? Function()? _contextOf;
  bool _observing = false;

  /// Found declined, not yet told.
  final List<UnseenDecline> _held = [];

  /// Told, their cancel still on its way: a sweep that finds one again (a
  /// company switched away and back) neither tells nor cancels it twice.
  final Set<String> _settling = {};

  /// One sweep at a time, in order: two at once would tell the same
  /// decline twice.
  Future<void> _sweeping = Future<void>.value();

  void attach({
    required void Function(String location) go,
    required BuildContext? Function() contextOf,
  }) {
    _go = go;
    _contextOf = contextOf;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _showHeld();
  }

  /// Stops listening for the app coming back in front (tests).
  void detach() {
    if (!_observing) return;
    _observing = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }

  /// The app is back in front: what was held for that is told now.
  void onResumed() => _showHeld();

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
      final id = decline.paymentIntentId;
      if (_settling.contains(id)) continue;
      if (decline.told) {
        // Told before; its cancel never went through. Only that is owed.
        _settle(decline);
        continue;
      }
      if (_held.every((h) => h.paymentIntentId != id)) _held.add(decline);
    }
    _showHeld();
  }

  /// A session end: nothing held belongs to the next one.
  void reset() {
    _held.clear();
    _gate.cancel();
  }

  /// Cancels [decline], after noting it told when [tell]. Marked as being
  /// settled at once — before anything is awaited — so a sweep in between
  /// can't find it again and tell it twice.
  void _settle(UnseenDecline decline, {bool tell = false}) {
    final id = decline.paymentIntentId;
    if (!_settling.add(id)) return;
    unawaited(() async {
      try {
        if (tell) await _terminal.markDeclineTold(decline);
        await _terminal.settleUnseenDecline(decline);
      } finally {
        _settling.remove(id);
      }
    }());
  }

  void _showHeld() {
    if (_held.isEmpty) return;
    if (!_gate.isOpen) {
      // Never over the lock screen: once the user is through.
      _gate.notifyWhenOpen(_showHeld);
      return;
    }
    // Only while the app is in front: a toast that ran out in the
    // background was told to nobody. [onResumed] comes back here.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final context = _contextOf?.call();
    final loc = context == null ? null : Localization.of(context);
    if (loc == null) {
      // Before the first frame: [attach], or the next activation, tries
      // again — the entries are still pending.
      return;
    }
    final current = _session.value?.currentCompany?.id;
    // Another company's by now: left pending for its next activation.
    final mine = [
      for (final d in _held)
        if (d.companyId == current) d,
    ];
    _held.clear();
    if (mine.isEmpty) return;
    final companyId = mine.first.companyId;
    final one = mine.length == 1 ? mine.single : null;
    final message = one == null
        ? loc.lookup('terminal_unseen_declines', {'count': '${mine.length}'})
        : one.invoiceNumber.isEmpty
        ? loc.lookup('terminal_unseen_decline_plain')
        : loc.lookup('terminal_unseen_decline', {'number': one.invoiceNumber});
    // One toast for everything found: the host shows only the newest on a
    // phone, so one each would hide all but the last.
    _toasts.show(
      variant: NotifyVariant.info,
      message: message,
      atLeast: shownAtLeast,
      action: NotifyAction(loc.lookup('open'), () {
        // The toast can outlive a company switch; the invoices are only the
        // company's they were declined in.
        if (_session.value?.currentCompany?.id != companyId) return;
        _go?.call(one == null ? '/invoices' : '/invoices/${one.invoiceId}');
      }),
    );
    for (final decline in mine) {
      _settle(decline, tell: true);
    }
  }
}
