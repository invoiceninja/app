import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';

/// The off switch is an outline: a `surface`-filled track, a 2 px `ink3`
/// outline and M3's small `ink3` knob (`theme.dart` § switchTheme). Off has to
/// read as a control in every preset — WCAG 1.4.11 asks 3:1 of a component's
/// boundary against what is around it — and must never look like on.
///
/// The two fills it replaced each failed one of those: Material's default
/// (`surfaceAlt` track, `border` knob) all but vanished on the dark cards, and
/// the filled `borderStrong` track read as a second "on" beside the accent.

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final presets = <String, InTheme>{
    'lightSand': InTheme.lightSand,
    'lightMist': InTheme.lightMist,
    'lightPaper': InTheme.lightPaper,
    'darkEspresso': InTheme.darkEspresso,
    'darkMidnight': InTheme.darkMidnight,
    'darkCarbon': InTheme.darkCarbon,
  };

  const off = <WidgetState>{};
  const on = <WidgetState>{WidgetState.selected};

  for (final entry in presets.entries) {
    group(entry.key, () {
      final theme = buildInTheme(entry.value);
      final t = theme.extension<InTheme>()!;
      final s = theme.switchTheme;

      test('off is a surface-filled track with a 2 px ink3 outline', () {
        expect(s.trackColor!.resolve(off), t.surface);
        expect(s.trackOutlineColor!.resolve(off), t.ink3);
        expect(s.trackOutlineWidth!.resolve(off), 2);
        expect(s.thumbColor!.resolve(off), t.ink3);
      });

      test('the off outline clears 3:1 on the card and on the page', () {
        final outline = s.trackOutlineColor!.resolve(off)!;
        for (final ground in {'surface': t.surface, 'bg': t.bg}.entries) {
          expect(
            _ratio(outline, ground.value),
            greaterThanOrEqualTo(3),
            reason:
                '${entry.key}: outline on ${ground.key} is '
                '${_ratio(outline, ground.value).toStringAsFixed(2)}:1',
          );
        }
      });

      test('the off knob clears 3:1 on its own track', () {
        final knob = s.thumbColor!.resolve(off)!;
        final track = s.trackColor!.resolve(off)!;
        expect(_ratio(knob, track), greaterThanOrEqualTo(3));
      });

      test('on is unchanged: accent track, white knob, no outline', () {
        expect(s.trackColor!.resolve(on), t.accent);
        expect(s.thumbColor!.resolve(on), Colors.white);
        expect(s.trackOutlineColor!.resolve(on), Colors.transparent);
        expect(
          _ratio(Colors.white, t.accent),
          greaterThanOrEqualTo(3),
          reason: '${entry.key}: the on knob against the accent track',
        );
      });

      test('off and on never share a track colour', () {
        expect(s.trackColor!.resolve(off), isNot(s.trackColor!.resolve(on)));
      });

      test('disabled dims the outline and the knob to ink4', () {
        const disabledOff = {WidgetState.disabled};
        expect(s.trackOutlineColor!.resolve(disabledOff), t.ink4);
        expect(s.thumbColor!.resolve(disabledOff), t.ink4);
      });
    });
  }
}
