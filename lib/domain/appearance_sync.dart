/// How the app's appearance — theme mode, both palettes and the custom colours
/// — follows the user across devices (invoiceninja/app#199,
/// `docs/user-settings-storage.md`).
///
/// A leaf: plain strings and maps, no Flutter, so the decision is testable on
/// its own. `ThemeController` turns a record into tokens; the
/// `AppearanceSyncController` feeds this the device's copy and every company's.
library;

import 'package:collection/collection.dart' show DeepCollectionEquality;

/// The `company_user.settings` key the record lives under.
const String kAppearanceSettingsKey = 'flutter_appearance';

/// The device's appearance, or one company's synced copy of it. Values are
/// the names `ThemeController` stores (`system` / `light` / `dark`, the
/// `LightVariant` / `DarkVariant` names, `{light: {token: '#hex'}, dark: …}`);
/// a value this build doesn't know is the reader's problem, never a reason to
/// drop the record.
class AppearanceRecord {
  const AppearanceRecord({
    required this.themeMode,
    required this.lightVariant,
    required this.darkVariant,
    this.custom = const {},
    this.updatedAt,
  });

  final String themeMode;
  final String lightVariant;
  final String darkVariant;

  /// `{light: {token: '#RRGGBB'}, dark: {…}}` — `CustomTheme`'s JSON shape.
  final Map<String, Object?> custom;

  /// Epoch ms of the change it carries (the device clock that made it). Null
  /// on the device's own copy when this account has never changed or adopted
  /// one here.
  final int? updatedAt;

  /// The settings a fresh install shows.
  static const AppearanceRecord defaults = AppearanceRecord(
    themeMode: 'system',
    lightVariant: 'sand',
    darkVariant: 'espresso',
  );

  /// Same look, whatever the stamps say. An empty side of [custom] equals a
  /// missing one.
  bool sameLook(AppearanceRecord other) =>
      themeMode == other.themeMode &&
      lightVariant == other.lightVariant &&
      darkVariant == other.darkVariant &&
      const DeepCollectionEquality().equals(
        _normalizedCustom(custom),
        _normalizedCustom(other.custom),
      );

  bool get isDefaultLook => sameLook(defaults);

  AppearanceRecord withUpdatedAt(int? stamp) => AppearanceRecord(
    themeMode: themeMode,
    lightVariant: lightVariant,
    darkVariant: darkVariant,
    custom: custom,
    updatedAt: stamp,
  );

  /// The settings patch that writes this record: one dotted path per field,
  /// so a field a newer build added to the record survives an older build's
  /// write.
  Map<String, Object?> toSettingsPatch() => {
    '$kAppearanceSettingsKey.theme_mode': themeMode,
    '$kAppearanceSettingsKey.light_variant': lightVariant,
    '$kAppearanceSettingsKey.dark_variant': darkVariant,
    '$kAppearanceSettingsKey.custom': _normalizedCustom(custom),
    '$kAppearanceSettingsKey.updated_at': updatedAt,
  };

  /// The record a company's `company_user.settings` holds, or null when it
  /// holds none this build can use — no key, not a map, or no stamp (a record
  /// without one can't be ordered against anything, so it reads as missing).
  static AppearanceRecord? fromSettings(Map<String, dynamic>? settings) {
    final raw = settings?[kAppearanceSettingsKey];
    if (raw is! Map) return null;
    final stamp = _intOf(raw['updated_at']);
    if (stamp == null || stamp <= 0) return null;
    final custom = raw['custom'];
    return AppearanceRecord(
      themeMode: _stringOf(raw['theme_mode'], defaults.themeMode),
      lightVariant: _stringOf(raw['light_variant'], defaults.lightVariant),
      darkVariant: _stringOf(raw['dark_variant'], defaults.darkVariant),
      custom: custom is Map
          ? {for (final e in custom.entries) e.key.toString(): e.value}
          : const {},
      updatedAt: stamp,
    );
  }

