import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// The choices Device Settings → Security offers, in minutes; `0` is Never.
const kLockAfterInactivityMinutes = <int>[0, 1, 5, 15, 30, 60];

/// Owns "Lock after inactivity" (`DevicePrefKeys.lockAfterInactivity`,
/// device-local, minutes; `0` = Never, the default).
///
/// `SoftLockController` reads [timeout] to decide when to lock; the Security
/// tab's row writes it. See docs/soft-lock.md.
class LockAfterInactivityController extends DevicePref<double> {
  LockAfterInactivityController({required DevicePrefsStore prefs})
    : super(prefs, DevicePrefKeys.lockAfterInactivity, fallback: 0);

  /// The stored value snapped to one of [kLockAfterInactivityMinutes], so a
  /// row this build can't offer (written by a newer one, or by hand) still
  /// selects a choice. A negative value reads as Never.
  int get minutes {
    final v = value;
    if (v.isNaN || v <= 0) return 0;
    return kLockAfterInactivityMinutes
        .where((m) => m > 0)
        .reduce((a, b) => (v - a).abs() <= (v - b).abs() ? a : b);
  }

  /// Null when the lock is off.
  Duration? get timeout => minutes == 0 ? null : Duration(minutes: minutes);

  Future<void> setMinutes(int minutes) => set(minutes.toDouble());
}
