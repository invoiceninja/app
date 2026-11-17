import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// Picks a stable tint for an initials avatar: a soft background and the ink
/// to draw on it. The same `seed` always maps to the same hue — in light and
/// dark alike — so a given entity (client, company, contact) keeps its
/// identity colour across screens and themes; only the lightness follows the
/// theme.
///
/// Uses [InTheme.avatarTints] in `lib/app/design_tokens.dart` — never
/// introduce a parallel palette in feature code. Draw the label or icon in
/// [InAvatarTint.ink], never white: the background is a soft tint.
///
/// Falls back to the ambient [ThemeData.brightness] where no [InTheme] is
/// registered (a bare `MaterialApp` in a test).
InAvatarTint avatarTintFor(BuildContext context, String seed) {
  final theme = Theme.of(context);
  final tokens = theme.extension<InTheme>();
  final tints = tokens?.avatarTints ?? InTheme.avatarTintsFor(theme.brightness);
  return tints[avatarTintIndexFor(seed, tints.length)];
}

/// The solid counterpart of [avatarTintFor] — 5.1.30's saturated swatch
/// with white initials, the same hue for the same [seed]. For a wide
/// entity-list row only ([InTheme.avatarSolids]).
InAvatarTint avatarSolidFor(String seed) {
  const solids = InTheme.avatarSolids;
  return solids[avatarTintIndexFor(seed, solids.length)];
}

/// The palette slot [seed] hashes to, out of [length] — a pure function of
/// the seed, so it is the same in every theme.
int avatarTintIndexFor(String seed, int length) {
  var hash = 0;
  for (final code in seed.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash % length;
}
