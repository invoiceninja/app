import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns the column widths the user dragged on the wide entity lists
/// (`DevicePrefKeys.listColumnWidths`, device-local — docs/entity-lists.md
/// § A dragged column width is a device preference).
///
/// The value is `{entityType: {columnId: width}}`. A column with no entry keeps
/// the width its `ColumnDefinition` declares. Widths are stored as dragged;
/// the list clamps them when it lays them out ([kListColumnMinWidth] /
/// [kListColumnMaxWidth]), so a value a newer build wrote with other limits
/// still renders.
///
/// Keyed by entity, not by list instance: a client's embedded Invoices tab
/// shows the widths set on the Invoices list, the way it shows that list's
/// chosen columns.
class ListColumnWidthsController
    extends ValueNotifier<Map<String, Map<String, double>>> {
  ListColumnWidthsController({required DevicePrefsStore prefs})
    : _prefs = prefs,
      super(_read(prefs)) {
    prefs.addListener(_sync);
  }

  final DevicePrefsStore _prefs;

  /// The widths the user set for [entityType]'s list — empty when none.
  Map<String, double> widthsFor(String entityType) =>
      value[entityType] ?? const {};

  /// Remember [width] for [columnId] on [entityType]'s list.
  Future<void> setWidth(String entityType, String columnId, double width) =>
      _write(entityType, (m) => m[columnId] = width.roundToDouble());

  /// Forget [columnId]'s width, so it goes back to its declared one.
  Future<void> clearWidth(String entityType, String columnId) =>
      _write(entityType, (m) => m.remove(columnId));

  Future<void> _write(
    String entityType,
    void Function(Map<String, double>) change,
  ) async {
    final widths = Map<String, double>.of(widthsFor(entityType));
    change(widths);
    final next = <String, Map<String, double>>{
      for (final e in value.entries)
        if (e.key != entityType) e.key: e.value,
      if (widths.isNotEmpty) entityType: widths,
    };
    if (mapEquals(next[entityType], value[entityType])) return;
    value = next;
    await _prefs.write(
      DevicePrefKeys.listColumnWidths,
      next.isEmpty ? null : jsonEncode(next),
    );
  }

  void _sync() => value = _read(_prefs);

  /// Anything unreadable — a hand edit, a shape a newer build wrote — reads as
  /// no widths at all rather than failing the list.
  static Map<String, Map<String, double>> _read(DevicePrefsStore prefs) {
    final raw = prefs.read(DevicePrefKeys.listColumnWidths);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, Map<String, double>>{};
      for (final entry in decoded.entries) {
        final cols = entry.value;
        if (entry.key is! String || cols is! Map) continue;
        final widths = <String, double>{
          for (final c in cols.entries)
            if (c.key is String && c.value is num && (c.value as num) > 0)
              c.key as String: (c.value as num).toDouble(),
        };
        if (widths.isNotEmpty) out[entry.key as String] = widths;
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

/// The narrowest a dragged column gets — room for a short value and its
/// ellipsis.
const double kListColumnMinWidth = 56;

/// The widest a dragged column gets.
const double kListColumnMaxWidth = 1200;
