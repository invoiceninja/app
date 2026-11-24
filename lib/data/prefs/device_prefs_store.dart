import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';

final _log = Logger('DevicePrefsStore');

/// This device's preferences — the `device_prefs` table, mirrored in memory
/// so every read is synchronous.
///
/// [load] fills the mirror once at boot. A write updates the mirror, then its
/// own row, so no write can disturb another preference: the old single-row
/// `nav_state` writes read the whole row and wrote it back, and a theme change
/// could put back the route or filters that row held a moment earlier.
///
/// Listeners hear only about changes a preference's owner did not make —
/// [load], a data wipe forgetting the account keys ([forgetWiped]), and a
/// returning user's account keys coming back ([restoreForReturningUser]) —
/// never about a [write]: each key has one owner, which already holds what it
/// wrote, and an owner that writes several keys (the theme) must not be
/// re-synced from a half-written set. So a preference that follows the store
/// needs no wipe hook to go back to its default (`DevicePref`).
class DevicePrefsStore extends ChangeNotifier {
  /// [db] null keeps the preferences in memory only — for tests of code that
  /// needs a store but not its persistence.
  DevicePrefsStore(AppDatabase? db, {DateTime Function()? now})
    : _db = db,
      _now = now ?? DateTime.now,
      _loaded = db == null,
      _loadSucceeded = db == null;

  final AppDatabase? _db;
  final DateTime Function() _now;
  final Map<String, String> _values = {};

  /// Whether [load] has settled — succeeded or failed — so the mirror is as
  /// complete as it will be this launch. Until then an empty read may only
  /// mean "not read yet": the trusted-certificate store refuses to report a
  /// rejection that a pin it hasn't loaded would have prevented.
  bool get isLoaded => _loaded;
  bool _loaded;

  /// Whether the mirror holds the table — false after a [load] that failed,
  /// where [isLoaded] is true but every read is a default. An owner that
  /// would write a value *derived from* "no row" (the What's New baseline)
  /// checks this, or it would overwrite the row the failed read never saw.
  bool get loadSucceeded => _loadSucceeded;
  bool _loadSucceeded;

  /// Replace the mirror with the table. Once at boot, bounded there: a
  /// failure leaves every preference on its default for this launch, and the
  /// rows untouched for the next.
  Future<void> load() async {
    final db = _db;
    if (db == null) return;
    try {
      final rows = await db.devicePrefsDao.readAll();
      _values
        ..clear()
        ..addAll(rows);
      _loadSucceeded = true;
    } finally {
      _loaded = true;
    }
    notifyListeners();
  }

  /// The stored value, or null when there is none or it can't be decoded —
  /// the owner's default applies.
  T? read<T extends Object>(PrefKey<T> key) {
    final raw = _values[key.name];
    return raw == null ? null : key.codec.decode(raw);
  }

  /// Store [value] under [key]; null removes the row, returning the key to
  /// its owner's default. A failed write is logged and keeps the new value in
  /// memory — the user sees their choice until the next launch.
  Future<void> write<T extends Object>(PrefKey<T> key, T? value) =>
      _writeRaw(key.name, value == null ? null : key.codec.encode(value));

  Future<void> _writeRaw(String name, String? raw) async {
    if (raw == null) {
      _values.remove(name);
    } else {
      _values[name] = raw;
    }
    final db = _db;
    if (db == null) return;
    try {
      if (raw == null) {
        await db.devicePrefsDao.remove(name);
      } else {
        await db.devicePrefsDao.put(
          name,
          raw,
          now: _now().millisecondsSinceEpoch,
        );
      }
    } catch (e, st) {
      _log.warning('Failed to persist the $name preference', e, st);
    }
  }

  /// How many signed-out users' preferences are kept aside at once.
  static const int _keptIdentities = 5;

  /// Put the [DevicePrefKeys.keptForReturningUser] preferences aside for
  /// [identity] before a sign-out wipes them (`LocalDataDisposer.wipeAll`),
  /// so [restoreForReturningUser] can hand them back when the same user signs
  /// in again (invoiceninja/app#209). Oldest identity first out past five.
  ///
  /// Nothing at all unless [load] succeeded: the mirror is empty then, and
  /// writing "nothing kept" from it would delete every other user's copy.
  Future<void> keepForReturningUser(String identity) async {
    if (!_loadSucceeded) return;
    final kept = <String, String>{
      for (final name in DevicePrefKeys.keptForReturningUser)
        if (_values[name] case final raw?) name: raw,
    };
    final all = _readKept()..remove(identity);
    if (kept.isNotEmpty) all[identity] = kept;
    while (all.length > _keptIdentities) {
      all.remove(all.keys.first);
    }
    await _writeKept(all);
  }

  /// Give [identity] back what [keepForReturningUser] put aside — only into
  /// preferences that are unset, so nothing newer is ever overwritten — and
  /// tell the owners. Called on every sign-in; a no-op when nothing was kept.
  ///
  /// The third change listeners hear about, beside [load] and [forgetWiped]:
  /// it writes rows other owners own, while none of them is writing.
  Future<void> restoreForReturningUser(String identity) async {
    if (!_loadSucceeded) return;
    final all = _readKept();
    final kept = all.remove(identity);
    if (kept == null) return;
    var changed = false;
    for (final entry in kept.entries) {
      if (!DevicePrefKeys.keptForReturningUser.contains(entry.key)) continue;
      if (_values.containsKey(entry.key)) continue;
      await _writeRaw(entry.key, entry.value);
      changed = true;
    }
    await _writeKept(all);
    if (changed) notifyListeners();
  }

  /// Drop what was kept for [identity] without handing it back — the same
  /// user signed in with their data kept, so the copy is stale.
  Future<void> forgetKeptFor(String identity) async {
    if (!_loadSucceeded) return;
    final all = _readKept();
    if (all.remove(identity) == null) return;
    await _writeKept(all);
  }

  Map<String, Map<String, String>> _readKept() {
    final raw = read(DevicePrefKeys.accountPrefsKept);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is Map)
            e.key as String: {
              for (final v in (e.value as Map).entries)
                if (v.key is String && v.value is String)
                  v.key as String: v.value as String,
            },
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeKept(Map<String, Map<String, String>> all) => write(
    DevicePrefKeys.accountPrefsKept,
    all.isEmpty ? null : jsonEncode(all),
  );

  /// The in-memory half of `AppDatabase.wipe`, which kept only
  /// [DevicePrefKeys.keptOnWipe]: forget the rest, and tell the owners.
  /// Called by `LocalDataDisposer.wipeAll` straight after the wipe.
  void forgetWiped() {
    final kept = DevicePrefKeys.keptOnWipe;
    _values.removeWhere((name, _) => !kept.contains(name));
    notifyListeners();
  }
}
