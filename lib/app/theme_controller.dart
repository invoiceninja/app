import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/domain/appearance_sync.dart';

/// Owns the user's theme preferences — the [ThemeMode] choice (System / Light
/// / Dark), the two palette sub-variants and the custom colour overrides —
/// each its own device preference (`DevicePrefKeys.themeMode`,
/// `.lightVariant`, `.darkVariant`, `.customTheme`). The variant choices
/// persist independently — System honors both so the OS can flip brightness
/// without losing either selection.
///
/// The app's [MaterialApp.router] binds to this controller via
/// [ListenableBuilder]. A change to any of the three fields rebuilds
/// `MaterialApp.router`'s `themeMode` / `theme` / `darkTheme`.
///
/// The four follow the user across devices (invoiceninja/app#199): every
/// setter stamps [syncedAt] (`DevicePrefKeys.appearanceSyncedAt`), and the
/// `AppearanceSyncController` writes the stamped [appearance] up to the
/// account and hands a newer one back through [adoptSynced].
class ThemeController extends ChangeNotifier {
  ThemeController({required DevicePrefsStore prefs, DateTime Function()? now})
    : _prefs = prefs,
      _now = now ?? DateTime.now {
    _apply();
    prefs.addListener(_sync);
  }

  static const _defaultMode = ThemeMode.system;
  static const _defaultLight = LightVariant.sand;
  static const _defaultDark = DarkVariant.espresso;

  final DevicePrefsStore _prefs;
  final DateTime Function() _now;

  ThemeMode _themeMode = _defaultMode;
  LightVariant _lightVariant = _defaultLight;
  DarkVariant _darkVariant = _defaultDark;
  CustomTheme _customTheme = defaultCustomTheme;
  int? _syncedAt;

  // Memoised resolved palettes (selected preset + the side's overrides).
  // Recomputed lazily and cleared whenever the variant OR [_customTheme]
  // changes, so [lightTokens] / [darkTokens] return a stable instance across
  // unrelated rebuilds (locale / accent notifies). Without this, `MaterialApp`
  // would see a fresh `InTheme` every build (it has no `==`) and fire a
  // spurious 200ms theme animation each time.
  InTheme? _cachedLight;
  InTheme? _cachedDark;

  ThemeMode get themeMode => _themeMode;
  LightVariant get lightVariant => _lightVariant;
  DarkVariant get darkVariant => _darkVariant;
  CustomTheme get customTheme => _customTheme;

  /// When this account last changed or adopted the appearance on this
  /// device (epoch ms), or null when it never has — a sign-out forgets it.
  int? get syncedAt => _syncedAt;

  /// The appearance as the record the account stores, stamped [syncedAt].
  AppearanceRecord get appearance => AppearanceRecord(
    themeMode: _serializeMode(_themeMode),
    lightVariant: _lightVariant.name,
    darkVariant: _darkVariant.name,
    custom: (jsonDecode(_customTheme.toJson()) as Map).cast<String, Object?>(),
    updatedAt: _syncedAt,
  );

  /// Light tokens = the selected light preset with the light overrides layered
  /// on. Returns the bare preset's const singleton when there are no
  /// overrides, so the no-customization path keeps stable identity.
  InTheme get lightTokens {
    if (_customTheme.lightOverrides.isEmpty) return _lightVariant.tokens;
    return _cachedLight ??= _customTheme.applyTo(
      _lightVariant.tokens,
      Brightness.light,
    );
  }

  /// Dark tokens — see [lightTokens].
  InTheme get darkTokens {
    if (_customTheme.darkOverrides.isEmpty) return _darkVariant.tokens;
    return _cachedDark ??= _customTheme.applyTo(
      _darkVariant.tokens,
      Brightness.dark,
    );
  }

  void _invalidateCache() {
    _cachedLight = null;
    _cachedDark = null;
  }

  void _setCustomTheme(CustomTheme next) {
    if (next == _customTheme) return;
    _customTheme = next;
    _invalidateCache();
  }

  /// Take every theme field from the store. Unknown / missing values fall
  /// back to the defaults — the same behavior a fresh install gets. Returns
  /// whether anything changed.
  bool _apply() {
    final mode =
        _parseMode(_prefs.read(DevicePrefKeys.themeMode)) ?? _defaultMode;
    final light =
        _parseLightVariant(_prefs.read(DevicePrefKeys.lightVariant)) ??
        _defaultLight;
    final dark =
        _parseDarkVariant(_prefs.read(DevicePrefKeys.darkVariant)) ??
        _defaultDark;
    final customJson = _prefs.read(DevicePrefKeys.customTheme);
    final custom = customJson == null
        ? defaultCustomTheme
        : CustomTheme.fromJson(customJson);
    final syncedAt = _parseStamp(
      _prefs.read(DevicePrefKeys.appearanceSyncedAt),
    );
    var changed = false;
    if (syncedAt != _syncedAt) {
      _syncedAt = syncedAt;
      changed = true;
    }
    if (custom != _customTheme) {
      _setCustomTheme(custom);
      changed = true;
    }
    if (mode != _themeMode) {
      _themeMode = mode;
      changed = true;
    }
    if (light != _lightVariant) {
      _lightVariant = light;
      _invalidateCache();
      changed = true;
    }
    if (dark != _darkVariant) {
      _darkVariant = dark;
      _invalidateCache();
      changed = true;
    }
    return changed;
  }

