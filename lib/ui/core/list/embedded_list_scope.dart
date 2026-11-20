import 'package:flutter/widgets.dart';

import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/list/deep_link_filter_intent.dart';

/// Marks the subtree as an **embedded** entity list — one rendered inside a
/// detail screen tab (Client/Vendor/Bank-account), not a standalone list
/// screen. Row tiles read this to adopt the Client-datatable look — **roomier
/// row padding**, and nothing else — so the bottom-of-detail tables match the
/// polished standalone Clients list.
///
/// It used to carry the `⋮`-vs-`⋯` decision too, forcing the vertical menu on
/// an embedded row while a standalone row kept whatever glyph its tile passed.
/// Every overflow menu is `⋮` now (CLAUDE.md § Design system (v2)), so
/// `EntityActionsPopupButton` no longer reads this at all and that divergence
/// is gone.
///
/// Absent in standalone list screens, so [of] returns `false` there and those
/// rows keep the tighter padding (per-context divergence is intended).
///
/// Mirrors the `FormatterScope` / `DetailScrollScope` pattern. Presence is
/// structurally constant for a given subtree, so [updateShouldNotify] is
/// always `false` — reading it registers a dependency that never forces an
/// extra rebuild.
class EmbeddedListScope extends InheritedWidget {
  const EmbeddedListScope({
    super.key,
    this.entityType,
    this.standaloneIntent,
    required super.child,
  });

  /// The rows' entity. A row tap opening a record of this type carries
  /// [standaloneIntent]; a link in a cell to another entity does not.
  final EntityType? entityType;

  /// Read at tap time (the tab's filters may have changed since the build):
  /// the filter state the standalone list adopts when a row opens there, so
  /// the list beside the record is still this tab's rows. See
  /// `GenericListViewModel.standaloneIntent`.
  final ListFilterIntent? Function()? standaloneIntent;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EmbeddedListScope>() != null;

  /// The intent a row tap opening a [type] record carries, or null outside an
  /// embedded list, for another entity, or when the list has no parent scope.
  /// No dependency: a tap handler reads it, nothing rebuilds on it.
  static ListFilterIntent? rowIntentOf(BuildContext context, EntityType type) {
    final scope = context.getInheritedWidgetOfExactType<EmbeddedListScope>();
    if (scope == null || scope.entityType != type) return null;
    return scope.standaloneIntent?.call();
  }

  @override
  bool updateShouldNotify(EmbeddedListScope oldWidget) => false;
}
