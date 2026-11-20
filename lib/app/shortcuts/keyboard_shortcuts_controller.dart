import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Intent, ShortcutActivator;
import 'package:logging/logging.dart';

import 'package:admin/app/shortcuts/key_binding.dart';
import 'package:admin/app/shortcuts/shortcut_catalog.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

final _log = Logger('KeyboardShortcutsController');

/// Owns the user's keyboard-shortcut overrides and resolves the effective
/// binding for every catalog action (override → catalog default). The single
/// source of truth feeding the real key handling (`activatorsFor`), the
/// hold-modifier hint bar, and the `?` help dialog.
///
/// Three-state per action: **default** (no override), **custom** (an override
/// binding), **cleared** (an explicit `null` override that removes even the
/// default). Device-local, one JSON blob (`DevicePrefKeys.keyboardShortcuts`);
/// [prefs] is optional so unit tests exercise the pure resolution logic
/// without a store.
class KeyboardShortcutsController extends ChangeNotifier {
  KeyboardShortcutsController({DevicePrefsStore? prefs}) : _prefs = prefs {
    if (prefs == null) return;
    restoreFromJson(prefs.read(DevicePrefKeys.keyboardShortcuts));
    prefs.addListener(_sync);
  }

  final DevicePrefsStore? _prefs;

  /// action id → override. A present key means "overridden"; its value may be a
  /// [KeyBinding] (custom) or `null` (explicitly cleared). Absent key = use the
  /// catalog default.
  final Map<String, KeyBinding?> _overrides = {};

  /// True when the user has set an explicit override (custom or cleared) for
  /// [id] — drives the "Reset" affordance in the settings row.
  bool isOverridden(String id) => _overrides.containsKey(id);

  /// The effective binding for [id]: the override if present (may be null =
  /// cleared), else the catalog default (may be null = ships unbound).
  KeyBinding? resolvedBinding(String id) {
    if (_overrides.containsKey(id)) return _overrides[id];
    return kShortcutCatalogById[id]?.defaultBinding;
  }

  /// Build the live `{activator: intent}` map for [scope]. [intents] maps action
  /// id → the [Intent] the consumer (the shell) wants fired; an action with no
  /// entry in [intents], or no resolved binding, is skipped. A primary-modified
  /// chord contributes both its meta + control activators.
  ///
  /// On a duplicate activator, a binding the user **set** beats a catalog
  /// default — a default that moves onto a key someone already chose for
  /// another action (⌘K, which went from Switch company to the palette in
  /// November 2026) must not take it from them. Between two of the same kind
  /// the **first** catalog entry wins. Both are deterministic, and the clash
  /// is surfaced in the settings UI via [conflictingIds].
  Map<ShortcutActivator, Intent> activatorsFor(
    ShortcutScope scope,
    Map<String, Intent> intents,
  ) {
    final out = <ShortcutActivator, Intent>{};
    for (final id in _winners(scope, (id) => intents.containsKey(id))) {
      final binding = resolvedBinding(id)!;
      for (final activator in binding.toActivators()) {
        out[activator] = intents[id]!;
      }
    }
    return out;
  }

  /// The binding [id] actually fires on: its [resolvedBinding], or null when
  /// that chord lost a clash to another action (see [activatorsFor]).
  ///
  /// What every surface that *advertises* a shortcut reads — the palette's
  /// chip, the hint bar, the `?` dialog, a tooltip — so none of them offers a
  /// key that does something else. Settings still shows [resolvedBinding]
  /// beside its conflict flag, because that is where the user fixes it.
  KeyBinding? effectiveBinding(String id) {
    final def = kShortcutCatalogById[id];
    if (def == null) return null;
    if (!_winners(def.scope, (_) => true).contains(id)) return null;
    return resolvedBinding(id);
  }

  /// The ids that own their chord in [scope], in claim order: user-set
  /// bindings before catalog defaults, then catalog order; an action whose
  /// chord is already claimed — by any one of its signatures — is out whole.
  /// [take] limits the contest to the actions a consumer can fire.
  ///
  /// Dedupes on the canonical signature, NOT the activator: SingleActivator /
  /// CharacterActivator declare no `operator ==`, so a `Map` keyed by them
  /// uses identity and `putIfAbsent` could never actually collide — both
  /// conflicting entries would land in the map and "first wins" would hold
  /// only by accident (via `_indexShortcuts`' insertion order).
  List<String> _winners(ShortcutScope scope, bool Function(String id) take) {
    final claimed = <String>{};
    final winners = <String>[];
    final ordered = [
      ...kShortcutCatalog.where((d) => _overrides.containsKey(d.id)),
      ...kShortcutCatalog.where((d) => !_overrides.containsKey(d.id)),
    ];
    for (final def in ordered) {
      if (def.scope != scope || !take(def.id)) continue;
      final binding = resolvedBinding(def.id);
      if (binding == null) continue;
      final signatures = binding.activatorSignatures();
      if (signatures.any(claimed.contains)) continue;
      claimed.addAll(signatures);
      winners.add(def.id);
    }
    return winners;
  }

