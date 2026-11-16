/// How the kanban board is drawn for this user — which fields a card shows,
/// what the lanes group by, which columns are folded away.
///
/// A leaf (`dart:convert` only), like `tasks_view_mode.dart`, so
/// `lib/app/kanban_prefs_controller.dart` can persist it without importing a
/// screen. Stored as one JSON string under `DevicePrefKeys.kanban`.
library;

import 'dart:convert';

/// A line of a kanban card the user can switch off — or, for the ones that
/// start off, on. The title is not here: a card without one is not a card.
enum KanbanCardField {
  client,
  project,
  assignee,
  time,

  /// The task number above the title. Off unless asked for: most boards are
  /// read by title, and a card whose title IS its number (no description)
  /// shows it regardless.
  number(defaultOn: false);

  const KanbanCardField({this.defaultOn = true});

  final bool defaultOn;

  /// Every field at its default.
  static Set<KanbanCardField> get defaults => {
    for (final f in values)
      if (f.defaultOn) f,
  };
}

/// The second axis of the board: none, or a lane per client / project /
/// assignee.
enum KanbanGroupBy { none, client, project, assignee }

class KanbanPrefs {
  const KanbanPrefs({
    this.groupBy = KanbanGroupBy.none,
    this.collapsedStatusIds = const {},
    this.closedLanes = const {},
    Set<KanbanCardField>? fields,
  }) : _fields = fields;

  /// Lanes folded shut, as `<groupBy>:<record id>` (see [laneKey]) — the same
  /// client can be open as a client lane and shut as nothing else.
  final Set<String> closedLanes;

  static String laneKey(KanbanGroupBy groupBy, String id) =>
      '${groupBy.name}:$id';

  bool isLaneClosed(String id) => closedLanes.contains(laneKey(groupBy, id));

  KanbanPrefs toggleLane(String id) {
    final key = laneKey(groupBy, id);
    final next = {...closedLanes};
    if (!next.remove(key)) next.add(key);
    return copyWith(closedLanes: next);
  }

  final KanbanGroupBy groupBy;

  /// Statuses drawn as a narrow strip. Status ids are unique across
  /// companies, so one set serves them all.
  final Set<String> collapsedStatusIds;

  final Set<KanbanCardField>? _fields;

  /// The fields a card shows.
  Set<KanbanCardField> get fields => _fields ?? KanbanCardField.defaults;

  bool shows(KanbanCardField field) => fields.contains(field);

  KanbanPrefs copyWith({
    KanbanGroupBy? groupBy,
    Set<String>? collapsedStatusIds,
    Set<String>? closedLanes,
    Set<KanbanCardField>? fields,
  }) => KanbanPrefs(
    groupBy: groupBy ?? this.groupBy,
    collapsedStatusIds: collapsedStatusIds ?? this.collapsedStatusIds,
    closedLanes: closedLanes ?? this.closedLanes,
    fields: fields ?? _fields,
  );

  KanbanPrefs toggleField(KanbanCardField field) {
    final next = {...fields};
    if (!next.remove(field)) next.add(field);
    return copyWith(fields: next);
  }

  KanbanPrefs toggleCollapsed(String statusId) {
    final next = {...collapsedStatusIds};
    if (!next.remove(statusId)) next.add(statusId);
    return copyWith(collapsedStatusIds: next);
  }

  /// Fields are stored as their DIFFERENCE from the defaults — `hidden` for
  /// the ones that start on, `shown` for the ones that start off — so a field
  /// added by a later build appears at its default instead of being read as
  /// "the user switched it off".
  String encode() => jsonEncode({
    if (groupBy != KanbanGroupBy.none) 'group_by': groupBy.name,
    if (collapsedStatusIds.isNotEmpty)
      'collapsed': collapsedStatusIds.toList()..sort(),
    if (closedLanes.isNotEmpty) 'closed_lanes': closedLanes.toList()..sort(),
    'hidden': [
      for (final f in KanbanCardField.values)
        if (f.defaultOn && !fields.contains(f)) f.name,
    ],
    'shown': [
      for (final f in KanbanCardField.values)
        if (!f.defaultOn && fields.contains(f)) f.name,
    ],
  });

  /// Never throws: anything unreadable — absent, written by a newer build,
  /// hand-edited — is the defaults, and an unknown name inside is skipped.
  static KanbanPrefs decode(String? raw) {
    if (raw == null || raw.isEmpty) return const KanbanPrefs();
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return const KanbanPrefs();
    }
    if (json is! Map) return const KanbanPrefs();
    final map = json;
    Set<String> names(String key) => switch (map[key]) {
      final List<Object?> l => l.whereType<String>().toSet(),
      _ => const {},
    };
    final hidden = names('hidden');
    final shown = names('shown');
    return KanbanPrefs(
      groupBy: KanbanGroupBy.values.firstWhere(
        (g) => g.name == map['group_by'],
        orElse: () => KanbanGroupBy.none,
      ),
      collapsedStatusIds: names('collapsed'),
      closedLanes: names('closed_lanes'),
      fields: {
        for (final f in KanbanCardField.values)
          if (f.defaultOn ? !hidden.contains(f.name) : shown.contains(f.name))
            f,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KanbanPrefs && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
