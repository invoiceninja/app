import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Opt-out marker — see the doc below.
const String _kAllowMarker = 'lint: allow-outline-input-border';

/// CI lint: an outlined field in `lib/` is drawn by `InFieldOutlineBorder`
/// (`lib/app/design_tokens.dart`), never a bare `OutlineInputBorder(`.
///
/// `LabeledField` hides a field's own label at the Comfortable density by
/// drawing it at font size 0, and the engine lays out a zero-size label that
/// contains a space at `FLT_MIN` wide rather than 0. Material's
/// `OutlineInputBorder` cuts a notch for any label wider than 0, plus 4 px of
/// `gapPadding` either side, so every two-word label ("PO Number", "Due
/// Date") left an 8 px nick in the box's top edge. `InFieldOutlineBorder`
/// ignores a gap under a pixel, so the Comfortable border is whole and the
/// Compact floating label still gets its notch. A decoration's own `border`
/// wins over the theme's, so one bare `OutlineInputBorder()` at a call site
/// brings the nick back for that field, and nothing else fails
/// (`docs/form-fields.md` § A label above the box cuts no notch in its
/// border).
///
/// A field that never has a label can still be given the bare class with
/// `// lint: allow-outline-input-border <reason>` on the line or the line
/// above — but the subclass draws it identically, so there is rarely a
/// reason.
void main() {
  test('lib/ draws outlined fields with InFieldOutlineBorder', () {
    // `OutlineInputBorder(` not preceded by an identifier character, so
    // `InFieldOutlineBorder(` itself does not match.
    final pattern = RegExp(r'(?<![A-Za-z0-9_])OutlineInputBorder\(');
    final offenders = <String>[];
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ should exist');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      if (entity.path.endsWith('.freezed.dart')) continue;

      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!pattern.hasMatch(lines[i])) continue;
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        if (line.contains(_kAllowMarker)) continue;
        if (i > 0 && lines[i - 1].contains(_kAllowMarker)) continue;
        offenders.add('${entity.path}:${i + 1}:  $line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use InFieldOutlineBorder (lib/app/design_tokens.dart) in place of '
          'OutlineInputBorder: the bare class cuts an 8 px notch in the top '
          'edge of every LabeledField whose hidden label holds a space. Opt '
          'out with `// $_kAllowMarker` plus a reason. Found:\n  '
          '${offenders.join('\n  ')}',
    );
  });
}
