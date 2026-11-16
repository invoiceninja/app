import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Opt-out marker — on the `labelText:` line or the line above it, with a
/// reason.
const String _kAllowMarker = 'lint: allow-inside-label';

/// How far above a `labelText:` its wrapper may open. The longest field in the
/// app today is under forty lines from `LabeledField(` to its decoration.
const int _kLookBack = 60;

/// The widgets that draw the label above themselves, so a `labelText:` handed
/// to one of them needs no wrapper at the call site.
final RegExp _kOwners = RegExp(
  r'\b(LabeledField|ComposerLabeledField|InDateField|InTimeField|'
  r'SettingsTextField|OverridableDateField)\(',
);

/// CI lint: a field that sets `labelText:` is wrapped in `LabeledField`
/// (`docs/form-fields.md` § Labels sit above the field).
///
/// A bare `InputDecoration(labelText:)` still works: it draws Material's
/// floating label inside the box. Nothing fails, nothing warns, and the form it
/// sits in gets one field whose name is grey text in the box while every
/// field around it has its name above — the mix this convention exists to end.
/// Only a rendered screen shows it.
///
/// A text scan, so it is a proxy: it accepts any `labelText:` with one of the
/// owning widgets opening in the [_kLookBack] lines above it.
void main() {
  test('every labelText sits under a LabeledField', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart') ||
          entity.path.endsWith('.freezed.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final at = line.indexOf('labelText:');
        if (at < 0) continue;
        final comment = line.indexOf('//');
        if (comment >= 0 && comment < at) continue;
        if (line.contains(_kAllowMarker) ||
            (i > 0 && lines[i - 1].contains(_kAllowMarker))) {
          continue;
        }
        var owned = false;
        for (var j = i; j >= 0 && j >= i - _kLookBack; j--) {
          if (_kOwners.hasMatch(lines[j])) {
            owned = true;
            break;
          }
        }
        if (!owned) offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Wrap the field in LabeledField(label: …, child: …) and keep its '
          'labelText, or mark the line `// $_kAllowMarker <reason>`. See '
          'docs/form-fields.md § Labels sit above the field.',
    );
  });
}
