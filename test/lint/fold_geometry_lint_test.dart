import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two rules from docs/foldables.md that nothing else can see — a foldable is
/// the only place either goes wrong, and no test device in CI is one.
///
///  * `lib/ui/core/fold_geometry.dart` is the only reader of
///    `MediaQuery.displayFeatures`: every layout that splits at a fold asks it
///    (`bookFoldOf`), so they all agree with each other and with Material's
///    `DisplayFeatureSubScreen` about where the fold is.
///  * Every `showDialog` in `lib/ui` passes `anchorPoint:` — in practice
///    `foldAnchorPoint(context)`, which is null (Material's default) with no
///    fold. Without it a dialog opens in the start half of a folded screen, so
///    a record's delete confirmation came up over the list beside it. A call
///    that deliberately takes the default says so with `// fold: <reason>` on
///    the `showDialog` line or the line above.
void main() {
  Iterable<File> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  /// [source] with `//` comments blanked (line structure kept), so a doc
  /// comment that names `showDialog` is not a call. A `//` inside a string
  /// (a URL) is not a comment, or the bracket count of the call it sits in
  /// would come out wrong.
  String code(String source) => source
      .split('\n')
      .map((l) {
        String? quote;
        for (var i = 0; i < l.length; i++) {
          final c = l[i];
          if (quote != null) {
            if (c == '\\') {
              i++;
            } else if (c == quote) {
              quote = null;
            }
          } else if (c == "'" || c == '"') {
            quote = c;
          } else if (c == '/' && i + 1 < l.length && l[i + 1] == '/') {
            return l.substring(0, i);
          }
        }
        return l;
      })
      .join('\n');

  test('only fold_geometry.dart reads displayFeatures', () {
    final offenders = <String>[
      for (final f in dartFiles('lib'))
        if (!f.path.endsWith('lib/ui/core/fold_geometry.dart') &&
            RegExp(
              r'displayFeatures|displayFeaturesOf',
            ).hasMatch(code(f.readAsStringSync())))
          f.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Read a fold through lib/ui/core/fold_geometry.dart '
          '(bookFoldOf / separatingFold), never displayFeatures directly.',
    );
  });

  test('every root dialog and picker in lib/ui passes anchorPoint', () {
    final offenders = <String>[];
    for (final f in dartFiles('lib/ui')) {
      final raw = f.readAsStringSync();
      final rawLines = raw.split('\n');
      final src = code(raw);
      for (final call in rootRouteCalls(src)) {
        if (call.topLevelArgs.contains('anchorPoint:')) continue;
        final line = '\n'.allMatches(src.substring(0, call.start)).length;
        final marked = [
          rawLines[line],
          if (line > 0) rawLines[line - 1],
        ].any((l) => l.contains('// fold:'));
        if (!marked) offenders.add('${f.path}:${line + 1} ${call.name}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Pass `anchorPoint: foldAnchorPoint(context)` so it opens on the '
          'side of the fold it came from (docs/foldables.md), or mark the '
          'call `// fold: <reason>`.',
    );
  });

  test('the call scanner reads nested generics and top-level args only', () {
    final calls = rootRouteCalls(
      'showDialog<Map<String, List<int>>>(context: c, builder: (_) => '
      'X(onTap: () => showDialog(context: c, anchorPoint: p, builder: b)));\n'
      'showModalBottomSheet(context: c, builder: b);\n'
      'showModalBottomSheet(context: c, useRootNavigator: true, builder: b);\n'
      'showDatePicker(context: c, anchorPoint: p);',
    ).toList();
    expect(
      code("x('https://a.b/c', showDialog(context: c));"),
      contains('showDialog'),
    );
    expect(calls.map((c) => c.name), [
      'showDialog',
      'showDialog',
      'showModalBottomSheet',
      'showDatePicker',
    ]);
    // The outer dialog's own args, not the inner call's anchorPoint.
    expect(calls.first.topLevelArgs.contains('anchorPoint:'), isFalse);
    expect(calls[1].topLevelArgs.contains('anchorPoint:'), isTrue);
  });
}

class RouteCall {
  RouteCall(this.name, this.start, this.topLevelArgs);
  final String name;
  final int start;

  /// The call's arguments with every nested bracket's contents dropped.
  final String topLevelArgs;
}

/// The calls that push a route onto the ROOT navigator through
/// `DisplayFeatureSubScreen`, which opens in the start half of a folded screen
/// without an `anchorPoint`: `showDialog`, `showGeneralDialog`, the date /
/// time pickers, and a
/// `showModalBottomSheet` with `useRootNavigator: true` (on a nested
/// navigator a sheet fills its half of the split, and needs nothing).
Iterable<RouteCall> rootRouteCalls(String src) sync* {
  final name = RegExp(
    r'\b(showDialog|showGeneralDialog|showDatePicker|showTimePicker|'
    r'showDateRangePicker|'
    r'showModalBottomSheet)\b',
  );
  for (final m in name.allMatches(src)) {
    var i = m.end;
    // Skip a type argument list, nested generics included.
    if (i < src.length && src[i] == '<') {
      var depth = 0;
      for (; i < src.length; i++) {
        if (src[i] == '<') depth++;
        if (src[i] == '>' && --depth == 0) {
          i++;
          break;
        }
      }
    }
    if (i >= src.length || src[i] != '(') continue;
    final top = StringBuffer();
    var depth = 0;
    for (; i < src.length; i++) {
      final c = src[i];
      if ('([{'.contains(c)) depth++;
      if (')]}'.contains(c)) {
        depth--;
        if (depth == 0) break;
      }
      if (depth == 1 && c != '(') top.write(c);
    }
    final args = top.toString();
    final callName = m.group(1)!;
    if (callName == 'showModalBottomSheet' &&
        !RegExp(r'useRootNavigator:\s*true').hasMatch(args)) {
      continue;
    }
    yield RouteCall(callName, m.start, args);
  }
}
