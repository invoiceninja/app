import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:flutter/foundation.dart';

/// Owns how the kanban board is drawn (`DevicePrefKeys.kanban`): the card
/// fields, the lane grouping, the collapsed columns. Follows the store, so a
/// sign-out that forgets the key resets it with no hook to wire — same shape
/// as `TasksViewController`.
class KanbanPrefsController extends ValueNotifier<KanbanPrefs> {
  KanbanPrefsController({required DevicePrefsStore prefs})
    : _prefs = prefs,
      super(_read(prefs)) {
    prefs.addListener(_sync);
  }

  final DevicePrefsStore _prefs;

  static KanbanPrefs _read(DevicePrefsStore prefs) =>
      KanbanPrefs.decode(prefs.read(DevicePrefKeys.kanban));

  void _sync() => value = _read(_prefs);

  Future<void> set(KanbanPrefs next) async {
    if (value == next) return;
    value = next;
    await _prefs.write(DevicePrefKeys.kanban, next.encode());
  }

  @override
  void dispose() {
    _prefs.removeListener(_sync);
    super.dispose();
  }
}
