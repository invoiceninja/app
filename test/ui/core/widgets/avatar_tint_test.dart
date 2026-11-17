import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/avatar_tint.dart';

/// WCAG 2.x relative luminance / contrast, written out here rather than
/// borrowed from the tokens file so the test does not grade itself.
double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Initials avatars draw the pair's ink on its soft background. White on the
/// old saturated swatches failed AA (amber `#B07A1F` was ~3.7:1); this holds
/// every pair, in both themes, to the 4.5:1 body-text floor.
void main() {
  for (final brightness in Brightness.values) {
    test('every ${brightness.name} pair clears 4.5:1', () {
      final tints = InTheme.avatarTintsFor(brightness);
      expect(tints, hasLength(8));
      for (var i = 0; i < tints.length; i++) {
        final t = tints[i];
        expect(
          _contrast(t.background, t.ink),
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name} #$i',
        );
      }
    });
  }

  test('the light and dark lists are the same hues in the same order', () {
    final light = InTheme.avatarTintsFor(Brightness.light);
    final dark = InTheme.avatarTintsFor(Brightness.dark);
    expect(light.length, dark.length);
    for (var i = 0; i < light.length; i++) {
      final hl = HSLColor.fromColor(light[i].background).hue;
      final hd = HSLColor.fromColor(dark[i].background).hue;
      final diff = (hl - hd).abs();
      expect(math.min(diff, 360 - diff), lessThan(8), reason: '#$i');
    }
  });

  test('every preset reads the list for its brightness', () {
    for (final t in [
      InTheme.lightSand,
      InTheme.lightMist,
      InTheme.lightPaper,
      InTheme.darkEspresso,
      InTheme.darkMidnight,
      InTheme.darkCarbon,
    ]) {
      expect(t.avatarTints, InTheme.avatarTintsFor(t.brightness));
    }
  });

  test('a seed maps to one slot, the same in every theme', () {
    expect(avatarTintIndexFor('c1', 8), avatarTintIndexFor('c1', 8));
    final slots = {
      for (final s in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'])
        avatarTintIndexFor(s, 8),
    };
    expect(slots.length, greaterThan(1));
    expect(slots.every((i) => i >= 0 && i < 8), isTrue);
  });
}
