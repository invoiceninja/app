# Accent colour

Companion to CLAUDE.md § Design system (v2). Why a user's accent can be any colour at all, what went blank when it was white, and the three pieces (`onAccent`, `accentInk`, the contrast floor in `buildInTheme`) that keep every accent-coloured surface legible.

## The accent is user-chosen and may be white

**The rule.** Anything drawn *on* a filled accent (a `FilledButton` label, a check in a ticked box, the edge day of a range picker, a switch's knob) takes `tokens.onAccent`, never `Colors.white`. Accent-coloured *text on a surface* takes `tokens.accentInk`, never `tokens.accent`. `buildInTheme` floors an overridden accent's contrast against the surface before anything derives from it.

**Where the colour comes from.** `company_user.settings.accent_color`, per user and per company, is set under Settings → User Details → Preferences → Accent Colour. `AccentColorController` reads it and `main.dart` passes it to `buildInTheme(..., accentOverride:)` for both the light and dark themes. The swatch grid offers 13 colours, but its trailing tile is a free hex picker, and React and v1 write the same key, so the value can be anything, white included.

**The failure it shipped as.** A user reported that the app's buttons "don't have the shadow shown in the demo". Their screenshot showed something worse: the list's **New Client** button was a blank white box and the selected **All** status-tab count was a blank white chip. Their accent was white, and two separate defects combined:

1. The `FilledButton` theme set `foregroundColor: Colors.white`, and `ColorScheme.onPrimary` was `Colors.white`, so a white accent got a white label. `InTheme.onAccent` already picked white or near-black by contrast, but the theme didn't use it.
2. The active neutral `SidebarBadge` drew its count in `tokens.accent` on `tokens.surface`, which was white on white. Tab underlines, switch tracks and the button fill disappeared the same way, because nothing related the accent to the surface it sits on.

**The contrast floor (`kAccentSurfaceContrastFloor = 1.8`, `lib/app/theme.dart`).** `withMinContrast` (`lib/app/design_tokens.dart`) makes the override opaque. It then walks its HSL lightness away from the surface, one percent at a time and keeping hue and saturation, until the WCAG contrast reaches the floor. The direction comes from the surface's luminance, not the theme's brightness, because a custom surface can be anything. An 8-digit `#AARRGGBB` value that parses translucent comes out opaque too.

The floor's value is chosen so that no palette pick is altered on a light preset. Against the three light surfaces (`#FFFFFF`, `#FFFFFF`, `#FAFAF9`), the faintest swatch is `#84CC16` lime at 1.89:1, followed by `#F59E0B` amber at 2.06:1. A floor at WCAG's 3:1 for UI components would have changed five of the thirteen swatches. On the dark presets every swatch clears 3.7:1 except `#1F2937` slate at 1.14:1, which was invisible there and is now lifted.

**`accentInk` reaches 4.5:1.** `_deriveAccentInk` still shifts the accent's lightness by ±0.18. It then continues with `withMinContrast` until the ink reaches `kAccentInkContrastFloor` (4.5:1, WCAG AA body text) on the surface. The 0.18 shift alone left a pale accent's ink unreadable.

**The floor runs on every theme, not only on an override.** A custom surface (`CustomToken.surface`, Device Settings → Customize) is a free pick too, so the stock accent is floored against it as well, and the preset's `accentInk` is re-floored at 4.5:1. A stock preset clears both floors and comes back from `buildInTheme` byte-identical; a test pins that.

**Floored against `surface`, not `bg`.** The FAB and some primary buttons sit on the page `bg`, which on lightMist (`#ECEEF2`) is darker than the card. Flooring against the lowest of `bg` / `surface` / `surfaceAlt` would put lime (1.67:1 on that `bg`) under the floor and change a palette pick, so the floor stays on `surface`. A floored white accent reads about 1.5:1 on lightMist's page; its label, through `onAccent`, still reads.

**A busy spinner sits on the disabled fill, never the accent.** Sign Up, the lock screen's Unlock and the three two-factor dialogs disable their button while busy. The spinner therefore draws on M3's disabled fill (`onSurface` at 12%, near-white on a light preset), where the old `Colors.white` was invisible whatever the accent. It takes `ink3`.

**Still open: accent as text.** About 69 sites draw `tokens.accent` as text or a tab indicator on a surface, and `TabBar`s default to `colorScheme.primary`. With a floored white accent these read at 1.8:1. Moving them to `accentInk`, and adding a `tabBarTheme`, is a separate sweep that restyles the stock look, so it was left out of this fix.

**Tests.** `test/app/accent_legibility_test.dart` checks the following:
- Every swatch is untouched on every light preset, which pins the floor.
- Only slate moves on a dark preset.
- White, near-white, black and slate come out at or above the floor, and the hue survives.
- A translucent override comes out opaque.
- A stock preset is untouched, a custom surface floors the stock accent, and a white accent gives a switch a visible knob.
- Every derived `accentInk` reaches 4.5:1.
- A white accent gives a `FilledButton` a near-black label.

`test/app/on_accent_test.dart` covers how `onAccent` picks between white and near-black.
