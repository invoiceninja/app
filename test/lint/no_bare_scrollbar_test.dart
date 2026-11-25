import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A hand-placed scroll bar is an `InScrollbar`, never Material's
/// `Scrollbar`: a bare one keeps the pointer look (the theme) but misses
/// "Always show scroll bars", and without a controller it falls back to a
/// `PrimaryScrollController` nothing attaches to on a pointer platform
/// (docs/scrollbars.md). `in_scrollbar.dart` builds the one Material bar,
/// on a touch platform.
void main() {
  test('no bare Scrollbar( outside in_scrollbar.dart', () {
    final bare = RegExp(r'(?<![A-Za-z_])Scrollbar\(');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File ||
          !f.path.endsWith('.dart') ||
          f.path.endsWith('.g.dart') ||
          f.path.endsWith('in_scrollbar.dart')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code = line.contains('//')
            ? line.substring(0, line.indexOf('//'))
            : line;
        if (bare.hasMatch(code)) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'use InScrollbar');
  });
}
