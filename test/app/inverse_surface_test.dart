import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';

/// The inverted-surface getters — the running-timer bar's fill and inks
/// (docs/tasks-views.md § The running timer is an inverted bar). They are
/// derived from tokens every preset already sets, so a new preset gets them
/// for free; this pins that what it gets is legible.

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

  for (final MapEntry(key: name, value: t) in presets.entries) {
    group(name, () {
      test('the fill is the ink, inverted against the page', () {
        expect(t.inverseSurface, t.ink);
        expect(t.onInverse, t.surface);
      });

      test('text on the bar clears 4.5:1, the muted line included', () {
        expect(
          _ratio(t.onInverse, t.inverseSurface),
          greaterThanOrEqualTo(4.5),
        );
        final muted = Color.alphaBlend(t.onInverseMuted, t.inverseSurface);
        expect(_ratio(muted, t.inverseSurface), greaterThanOrEqualTo(4.5));
      });

      test('the caution colour beats this brightness\'s own amber', () {
        // The bar's "Due now" is bold text; 4.3 is the darkest preset's
        // swap, and still double what the theme's own warning gives there.
        final swap = _ratio(t.warningOnInverse, t.inverseSurface);
        expect(swap, greaterThanOrEqualTo(4.3));
        expect(swap, greaterThan(_ratio(t.warning, t.inverseSurface)));
      });
    });
  }
}