  void _sync() {
    if (_apply()) notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _stampLocalChange();
    notifyListeners();
    await _prefs.write(DevicePrefKeys.themeMode, _serializeMode(mode));
    await _persistStamp();
  }

  Future<void> setLightVariant(LightVariant variant) async {
    if (_lightVariant == variant) return;
    _lightVariant = variant;
    _invalidateCache(); // the preset feeds the resolved tokens
    // Picking a different preset starts fresh — stale tweaks shouldn't bleed
    // onto the new palette. (Set `_customTheme` directly: `_setCustomTheme`
    // early-returns when equal and would skip the cache invalidation above.)
    if (_customTheme.lightOverrides.isNotEmpty) {
      _customTheme = _customTheme.copyWith(lightOverrides: const {});
    }
    _stampLocalChange();
    notifyListeners();
    await _prefs.write(DevicePrefKeys.lightVariant, variant.name);
    await _persistCustomTheme();
    await _persistStamp();
  }

  Future<void> setDarkVariant(DarkVariant variant) async {
    if (_darkVariant == variant) return;
    _darkVariant = variant;
    _invalidateCache();
    if (_customTheme.darkOverrides.isNotEmpty) {
      _customTheme = _customTheme.copyWith(darkOverrides: const {});
    }
    _stampLocalChange();
    notifyListeners();
    await _prefs.write(DevicePrefKeys.darkVariant, variant.name);
    await _persistCustomTheme();
    await _persistStamp();
  }

  Future<void> setCustomOverride(
    Brightness side,
    CustomToken token,
    Color color,
  ) async {
    final next = _customTheme.withOverride(side, token, color);
    if (next == _customTheme) return;
    _setCustomTheme(next);
    _stampLocalChange();
    notifyListeners();
    await _persistCustomTheme();
    await _persistStamp();
  }

  Future<void> clearCustomOverride(Brightness side, CustomToken token) async {
    final next = _customTheme.withoutOverride(side, token);
    if (next == _customTheme) return;
    _setCustomTheme(next);
    _stampLocalChange();
    notifyListeners();
    await _persistCustomTheme();
    await _persistStamp();
  }

  /// Drop every override on [side] — reverts that side to its base preset.
  Future<void> clearCustomSide(Brightness side) async {
    final next = side == Brightness.dark
        ? _customTheme.copyWith(darkOverrides: const {})
        : _customTheme.copyWith(lightOverrides: const {});
    if (next == _customTheme) return;
    _setCustomTheme(next);
    _stampLocalChange();
    notifyListeners();
    await _persistCustomTheme();
    await _persistStamp();
  }

  Future<void> _persistCustomTheme() =>
      _prefs.write(DevicePrefKeys.customTheme, _customTheme.toJson());

  /// A change made on this device: stamped now, so it beats every copy the
  /// account holds that is older. Never earlier than the stamp it replaces —
  /// a clock set back must not lose the change to the copy it came from.
  void _stampLocalChange() {
    final now = _now().millisecondsSinceEpoch;
    final prev = _syncedAt;
    _syncedAt = prev != null && prev >= now ? prev + 1 : now;
  }

  Future<void> _persistStamp() =>
      _prefs.write(DevicePrefKeys.appearanceSyncedAt, _syncedAt?.toString());

  /// Take [record] — the account's newer appearance, or this device's own
  /// look being stamped for its first upload — with its stamp. Written
  /// wholesale: unlike [setLightVariant], a palette that arrives with its
  /// overrides keeps them. A value this build doesn't know keeps the
  /// device's. Not a local change, so nothing is stamped anew.
  Future<void> adoptSynced(AppearanceRecord record) async {
    final mode = _parseMode(record.themeMode) ?? _themeMode;
    final light = _parseLightVariant(record.lightVariant) ?? _lightVariant;
    final dark = _parseDarkVariant(record.darkVariant) ?? _darkVariant;
    final custom = CustomTheme.fromJson(jsonEncode(record.custom));
    final changed =
        mode != _themeMode ||
        light != _lightVariant ||
        dark != _darkVariant ||
        custom != _customTheme ||
        record.updatedAt != _syncedAt;
    if (!changed) return;
    _themeMode = mode;
    if (light != _lightVariant || dark != _darkVariant) _invalidateCache();
    _lightVariant = light;
    _darkVariant = dark;
    _setCustomTheme(custom);
    _syncedAt = record.updatedAt;
    notifyListeners();
    await _prefs.write(DevicePrefKeys.themeMode, _serializeMode(mode));
    await _prefs.write(DevicePrefKeys.lightVariant, light.name);
    await _prefs.write(DevicePrefKeys.darkVariant, dark.name);
    await _persistCustomTheme();
    await _persistStamp();
  }

  @override
  void dispose() {
    _prefs.removeListener(_sync);
    super.dispose();
  }

  static String _serializeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
  };

  static int? _parseStamp(String? raw) =>
      raw == null ? null : int.tryParse(raw);

  static ThemeMode? _parseMode(String? raw) => switch (raw) {
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => null,
  };

  static LightVariant? _parseLightVariant(String? raw) {
    if (raw == null) return null;
    for (final v in LightVariant.values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  static DarkVariant? _parseDarkVariant(String? raw) {
    if (raw == null) return null;
    for (final v in DarkVariant.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}
