import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/tasks/kanban_prefs.dart';

void main() {
  test('nothing stored is the defaults', () {
    for (final raw in [null, '', 'not json', '[]', '{"hidden": 3}']) {
      final prefs = KanbanPrefs.decode(raw);
      expect(prefs.groupBy, KanbanGroupBy.none, reason: '$raw');
      expect(prefs.collapsedStatusIds, isEmpty, reason: '$raw');
      expect(prefs.fields, KanbanCardField.defaults, reason: '$raw');
    }
    // The number starts off; everything else on.
    expect(const KanbanPrefs().shows(KanbanCardField.number), isFalse);
    expect(const KanbanPrefs().shows(KanbanCardField.project), isTrue);
  });

  test('a round trip keeps every choice', () {
    final prefs = const KanbanPrefs()
        .copyWith(groupBy: KanbanGroupBy.project)
        .toggleCollapsed('s2')
        .toggleField(KanbanCardField.client)
        .toggleField(KanbanCardField.number);
    final back = KanbanPrefs.decode(prefs.encode());
    expect(back, prefs);
    expect(back.groupBy, KanbanGroupBy.project);
    expect(back.collapsedStatusIds, {'s2'});
    expect(back.shows(KanbanCardField.client), isFalse);
    expect(back.shows(KanbanCardField.number), isTrue);
    expect(back.toggleCollapsed('s2').collapsedStatusIds, isEmpty);
  });

  test('fields are stored as a difference, so one added by a later build '
      'arrives at its default', () {
    // What a build that knew only `client` would have written with it hidden.
    final prefs = KanbanPrefs.decode(
      jsonEncode({
        'hidden': ['client'],
      }),
    );
    expect(prefs.shows(KanbanCardField.client), isFalse);
    for (final f in KanbanCardField.values) {
      if (f == KanbanCardField.client) continue;
      expect(prefs.shows(f), f.defaultOn, reason: f.name);
    }
  });

  test('a name this build does not know is skipped, not fatal', () {
    final prefs = KanbanPrefs.decode(
      jsonEncode({
        'group_by': 'sprint',
        'hidden': ['estimate', 'time'],
        'shown': ['priority'],
      }),
    );
    expect(prefs.groupBy, KanbanGroupBy.none);
    expect(prefs.shows(KanbanCardField.time), isFalse);
    expect(prefs.shows(KanbanCardField.client), isTrue);
  });

  test('a folded lane is remembered per grouping', () {
    final byClient = const KanbanPrefs(
      groupBy: KanbanGroupBy.client,
    ).toggleLane('x1');
    expect(byClient.isLaneClosed('x1'), isTrue);
    // The same id under another grouping is another lane.
    final byProject = byClient.copyWith(groupBy: KanbanGroupBy.project);
    expect(byProject.isLaneClosed('x1'), isFalse);

    final back = KanbanPrefs.decode(byClient.encode());
    expect(back.isLaneClosed('x1'), isTrue);
    expect(back.toggleLane('x1').closedLanes, isEmpty);
  });
}
