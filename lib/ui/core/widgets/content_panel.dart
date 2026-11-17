import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';

/// The white rounded card a screen's rows sit in: `surface` fill, `border`,
/// [InRadii.r3] corners and `shadow1` — the chrome every standalone entity
/// list draws its rows in (docs/entity-lists.md § A standalone list sits in a
/// white panel), for the screens that are lists without being entity lists:
/// the Tasks daily / weekly / calendar views and the Activity feed.
///
/// The inner `Material(type: transparency)` hosts the ink of every row
/// `InkWell` inside, so a hover paints inside the clip, over the fill, and
/// never leaks past the rounded corners.
class ContentPanelCard extends StatelessWidget {
  const ContentPanelCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r3),
        boxShadow: tokens.shadow1,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// [ContentPanelCard] inset on the page the way a standalone entity list's
/// panel is: on a [wide] pane by [entityListTableInset] (24 each side so its
/// edges line up with the header row above; above and below per the list
/// density); on a narrow one 16 px each side and [InSpacing.md] above and
/// below.
///
/// **The panel owns the bottom safe inset** (CLAUDE.md § Design system (v2):
/// one surface, one safe-area owner). Its bottom margin adds
/// `MediaQuery.paddingOf(context).bottom`, and [child] is handed a
/// `MediaQuery` with the bottom padding removed — so a `fabScrollClearance`
/// inside resolves to the FAB's height alone, and nothing pays the inset a
/// second time.
class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.wide,
    required this.child,
    this.side,
    this.top,
    this.bottom,
  });

  /// The pane's width class, as the screen already computed it
  /// (`Breakpoints.isWide(constraints)`).
  final bool wide;

  /// The margin each side; null is [sideOf]. A screen whose other content
  /// keeps a different gutter (the Activity feed under its chart card) passes
  /// that one, so the edges line up.
  final double? side;

  /// The space above the panel; null is [topOf]. Only a screen that cannot
  /// scroll and has measured that it has no height to spare passes less.
  final double? top;

  /// The whole space below the panel, the bottom safe inset included. Null
  /// is [bottomOf]: the default gap plus the inset. A screen whose content
  /// must clear its FAB rather than scroll under it (the weekly grid's pinned
  /// totals row) passes the clearance.
  final double? bottom;

  final Widget child;

  /// The margin each side: 24 on a wide pane, 16 on a narrow one.
  static double sideOf({required bool wide}) => wide ? 24 : 16;

  static EdgeInsetsDirectional _wideInset(BuildContext context) =>
      entityListTableInset(compact: ListDensityScope.isCompactOf(context));

  /// The default top margin, for a caller that budgets the panel's height
  /// before it lays out (the calendar's never-scrolling month grid).
  static double topOf(BuildContext context, {required bool wide}) =>
      wide ? _wideInset(context).top : InSpacing.md(context);

  /// The default bottom margin, the safe inset included.
  static double bottomOf(BuildContext context, {required bool wide}) =>
      (wide ? _wideInset(context).bottom : InSpacing.md(context)) +
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final gutter = side ?? sideOf(wide: wide);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        top ?? topOf(context, wide: wide),
        gutter,
        bottom ?? bottomOf(context, wide: wide),
      ),
      child: ContentPanelCard(
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: child,
        ),
      ),
    );
  }
}
