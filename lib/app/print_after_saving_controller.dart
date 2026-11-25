import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns "Print After Saving" (`DevicePrefKeys.printAfterSaving`,
/// device-local): whether a plain Save — the button, Enter, ⌘S — of a
/// billing document that has Print PDF also prints it, through the same
/// after-save path as choosing Print PDF from the editor's menu
/// (docs/after-saving.md). Off by default: a print dialog after every save
/// is only welcome to someone who asked for it.
///
/// Read through its root provider as
/// `context.read<PrintAfterSavingController?>()` (`EntityEditScaffold`), so a
/// test without the provider simply never prints after a save.
class PrintAfterSavingController extends DevicePref<bool> {
  PrintAfterSavingController({required DevicePrefsStore prefs})
    : super(prefs, DevicePrefKeys.printAfterSaving, fallback: false);
}
