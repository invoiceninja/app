import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:admin/app/lock_after_inactivity_controller.dart';
import 'package:admin/app/user_activity_tracker.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';

/// Decides **when** the soft lock engages: after Device Settings → Security →
/// "Lock after inactivity" of no user activity, time in the background
/// included. What the lock looks like and how it is passed is
/// `SoftLockHost`'s; the lock state itself is `AuthRepository.softLocked`.
/// See docs/soft-lock.md.
///
/// The lock never signs out, so — unlike the web's idle sign-out
/// (`IdleTimeoutController`) — it is safe on every native platform: a running
/// task timer keeps running under it, the outbox keeps draining, and an open
/// editor keeps its unsaved changes. A timer is deliberately not activity (see
/// [UserActivityTracker]), so it never holds the lock off.
///
/// It locks only where the device can verify its owner
/// ([canAuthenticate] — biometrics or the device passcode), re-asked on every
/// resume: a lock nobody could pass would leave Sign out as the only way on.
class SoftLockController with WidgetsBindingObserver {
  SoftLockController({
    required this.session,
    required this.isSignedIn,
    required this.locked,
    required this.lock,
    required this.setting,
    required this.activity,
    required Future<bool> Function() canAuthenticate,
  }) : _canAuthenticateQuery = canAuthenticate {
    _armedAt = activity.now();
    _signedIn = _hasSession;
    _wasLocked = locked.value;
    setting.addListener(_rearm);
    locked.addListener(_onLockedChanged);
    session.addListener(_onSessionChanged);
    _rearm();
  }

  final ValueListenable<AuthSession?> session;

  /// Credentials present — `AuthRepository.isAuthenticated`.
  final bool Function() isSignedIn;

  /// Either lock (`AuthRepository.appLocked`): nothing to do while one is up.
  final ValueListenable<bool> locked;

  /// `AuthRepository.engageSoftLock`.
  final VoidCallback lock;

  final LockAfterInactivityController setting;
  final UserActivityTracker activity;
  final Future<bool> Function() _canAuthenticateQuery;

  Timer? _ticker;
  bool _sourcesAttached = false;
  bool _signedIn = false;
  bool _wasLocked = false;
  bool _disposed = false;

  /// Null until asked; only `true` lets the lock engage.
  bool? _canAuthenticate;

  /// Idle time runs from the later of this and the last activity — reset when
  /// the timeout is armed, when someone signs in, and when a lock is passed
  /// (a Face ID unlock involves no touch, and must not re-lock at once).
  late DateTime _armedAt;

  @visibleForTesting
  bool? get canAuthenticate => _canAuthenticate;

  bool get _hasSession => session.value != null && isSignedIn();

  void _rearm() {
    final timeout = setting.timeout;
    _ticker?.cancel();
    _ticker = null;
    if (timeout == null) {
      if (_sourcesAttached) {
        _sourcesAttached = false;
        activity.detachSources();
      }
      return;
    }
    if (!_sourcesAttached) {
      _sourcesAttached = true;
      activity.attachSources();
    }
    _armedAt = activity.now();
    _refreshCanAuthenticate();
    // Timely without being chatty: a quarter of the span, 5–15 s.
    final ms = (timeout.inMilliseconds ~/ 4).clamp(5000, 15000);
    _ticker = Timer.periodic(Duration(milliseconds: ms), (_) => check());
  }

  void _refreshCanAuthenticate() {
    unawaited(
      _canAuthenticateQuery()
          .then((ok) {
            if (_disposed) return;
            _canAuthenticate = ok;
            check();
          })
          .catchError((Object _) {
            if (!_disposed) _canAuthenticate = false;
          }),
    );
  }

  void _onLockedChanged() {
    final now = locked.value;
    if (_wasLocked && !now) _armedAt = activity.now();
    _wasLocked = now;
  }

  void _onSessionChanged() {
    // The session re-emits on every `companies` row write (each /refresh), so
    // only the signed-out → signed-in edge restarts the clock.
    final signedIn = _hasSession;
    if (signedIn && !_signedIn) _armedAt = activity.now();
    _signedIn = signedIn;
  }

  /// Lock if the span has passed. Called by the ticker and on every lifecycle
  /// change, so time spent in the background — when no timer runs — counts
  /// the moment the app comes back.
  @visibleForTesting
  void check() {
    final timeout = setting.timeout;
    if (timeout == null || _canAuthenticate != true) return;
    if (!_hasSession || locked.value) return;
    final last = activity.lastActivity.isAfter(_armedAt)
        ? activity.lastActivity
        : _armedAt;
    if (activity.now().difference(last) >= timeout) lock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Checked on the way back (hidden and inactive come before resumed on
    // iOS and Android) so the lock is up before the first resumed frame.
    check();
    if (state == AppLifecycleState.resumed && setting.timeout != null) {
      // The passcode may have been removed in the OS settings meanwhile.
      _refreshCanAuthenticate();
    }
  }

  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    setting.removeListener(_rearm);
    locked.removeListener(_onLockedChanged);
    session.removeListener(_onSessionChanged);
    if (_sourcesAttached) activity.detachSources();
  }
}
