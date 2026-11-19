import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/color_hex.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/settings/widgets/accent_swatch_grid.dart';

/// The accent is the user's own pick (`company_user.settings.accent_color`),
/// and the custom picker, React and v1 all accept any hex. A user who picked
/// white saw the primary button and the active status-tab badge as blank
/// white boxes, labels gone: the button's text was a hardcoded white, and
/// nothing kept the accent apart from the white card it sits on
/// (docs/accent-colour.md).

const _lightPresets = <String, InTheme>{
  'lightSand': InTheme.lightSand,
  'lightMist': InTheme.lightMist,
  'lightPaper': InTheme.lightPaper,
};

const _darkPresets = <String, InTheme>{
  'darkEspresso': InTheme.darkEspresso,
  'darkMidnight': InTheme.darkMidnight,
  'darkCarbon': InTheme.darkCarbon,
};

InTheme _built(InTheme base, Color accent) =>
    buildInTheme(base, accentOverride: accent).extension<InTheme>()!;

void main() {
  group('the floor never alters a palette pick on a light preset', () {
    // Pins kAccentSurfaceContrastFloor: raise it past the faintest swatch
    // (lime, 1.89:1 on the paper surface) and this fails.
    for (final preset in _lightPresets.entries) {
      test(preset.key, () {
        for (final hex in kAccentSwatches) {
          final swatch = parseHexColor(hex)!;
          expect(_built(preset.value, swatch).accent, swatch, reason: hex);
        }
      });
    }
  });

  test('on a dark preset only the slate swatch is lifted', () {
    for (final preset in _darkPresets.entries) {
      for (final hex in kAccentSwatches) {
        final swatch = parseHexColor(hex)!;
        final built = _built(preset.value, swatch).accent;
        if (hex == '#1F2937') {
          expect(built, isNot(swatch), reason: '${preset.key} $hex');
        } else {
          expect(built, swatch, reason: '${preset.key} $hex');
        }
      }
    }
  });

  group('an accent the surface would swallow is floored', () {
    final cases = <String, (InTheme, Color)>{
      'white on lightSand': (InTheme.lightSand, const Color(0xFFFFFFFF)),
      'white on lightPaper': (InTheme.lightPaper, const Color(0xFFFFFFFF)),
      'near-white on lightMist': (InTheme.lightMist, const Color(0xFFF4F6F8)),
      'black on darkCarbon': (InTheme.darkCarbon, const Color(0xFF000000)),
      'slate on darkEspresso': (InTheme.darkEspresso, const Color(0xFF1F2937)),
    };
    for (final c in cases.entries) {
      test(c.key, () {
        final (base, accent) = c.value;
        final t = _built(base, accent);
        expect(
          colorContrast(t.accent, base.surface),
          greaterThanOrEqualTo(kAccentSurfaceContrastFloor),
        );
      });
    }

    test('the hue survives the nudge', () {
      final t = _built(InTheme.darkEspresso, const Color(0xFF1F2937));
      expect(
        HSLColor.fromColor(t.accent).hue,
        closeTo(HSLColor.fromColor(const Color(0xFF1F2937)).hue, 1),
      );
    });

    test('a translucent override comes out opaque', () {
      final t = _built(InTheme.lightSand, parseHexColor('#002F7DC3')!);
      expect(t.accent.a, 1.0);
      expect(t.accent, const Color(0xFF2F7DC3));
    });
  });

  test('a derived accentInk reads as text on the surface', () {
    final picks = [
      ...kAccentSwatches.map((h) => parseHexColor(h)!),
      const Color(0xFFFFFFFF),
      const Color(0xFF000000),
    ];
    for (final preset in {..._lightPresets, ..._darkPresets}.entries) {
      for (final pick in picks) {
        final t = _built(preset.value, pick);
        expect(
          colorContrast(t.accentInk, preset.value.surface),
          greaterThanOrEqualTo(kAccentInkContrastFloor),
          reason: '${preset.key} ${formatHexColor(pick)}',
        );
      }
    }
  });

  test('a stock preset comes back from buildInTheme untouched', () {
    for (final preset in {..._lightPresets, ..._darkPresets}.entries) {
      final t = buildInTheme(preset.value).extension<InTheme>()!;
      expect(t.accent, preset.value.accent, reason: preset.key);
      expect(t.accentSoft, preset.value.accentSoft, reason: preset.key);
      expect(t.accentInk, preset.value.accentInk, reason: preset.key);
    }
  });

  test('a custom surface floors the stock accent too', () {
    // No accent_color set, but the device's custom palette put the surface
    // on the stock blue: the floor is about the surface, not the override.
    final base = InTheme.lightSand.copyWith(surface: const Color(0xFF2F7DC3));
    final t = buildInTheme(base).extension<InTheme>()!;
    expect(
      colorContrast(t.accent, base.surface),
      greaterThanOrEqualTo(kAccentSurfaceContrastFloor),
    );
    expect(
      colorContrast(t.accentInk, base.surface),
      greaterThanOrEqualTo(kAccentInkContrastFloor),
    );
  });

  test('a white accent gives a switch a knob it can be seen on', () {
    final theme = buildInTheme(
      InTheme.lightSand,
      accentOverride: const Color(0xFFFFFFFF),
    );
    final t = theme.extension<InTheme>()!;
    final knob = theme.switchTheme.thumbColor!.resolve({WidgetState.selected})!;
    expect(knob, t.onAccent);
    expect(colorContrast(knob, t.accent), greaterThanOrEqualTo(4.5));
  });

  testWidgets('a white accent gives the primary button a dark label', (
    tester,
  ) async {
    final theme = buildInTheme(
      InTheme.lightSand,
      accentOverride: const Color(0xFFFFFFFF),
    );
    final tokens = theme.extension<InTheme>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: FilledButton(onPressed: () {}, child: const Text('New')),
          ),
        ),
      ),
    );
    final style = DefaultTextStyle.of(tester.element(find.text('New'))).style;
    expect(style.color, tokens.onAccent);
    expect(theme.colorScheme.onPrimary, tokens.onAccent);
    expect(
      colorContrast(style.color!, tokens.accent),
      greaterThanOrEqualTo(4.5),
    );
  });
}