  @override
  String toString() =>
      'AppearanceRecord($themeMode, $lightVariant, $darkVariant, $custom, '
      '$updatedAt)';
}

Map<String, Object?> _normalizedCustom(Map<String, Object?> custom) => {
  for (final side in const ['light', 'dark'])
    side: switch (custom[side]) {
      final Map<dynamic, dynamic> m => {
        for (final e in m.entries) e.key.toString(): e.value,
      },
      _ => const <String, Object?>{},
    },
};

String _stringOf(Object? raw, String fallback) =>
    raw is String && raw.isNotEmpty ? raw : fallback;

int? _intOf(Object? raw) => switch (raw) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

/// What [reconcileAppearance] decided.
class AppearanceDecision {
  const AppearanceDecision({this.adopt, this.push, this.markSeeded = false});

  /// A record to take on this device (it carries its stamp).
  final AppearanceRecord? adopt;

  /// A record to write to the active company's settings (it carries its
  /// stamp). Never another company's: the outbox drains only the active one.
  final AppearanceRecord? push;

  /// Set the device's one-time seed marker.
  final bool markSeeded;

  bool get isNoop => adopt == null && push == null && !markSeeded;

  @override
  String toString() =>
      'AppearanceDecision(adopt: $adopt, push: $push, seeded: $markSeeded)';
}

/// Decide between the device's appearance and the companies' synced copies.
///
/// * **Adopt the newest copy across every company** — a change is written
///   only to the company that was active when it was made, so a new device
///   finds it wherever it is. It wins when it is newer than [local]'s stamp,
///   or when [local] has none (this account never chose one here). On a tie
///   with a different look the server's copy wins, as for saved views.
/// * **Push to the active company** whatever the device holds that is newer
///   than that company's copy, or that it lacks — so every company converges
///   as it is used, and a copy another client wrote back stale (React's
///   whole-object profile save, the old app dropping the key) is put right.
/// * **Seed once** when nothing anywhere has a copy and this account has no
///   stamp here: a device that ran a build before this one uploads the look
///   it was given, stamped [nowMs]. Only while [seeded] is false — a device
///   seeds once, so the next person to sign in on a shared one doesn't get
///   the last person's look uploaded as their own.
///
/// [companies] maps company id to that company's copy (null when it has
/// none); [activeCompanyId] must be among them, or nothing is pushed.
AppearanceDecision reconcileAppearance({
  required AppearanceRecord local,
  required Map<String, AppearanceRecord?> companies,
  required String activeCompanyId,
  required bool seeded,
  required int nowMs,
}) {
  final hasActive = companies.containsKey(activeCompanyId);
  final active = companies[activeCompanyId];

  // Newest copy anywhere; a tie prefers the active company's, which is the
  // one a push would otherwise overwrite.
  AppearanceRecord? newest = active;
  for (final MapEntry(:key, :value) in companies.entries) {
    if (value == null || key == activeCompanyId) continue;
    if (newest == null || value.updatedAt! > newest.updatedAt!) newest = value;
  }

  AppearanceRecord? adopt;
  var effective = local;
  final localStamp = local.updatedAt;
  if (newest != null &&
      (localStamp == null ||
          newest.updatedAt! > localStamp ||
          (newest.updatedAt == localStamp && !newest.sameLook(local)))) {
    adopt = newest;
    effective = newest;
  }

  AppearanceRecord? push;
  var markSeeded = false;
  if (hasActive) {
    if (effective.updatedAt != null) {
      if (active == null || active.updatedAt! < effective.updatedAt!) {
        push = effective;
      }
    } else if (!seeded && !local.isDefaultLook) {
      // Nothing anywhere and no stamp: the upload-once migration.
      push = local.withUpdatedAt(nowMs);
      adopt = push;
    }
    // The device has now met this account's settings once; from here a
    // missing copy is never filled from an unstamped look.
    markSeeded = !seeded;
  }

  return AppearanceDecision(adopt: adopt, push: push, markSeeded: markSeeded);
}
