import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';

/// Owns whether the web build's "other apps" banner (`WebAppBanner`) was
/// dismissed in this browser (`DevicePrefKeys.webAppBannerDismissed`).
///
/// A device preference, kept at a sign-out: the ✕ answers "this browser has
/// been told", like the mobile-app promo's schedule. An account scope would
/// bring the banner back after every sign-out — and on the web the idle
/// timeout signs people out on its own.
class WebAppBannerController extends DevicePref<bool> {
  WebAppBannerController({required DevicePrefsStore prefs})
    : super(prefs, DevicePrefKeys.webAppBannerDismissed, fallback: false);

  bool get dismissed => value;

  Future<void> dismiss() => set(true);
}