  /// Action ids whose resolved binding collides with another action's — two
  /// actions produce an overlapping activator. Both sides of every clash are
  /// included so the settings UI can flag each row.
  Set<String> conflictingIds() {
    // Key by the binding's canonical signature, not the produced activator —
    // SingleActivator/CharacterActivator use identity equality (see
    // KeyBinding.activatorSignatures).
    final bySignature = <String, List<String>>{};
    for (final def in kShortcutCatalog) {
      final binding = resolvedBinding(def.id);
      if (binding == null) continue;
      for (final signature in binding.activatorSignatures()) {
        (bySignature[signature] ??= <String>[]).add(def.id);
      }
    }
    final out = <String>{};
    for (final ids in bySignature.values) {
      if (ids.length > 1) out.addAll(ids);
    }
    return out;
  }

  /// Assign a custom binding. A binding equal to the catalog default is no
  /// override — it reverts to the default, exactly as [restoreFromJson] would
  /// read it back, so the row's Reset never shows only to vanish on the next
  /// launch.
  void setBinding(String id, KeyBinding binding) {
    if (binding == kShortcutCatalogById[id]?.defaultBinding) {
      resetBinding(id);
      return;
    }
    _overrides[id] = binding;
    _persist();
    notifyListeners();
  }

  /// Explicitly clear a shortcut (removes even the catalog default). Distinct
  /// from [resetBinding], which reverts to the default. Clearing an action
  /// that ships unbound is its default, so that is a reset too (the same
  /// normalisation as [restoreFromJson]).
  void clearBinding(String id) {
    if (kShortcutCatalogById[id]?.defaultBinding == null) {
      resetBinding(id);
      return;
    }
    _overrides[id] = null;
    _persist();
    notifyListeners();
  }

  /// Revert [id] to its catalog default.
  void resetBinding(String id) {
    if (_overrides.remove(id) == null) return;
    _persist();
    notifyListeners();
  }

  /// Revert every action to its catalog default.
  void resetAll() {
    if (_overrides.isEmpty) return;
    _overrides.clear();
    _persist();
    notifyListeners();
  }

  /// Follow the store — the boot load (the overrides are a device preference,
  /// so a data wipe keeps them).
  void _sync() {
    restoreFromJson(_prefs?.read(DevicePrefKeys.keyboardShortcuts));
    notifyListeners();
  }

  /// Parse a stored overrides blob into memory (unknown ids ignored, so a
  /// removed catalog action doesn't strand a dead override). Does not
  /// notify.
  @visibleForTesting
  void restoreFromJson(String? jsonStr) {
    _overrides.clear();
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is! String || !kShortcutCatalogById.containsKey(key)) return;
        final defaultBinding = kShortcutCatalogById[key]!.defaultBinding;
        // An override equal to the default is no override: it would show a
        // Reset that does nothing — a Switch company someone cleared back when
        // it owned ⌘K, now that it ships unbound — and would outrank defaults
        // in a clash it never chose.
        if (value == null) {
          if (defaultBinding != null) _overrides[key] = null; // cleared
        } else if (value is Map) {
          final binding = KeyBinding.fromJson(Map<String, dynamic>.from(value));
          if (binding != null && binding != defaultBinding) {
            _overrides[key] = binding;
          }
        }
      });
    } catch (e, st) {
      _log.warning('Failed to parse keyboard shortcut overrides', e, st);
    }
  }

  /// Serialize the current overrides (custom bindings + explicit clears).
  @visibleForTesting
  Map<String, dynamic> overridesToJson() => {
    for (final e in _overrides.entries) e.key: e.value?.toJson(),
  };

  Future<void> _persist() async {
    await _prefs?.write(
      DevicePrefKeys.keyboardShortcuts,
      jsonEncode(overridesToJson()),
    );
  }

  @override
  void dispose() {
    _prefs?.removeListener(_sync);
    super.dispose();
  }
}
