import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Opt-out marker — see the doc below.
const String _kAllowMarker = 'lint: allow-keep-alives';

/// CI lint: every lazy list in `lib/` decides whether its rows may be kept
/// alive once they scroll out of range. It sets `addAutomaticKeepAlives:
/// false`, gives its rows a fixed extent, or says why it keeps them alive.
///
/// The default (`true`) parks a row that asks to be kept alive instead of
/// disposing it. A hovered `InkWell` asks, and a focused text field asks. If
/// that row also shows a `Tooltip`, or any other `OverlayPortal`, its overlay
/// box stays in the `Overlay` and is never laid out. The `Overlay` still
/// hit-tests it, so every later mouse event throws
/// (`Null check operator used on a null value` in `RenderBox.hitTest` in
/// release) and the app stops reacting to the mouse. The trigger is a hover
/// and a scroll past the cache extent in one frame: a wheel flick, a jump to
/// the top, a list that resets. This shipped as Sentry FLUTTER-ADMIN-1F, a
/// Windows user's app freezing while typing in a quote's Item cell. The
/// framework bug is flutter/flutter#193566. `docs/lazy-list-keep-alives.md`
/// has the mechanism and the repro.
///
/// A fixed extent (`itemExtent`, `itemExtentBuilder`, `prototypeItem`) is
/// safe as it stands: each row then gets tight constraints, which makes it a
/// relayout boundary, and a dirty boundary is still laid out while parked.
///
/// Keep the default only where the rows' own state must outlive scrolling:
/// form fields, a drag in progress, cards that keep themselves alive. Mark
/// those with `// $_kAllowMarker <reason>` on the list's line or the one
/// above.
///
/// Know the limits. `ReorderableListView` and `SliverReorderableList` take no
/// `addAutomaticKeepAlives`, so they are not read. Their lists are short
/// sheets and shrink-wrapped tables, and a shrink-wrapped list in an
/// unbounded parent lays out every row anyway. `GridView` is not read either:
/// grid tiles get tight constraints. The depth walk does not know about
/// quotes, so a bracket inside a string literal would confuse it; no site
/// does that.
void main() {
  final scanned = <String>[];
  final offenders = <String>[];

  for (final file in _dartFiles('lib')) {
    final raw = file.readAsStringSync();
    final source = _stripComments(raw);
    final lines = raw.split('\n');
    for (final call in _lazyListCalls(source)) {
      final line = lines[call.line - 1];
      final above = call.line > 1 ? lines[call.line - 2] : '';
      if (line.contains(_kAllowMarker) || above.contains(_kAllowMarker)) {
        continue;
      }
      scanned.add('${file.path}:${call.line}');
      if (!_decided(call.args)) offenders.add('${file.path}:${call.line}');
    }
  }

  test('every lazy list decides on keep-alives', () {
    expect(
      offenders,
      isEmpty,
      reason:
          'these lists keep the default `addAutomaticKeepAlives: true`. A '
          'hovered row with a tooltip that scrolls out of range is parked '
          'with its overlay never laid out, and the app stops reacting to '
          'the mouse (Sentry FLUTTER-ADMIN-1F, flutter/flutter#193566). Add '
          '`addAutomaticKeepAlives: false`, a fixed `itemExtent`, or '
          '`// $_kAllowMarker <reason>` on that line or the one above.',
    );
  });

  test('the scan is not blind', () {
    expect(
      scanned.length,
      greaterThanOrEqualTo(40),
      reason: 'only ${scanned.length} lazy lists found — the pattern broke',
    );
    expect(
      scanned.where((s) => s.contains('entity_list_screen_scaffold.dart')),
      isNotEmpty,
      reason: "the entity list's ListView.builder must be scanned",
    );
  });

  test('an undecided list is flagged, and only its own arguments count', () {
    const offender = '''
ListView.builder(
  itemCount: n,
  itemBuilder: (context, i) => ListView(
    addAutomaticKeepAlives: false,
    itemExtent: 40,
    children: const [],
  ),
)''';
    final calls = _lazyListCalls(offender);
    expect(calls, hasLength(2), reason: 'the nested list is its own call');
    expect(calls.first.line, 1);
    expect(
      _decided(calls.first.args),
      isFalse,
      reason: "a nested list's arguments are not the outer list's",
    );
    expect(_decided(calls.last.args), isTrue);

    expect(
      _decided(
        _lazyListCalls(
          'ListView(addAutomaticKeepAlives: true, children: c)',
        ).single.args,
      ),
      isFalse,
      reason: 'keeping the default needs the marker and a reason',
    );
    for (final decided in const [
      'ListView(addAutomaticKeepAlives: false, children: c)',
      'ListView.separated(addAutomaticKeepAlives: false, itemCount: n)',
      'SliverList.builder(itemExtentBuilder: e, itemBuilder: b)',
      'ListView.builder(prototypeItem: p, itemBuilder: b)',
      'SliverChildBuilderDelegate(b, addAutomaticKeepAlives: false)',
    ]) {
      expect(
        _decided(_lazyListCalls(decided).single.args),
        isTrue,
        reason: decided,
      );
    }
  });

  test('what the rule does not read is never matched', () {
    for (final other in const [
      'ReorderableListView.builder(itemBuilder: b)',
      'SliverReorderableList(itemBuilder: b)',
      'GridView.builder(itemBuilder: b)',
      '_buildListView(children: c)',
      'ListViewHost(children: c)',
      // These two take no `addAutomaticKeepAlives`: their delegate decides,
      // and the delegate is read on its own.
      'ListView.custom(childrenDelegate: d)',
      'SliverList(delegate: d)',
    ]) {
      expect(_lazyListCalls(other), isEmpty, reason: other);
    }
  });
}

