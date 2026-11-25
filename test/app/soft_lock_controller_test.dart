import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/lock_after_inactivity_controller.dart';
import 'package:admin/app/soft_lock_controller.dart';
import 'package:admin/app/user_activity_tracker.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';

/// When the soft lock engages (docs/soft-lock.md). Timers are the test
/// binding's fake ones and the clock is hand-driven, so [_Harness.advance]
/// moves both together — `fake_async` is not a dependency here.
void main() {
  group('locks after the span', () {
    testWidgets('with no activity it locks on time, not before', (
      tester,
    ) async {
      final h = await _Harness.start(tester, minutes: 1);
      await h.advance(tester, const Duration(seconds: 45));
      expect(h.locked.value, isFalse);
      await h.advance(tester, const Duration(seconds: 30));
      expect(h.locked.value, isTrue);
      h.dispose();
    });

    testWidgets('Never never locks', (tester) async {
      final h = await _Harness.start(tester, minutes: 0);
      await h.advance(tester, const Duration(hours: 3));
      h.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(h.locked.value, isFalse);
      h.dispose();
    });

    testWidgets('a device that cannot verify its owner is never locked', (
      tester,
    ) async {
      // A lock nobody could pass would leave Sign out as the only way on.
      final h = await _Harness.start(
        tester,
        minutes: 1,
        canAuthenticate: false,
      );
      await h.advance(tester, const Duration(minutes: 5));
      expect(h.locked.value, isFalse);
      h.dispose();
    });

    testWidgets('signed out, nothing locks', (tester) async {
      final h = await _Harness.start(tester, minutes: 1);
      h.session.value = null;
      await h.advance(tester, const Duration(minutes: 5));
      expect(h.locked.value, isFalse);
      h.dispose();
    });

    testWidgets('turning it on starts the span from then', (tester) async {
      final h = await _Harness.start(tester, minutes: 0);
      await h.advance(tester, const Duration(minutes: 10));
      await h.setting.setMinutes(1);
      await tester.pump();
      await h.advance(tester, const Duration(seconds: 45));
      expect(h.locked.value, isFalse, reason: 'not the 10 idle minutes before');
      await h.advance(tester, const Duration(seconds: 30));
      expect(h.locked.value, isTrue);
      h.dispose();
    });
  });

  group('time in the background counts', () {
    testWidgets('coming back after the span locks at once — before resumed', (
      tester,
    ) async {
      final h = await _Harness.start(tester, minutes: 5);
      h.controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      h.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      // Suspended: the clock moves, no timer fires.
      h.clock = h.clock.add(const Duration(minutes: 6));
      h.controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(
        h.locked.value,
        isTrue,
        reason: 'up on the way back, so the first resumed frame is the lock',
      );
      h.dispose();
    });

    testWidgets('a short trip away does not', (tester) async {
      final h = await _Harness.start(tester, minutes: 5);
      h.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.clock = h.clock.add(const Duration(minutes: 2));
      h.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(h.locked.value, isFalse);
      h.dispose();
    });
  });

  group('what counts as activity', () {
    testWidgets('a poke (pointer, markdown edit) restarts the span', (
      tester,
    ) async {
      final h = await _Harness.start(tester, minutes: 1);
      await h.advance(tester, const Duration(seconds: 45));
      h.activity.poke();
      await h.advance(tester, const Duration(seconds: 45));
      expect(h.locked.value, isFalse);
      await h.advance(tester, const Duration(seconds: 30));
      expect(h.locked.value, isTrue);
      h.dispose();
    });

    testWidgets('a hardware key restarts the span', (tester) async {
      final h = await _Harness.start(tester, minutes: 1);
      await h.advance(tester, const Duration(seconds: 45));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await h.advance(tester, const Duration(seconds: 45));
      expect(h.locked.value, isFalse);
      h.dispose();
    });

    testWidgets('a running task timer does not hold the lock off', (
      tester,
    ) async {
      // What a running timer does: tick, repaint, write its own state. None of
      // it is the user, and the lock must still engage — the timer goes on
      // ticking under it.
      final h = await _Harness.start(tester, minutes: 1);
      var ticks = 0;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) => ticks++);
      await h.advance(tester, const Duration(seconds: 75));
      expect(h.locked.value, isTrue);
      final atLock = ticks;
      await h.advance(tester, const Duration(seconds: 10));
      expect(ticks, greaterThan(atLock), reason: 'still running while locked');
      timer.cancel();
      h.dispose();
    });
  });

  testWidgets('passing the lock restarts the span — a Face ID unlock is no '
      'touch, and must not lock again at once', (tester) async {
    final h = await _Harness.start(tester, minutes: 1);
    await h.advance(tester, const Duration(seconds: 75));
    expect(h.locked.value, isTrue);
    await h.advance(tester, const Duration(minutes: 10));
    h.locked.value = false; // the unlock
    await h.advance(tester, const Duration(seconds: 30));
    expect(h.locked.value, isFalse);
    await h.advance(tester, const Duration(seconds: 45));
    expect(h.locked.value, isTrue);
    h.dispose();
  });

  group('the setting', () {
    test('snaps a stored value to an offered choice', () {
      final prefs = DevicePrefsStore(null);
      final setting = LockAfterInactivityController(prefs: prefs);
      expect(setting.minutes, 0);
      expect(setting.timeout, isNull);
      setting.value = 4;
      expect(setting.minutes, 5);
      setting.value = 1000;
      expect(setting.minutes, 60);
      setting.value = -3;
      expect(setting.minutes, 0);
      setting.dispose();
    });
  });
}

class _Harness {
  _Harness._();

  var clock = DateTime.utc(2026, 3, 1, 12);
  final session = ValueNotifier<AuthSession?>(
    const AuthSession(
      baseUrl: 'https://example.com',
      isHosted: true,
      accountId: 'acct1',
      companies: [],
      currentCompanyId: 'co1',
    ),
  );
  final locked = ValueNotifier<bool>(false);
  late final UserActivityTracker activity;
  late final LockAfterInactivityController setting;
  late final SoftLockController controller;

  static Future<_Harness> start(
    WidgetTester tester, {
    required int minutes,
    bool canAuthenticate = true,
  }) async {
    final h = _Harness._();
    h.activity = UserActivityTracker(now: () => h.clock);
    h.setting = LockAfterInactivityController(prefs: DevicePrefsStore(null));
    await h.setting.setMinutes(minutes);
    h.controller = SoftLockController(
      session: h.session,
      isSignedIn: () => h.session.value != null,
      locked: h.locked,
      lock: () => h.locked.value = true,
      setting: h.setting,
      activity: h.activity,
      canAuthenticate: () async => canAuthenticate,
    );
    // The device-auth answer is asynchronous.
    await tester.pump();
    return h;
  }

  Future<void> advance(WidgetTester tester, Duration d) async {
    // In 5 s steps, so the periodic check sees each moment as a real clock
    // would rather than one jump.
    var left = d;
    const step = Duration(seconds: 5);
    while (left > Duration.zero) {
      final s = left < step ? left : step;
      clock = clock.add(s);
      await tester.pump(s);
      left -= s;
    }
  }

  /// In the test body: the binding checks for pending timers before
  /// tear-downs run, and the ticker is periodic.
  void dispose() {
    controller.dispose();
    activity.dispose();
    setting.dispose();
  }
}
