import 'package:flutter/foundation.dart';

import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns "After Saving" (`DevicePrefKeys.afterSaving`, device-local,
/// invoiceninja/app#202): whether Save on an edit screen keeps the editor
/// open (`true`, "Edit Record") or goes to the record (`false`, "View
/// Record") — docs/after-saving.md.
///
/// **Null means automatic**, and automatic depends on the device: the editor
/// stays open on a tablet or a desktop — v1's default there, and React's
/// behaviour — and a phone goes to the record, as v1 always did on one. That
/// answer needs a `MediaQuery` (`Breakpoints.isPhone`), so callers resolve it
/// through [staysFor] / [set] — and every UI caller goes through the
/// `staysIn` / `setIn` extension (`ui/core/edit/after_saving.dart`), so the
/// device question is asked in one place. The pattern is
/// `HideEmptyPanelsController`'s.
///
/// **Automatic stays reachable**: [set] stores nothing when the choice is the
/// one this device would make anyway, so only a choice that differs from the
/// device default sticks.
class AfterSavingController extends ValueNotifier<bool?> {
  AfterSavingController({required DevicePrefsStore prefs})
    : _prefs = prefs,
      super(prefs.read(DevicePrefKeys.afterSaving)) {
    prefs.addListener(_sync);
  }

  final DevicePrefsStore _prefs;

  void _sync() => value = _prefs.read(DevicePrefKeys.afterSaving);

  /// Whether Save keeps the editor open on a device whose automatic answer is
  /// "go to the record" exactly when [isPhone].
  bool staysFor({required bool isPhone}) => value ?? !isPhone;

  /// Record [stay] as chosen on a device that [isPhone] or not: the device
  /// default is stored as nothing (automatic), anything else as an override.
  Future<void> set(bool stay, {required bool isPhone}) async {
    final next = stay == !isPhone ? null : stay;
    if (value == next) return;
    value = next;
    await _prefs.write(DevicePrefKeys.afterSaving, next);
  }

  @override
  void dispose() {
    _prefs.removeListener(_sync);
    super.dispose();
  }
}
