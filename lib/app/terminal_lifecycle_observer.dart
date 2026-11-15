import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/repositories/auth_repository.dart';

/// Warms Tap to Pay on iPhone up again when the app comes back to the
/// foreground (App Review 1.5), and forgets what Apple said about the
/// account's terms meanwhile (1.6): [TerminalController.onResumed].
///
/// Only a return from the background counts: iOS also reports `inactive` →
/// `resumed` around a system sheet (Apple's own terms and payment sheets
/// among them), which is no reason to start anything.
class TerminalLifecycleObserver with WidgetsBindingObserver {
  TerminalLifecycleObserver({required this.terminal, required this.auth});

  final TerminalController terminal;
  final AuthRepository auth;

  bool _backgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_backgrounded) return;
    _backgrounded = false;
    unawaited(terminal.onResumed(auth.session.value?.currentCompanyId));
  }
}