/// Drop `//` comment tails so the scan reads code, not prose. Per line, never
/// dropping a line, so the reported line numbers still point at the source.
String _stripComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

class _Call {
  const _Call(this.args, this.line);
  final String args;
  final int line;
}

/// `ListView.custom` and a bare `SliverList` are left out on purpose: neither
/// takes `addAutomaticKeepAlives`, and the `SliverChild*Delegate` they are
/// handed is matched on its own.
///
/// Every lazy list invocation's own argument text, in source order, with
/// nested calls kept intact but nested lists also returned as separate
/// entries.
List<_Call> _lazyListCalls(String source) {
  final calls = <_Call>[];
  final pattern = RegExp(
    r'(?<![A-Za-z0-9_.])'
    r'(ListView(\.builder|\.separated)?'
    r'|SliverList\.(builder|separated|list)'
    r'|SliverChildBuilderDelegate|SliverChildListDelegate)'
    r'\(',
  );
  for (final match in pattern.allMatches(source)) {
    var depth = 1;
    var i = match.end;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
      i++;
    }
    calls.add(
      _Call(
        source.substring(match.end, i - 1),
        '\n'.allMatches(source.substring(0, match.start)).length + 1,
      ),
    );
  }
  return calls;
}

/// Whether the list has decided: keep-alives off, or a fixed row extent.
bool _decided(String args) {
  if (_topLevelArgValue(args, 'addAutomaticKeepAlives') == 'false') {
    return true;
  }
  return _topLevelArgValue(args, 'itemExtent') != null ||
      _topLevelArgValue(args, 'itemExtentBuilder') != null ||
      _topLevelArgValue(args, 'prototypeItem') != null;
}

/// The value text of the `name:` argument at [args]' own level, or null when
/// it does not pass one. Nested calls are skipped, so a child widget's
/// arguments never stand in for the outer list's.
String? _topLevelArgValue(String args, String name) {
  final pattern = RegExp('(?<![A-Za-z0-9_])$name:');
  var depth = 0;
  for (var i = 0; i < args.length; i++) {
    final c = args[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (depth == 0) {
      final match = pattern.matchAsPrefix(args, i);
      if (match == null) continue;
      var inner = 0;
      for (var j = match.end; j < args.length; j++) {
        final v = args[j];
        if (v == '(' || v == '[' || v == '{') {
          inner++;
        } else if (v == ')' || v == ']' || v == '}') {
          inner--;
        } else if (v == ',' && inner == 0) {
          return args.substring(match.end, j).trim();
        }
      }
      return args.substring(match.end).trim();
    }
  }
  return null;
}

List<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList(growable: false);
