import 'package:flutter/widgets.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';

/// The dashboard's half of the Compact density preference
/// (`docs/list-density.md` § The dashboard).
///
/// **`dense`, never `compact`.** On the dashboard `compact:` already means the
/// phone form — `NeedsAttentionBand.compact`, `DashboardRecordRow.compact`,
/// and each panel card's `compact:` — so the
/// preference is called `dense` everywhere here, and every dashboard widget
/// reads it through [dashboardDense] so one grep finds them all.

/// Whether the dashboard renders Compact. Subscribes: call from `build`.
///
/// An `InheritedNotifier` read, so it is legal under the dashboard's
/// `IntrinsicHeight` rows — a `LayoutBuilder` there is not (CLAUDE.md
/// § Dashboard panels).
bool dashboardDense(BuildContext context) =>
    ListDensityScope.isCompactOf(context);

/// Marks a subtree as the dashboard, the way `RecordColumnScope` marks a
/// record screen's profile column.
///
/// `DashboardCardShell` is also the section card of several edit forms, which
/// Compact deliberately leaves alone; the shell tightens only inside one of
/// these two markers. Mounted once around each dashboard body's scroll view.
class DashboardScope extends InheritedWidget {
  const DashboardScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DashboardScope>() != null;

  @override
  bool updateShouldNotify(DashboardScope oldWidget) => false;
}

/// A dashboard row's vertical padding under Compact with a pointer; a touch
/// row spends it all on the 44 px action box instead.
const double kDenseRowPad = 2;

/// The row action box under Compact with a pointer (32 under Normal). Touch
/// keeps `InSizes.touchTarget`.
const double kDenseActionExtent = 28;

/// The chart's plot floor beside Activity under Compact (220 under Normal).
const double kChartMinPlotHeightDense = 168;

/// The figure cards' floor under Compact (`kFigureCardMinHeight`, 104, under
/// Normal). A floor: a larger text scale still grows the card.
const double kFigureCardMinHeightDense = 64;

/// Rows in a wide dashboard list panel under Compact (5 under Normal). The
/// lists fetch `kDashboardListPageSize` rows, so this needs no fetch change.
const int kDensePanelRows = 8;

/// A dashboard card's corner radius: [InRadii.r3], one step tighter under
/// Compact. The dashboard's cards are tiles on a page; nothing else in the
/// app changes radius with the density.
///
/// Dashboard cards paint no shadow at all, in either density: the 1 px
/// border carries the edge, so they read as tiles on a page rather than
/// paper floating over it (`docs/list-density.md` § The dashboard).
double dashboardCardRadius(BuildContext context) =>
    dashboardDense(context) ? InRadii.r2 : InRadii.r3;
