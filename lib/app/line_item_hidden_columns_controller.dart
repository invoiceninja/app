import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns which custom-field columns the billing-doc editor's desktop
/// line-item table hides (`DevicePrefKeys.lineItemHiddenColumns`,
/// docs/line-item-columns.md § Which custom fields the desktop table shows is
/// a device preference).
///
/// The value is `{companyId: {"product" | "task": {slot, …}}}` — the hidden
/// 1-based slots. Nothing stored hides nothing: every defined custom field
/// shows, as React's editor draws them. Only the desktop table reads it; the
/// phone cards and the line editor show every field, and a hidden field's
/// value is kept and saved.
class LineItemHiddenColumnsController
    extends ValueNotifier<Map<String, Map<String, Set<int>>>> {
  LineItemHiddenColumnsController({required DevicePrefsStore prefs})
    : _prefs = prefs,
      super(_read(prefs)) {
    prefs.addListener(_sync);
  }

  final DevicePrefsStore _prefs;

  static String _kind(bool task) => task ? 'task' : 'product';

  /// The custom-field slots [companyId]'s product (or, with [task], task)
  /// table hides — empty when none.
  Set<int> hiddenSlots(String companyId, {required bool task}) =>
      value[companyId]?[_kind(task)] ?? const {};

  /// Hide or show [slot]'s column on [companyId]'s product / task table.
  Future<void> setHidden(
    String companyId, {
    required bool task,
    required int slot,
    required bool hidden,
  }) async {
    final kind = _kind(task);
    final slots = Set<int>.of(hiddenSlots(companyId, task: task));
    if (hidden ? !slots.add(slot) : !slots.remove(slot)) return;
    final kinds = <String, Set<int>>{
      for (final e in (value[companyId] ?? const {}).entries)
        if (e.key != kind) e.key: e.value,
      if (slots.isNotEmpty) kind: slots,
    };
    final next = <String, Map<String, Set<int>>>{
      for (final e in value.entries)
        if (e.key != companyId) e.key: e.value,
      if (kinds.isNotEmpty) companyId: kinds,
    };
    value = next;
    await _prefs.write(
      DevicePrefKeys.lineItemHiddenColumns,
      next.isEmpty
          ? null
          : jsonEncode({
              for (final c in next.entries)
                c.key: {
                  for (final k in c.value.entries)
                    k.key: (k.value.toList()..sort()),
                },
            }),
    );
  }

  void _sync() => value = _read(_prefs);

  /// Anything unreadable — a hand edit, a shape a newer build wrote — reads
  /// as nothing hidden rather than failing the table.
  static Map<String, Map<String, Set<int>>> _read(DevicePrefsStore prefs) {
    final raw = prefs.read(DevicePrefKeys.lineItemHiddenColumns);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, Map<String, Set<int>>>{};
      for (final company in decoded.entries) {
        final kinds = company.value;
        if (company.key is! String || kinds is! Map) continue;
        final parsed = <String, Set<int>>{};
        for (final kind in kinds.entries) {
          final slots = kind.value;
          if (kind.key is! String || slots is! List) continue;
          final set = {
            for (final s in slots)
              if (s is int && s >= 1 && s <= 4) s,
          };
          if (set.isNotEmpty) parsed[kind.key as String] = set;
        }
        if (parsed.isNotEmpty) out[company.key as String] = parsed;
      }
      return out;
    } on FormatException {
      return const {};
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_sync);
    super.dispose();
  }
}
