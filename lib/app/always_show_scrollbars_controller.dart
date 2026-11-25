import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns the "Always show scroll bars" preference
/// (`DevicePrefKeys.alwaysShowScrollbars`, device-local).
///
/// Defaults to **off**: a thumb that fades once the scrolling stops is the
/// platform convention, and the pointer theme already makes it easier to find
/// (docs/scrollbars.md). On keeps each thumb drawn while its scroll view can
/// scroll. Pointer platforms only — touch scroll views draw no scroll bar to
/// keep.
///
/// Read through its root provider with `watchAlwaysShowScrollbars(context)`,
/// so every `InScrollbar` rebuilds when it flips and a test without the
/// provider simply gets the default.
class AlwaysShowScrollbarsController extends DevicePref<bool> {
  AlwaysShowScrollbarsController({required DevicePrefsStore prefs})
    : super(prefs, DevicePrefKeys.alwaysShowScrollbars, fallback: false);
}
