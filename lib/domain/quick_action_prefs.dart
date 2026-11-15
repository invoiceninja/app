/// One entry of a record screen's quick-action arrangement: which action, and
/// whether it may take a tile. Order is the list's own.
///
/// Stored as `"<id>|<1|0>"`, the shape `SidebarMenuEntryPref` and
/// `DashboardPanelPref` already use.
class QuickActionPref {
  const QuickActionPref({required this.id, this.visible = true});

  /// The action's enum `name` (`sendEmail`).
  final String id;
  final bool visible;

  QuickActionPref copyWith({bool? visible}) =>
      QuickActionPref(id: id, visible: visible ?? this.visible);

  String toJson() => '$id|${visible ? 1 : 0}';

  /// Strict, like `SidebarMenuEntryPref.tryParse`: a truncated entry is
  /// dropped and re-defaulted by [resolveQuickActionPrefs], never read as
  /// hidden.
  static QuickActionPref? tryParse(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split('|');
    if (parts.length != 2 || parts[0].isEmpty) return null;
    if (parts[1] != '0' && parts[1] != '1') return null;
    return QuickActionPref(id: parts[0], visible: parts[1] == '1');
  }

  @override
  bool operator ==(Object other) =>
      other is QuickActionPref && other.id == id && other.visible == visible;

  @override
  int get hashCode => Object.hash(id, visible);
}

/// The app's own arrangement for a catalog: [catalog] in order, the ids in
/// [defaultShown] visible.
List<QuickActionPref> defaultQuickActionPrefs(
  List<String> catalog,
  Set<String> defaultShown,
) => [
  for (final id in catalog)
    QuickActionPref(id: id, visible: defaultShown.contains(id)),
];

/// [stored] laid over the catalog: unknown ids dropped, duplicates collapsed,
/// and an action the stored arrangement has never seen placed at its default
/// rank with its default visibility — so a new action needs no migration.
List<QuickActionPref> resolveQuickActionPrefs(
  List<QuickActionPref>? stored,
  List<String> catalog,
  Set<String> defaultShown,
) {
  final defaults = defaultQuickActionPrefs(catalog, defaultShown);
  if (stored == null || stored.isEmpty) return defaults;
  final known = catalog.toSet();
  final seen = <String>{};
  final out = <QuickActionPref>[
    for (final p in stored)
      if (known.contains(p.id) && seen.add(p.id)) p,
  ];
  for (var i = 0; i < defaults.length; i++) {
    final d = defaults[i];
    if (seen.contains(d.id)) continue;
    // After the nearest preceding default that is present, else at the front.
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final k = out.indexWhere((p) => p.id == defaults[j].id);
      if (k >= 0) {
        at = k + 1;
        break;
      }
    }
    out.insert(at, d);
    seen.add(d.id);
  }
  return out;
}

/// [prefs] with the entry at [index] switched. A newly shown action joins the
/// end of the shown run, and a newly hidden one drops to just below it, so
/// the shown actions stay together at the top of the list in tile order.
List<QuickActionPref> toggleQuickActionPref(
  List<QuickActionPref> prefs,
  int index,
) {
  final next = List<QuickActionPref>.from(prefs);
  final moved = next.removeAt(index);
  final shownCount = next.where((p) => p.visible).length;
  // Shown entries are contiguous at the top by construction, but a stored
  // list need not be: insert after the last shown one wherever it sits.
  var at = 0;
  if (shownCount > 0) {
    at = next.lastIndexWhere((p) => p.visible) + 1;
  }
  next.insert(at, moved.copyWith(visible: !moved.visible));
  return next;
}
