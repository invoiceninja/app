import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';

/// The create button a narrow list floats in its bottom-end corner: an
/// extended FAB that says what it makes — "+ New Client" — rather than a bare
/// `+`, the same words as the wide header's primary button
/// (`EntityListTopRow`).
///
/// Every list that floats one uses this, so they read alike: the entity lists
/// (`EntityListScreenScaffold`) and the Daily / Weekly / Calendar task views.
/// The kanban board floats none (`docs/tasks-views.md`).
///
/// Still 56 px tall — `FloatingActionButton.extended`'s M3 height — so the
/// scroll clearance under it is unchanged ([kFabClearance] in
/// `fab_clearance.dart`); only its width grows, and the clearance already
/// lifts the last row clear of the whole button. Its shape is the theme's
/// rounded rectangle (`theme.dart`), never a pill.
class EntityCreateFab extends StatelessWidget {
  const EntityCreateFab({
    required this.labelKey,
    required this.onPressed,
    super.key,
  });

  /// The entity's `new_<entity>` key, e.g. `new_client`.
  final String labelKey;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.tr(labelKey);
    return FloatingActionButton.extended(
      tooltip: label,
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
    );
  }
}
