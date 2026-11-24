import 'package:flutter/widgets.dart';

import 'package:admin/app/list_column_widths_controller.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';

/// Provides the dragged column widths ([ListColumnWidthsController]) to every
/// list, above the router (`main.dart`), the way `ListDensityScope` provides
/// the row density. Absent — a widget test, a preview — lists show their
/// declared widths and draw no resize handles.
class ListColumnWidthsScope
    extends InheritedNotifier<ListColumnWidthsController> {
  const ListColumnWidthsScope({
    super.key,
    required ListColumnWidthsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ListColumnWidthsController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ListColumnWidthsScope>()
      ?.notifier;
}

/// What a resize handle reports, for one table.
class ColumnResizeCallbacks {
  const ColumnResizeCallbacks({
    required this.onUpdate,
    required this.onEnd,
    required this.onReset,
  });

  /// The column is being dragged to [width] (live, not yet saved).
  final void Function(String columnId, double width) onUpdate;

  /// The drag ended — save the width it reached.
  final void Function(String columnId) onEnd;

  /// A double-click / double-tap on the handle — back to the declared width.
  final void Function(String columnId) onReset;
}

/// The width each column of ONE wide table renders at, read by the header
/// strip (`_HeaderCell`) and every row (`CellSlot`) so the two stay aligned.
///
/// Provided by `EntityListScreenScaffold._wideTable`. A column missing from
/// [widths] flexes (`Expanded`); outside a scope every column renders its
/// declared [ColumnDefinition.width].
///
/// An [InheritedModel] keyed by column id: the stretch recomputes widths on
/// every frame of a window resize, and only the cells whose own column moved
/// rebuild — not every cell of every visible row.
class ListColumnLayout extends InheritedModel<String> {
  const ListColumnLayout({
    super.key,
    required this.widths,
    this.resize,
    required super.child,
  });

  final Map<String, double> widths;

  /// Null when nothing may store a width — no handles are drawn.
  final ColumnResizeCallbacks? resize;

  /// The aspect a resize-handle reader depends on.
  static const String _resizeAspect = '\u0000resize';

  /// [column]'s width in the enclosing table, or null when it flexes.
  static double? widthOf(
    BuildContext context,
    ColumnDefinition<dynamic> column,
  ) {
    final scope = InheritedModel.inheritFrom<ListColumnLayout>(
      context,
      aspect: column.id,
    );
    if (scope == null) return column.width;
    return scope.widths[column.id];
  }

  static ColumnResizeCallbacks? resizeOf(BuildContext context) =>
      InheritedModel.inheritFrom<ListColumnLayout>(
        context,
        aspect: _resizeAspect,
      )?.resize;

  @override
  bool updateShouldNotify(ListColumnLayout oldWidget) =>
      !_sameWidths(widths, oldWidget.widths) ||
      !identical(resize, oldWidget.resize);

  @override
  bool updateShouldNotifyDependent(
    ListColumnLayout oldWidget,
    Set<String> dependencies,
  ) {
    for (final aspect in dependencies) {
      if (aspect == _resizeAspect) {
        if (!identical(resize, oldWidget.resize)) return true;
      } else if (widths[aspect] != oldWidget.widths[aspect]) {
        return true;
      }
    }
    return false;
  }

  static bool _sameWidths(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// A column the stretch may widen: start-aligned text wide enough to be worth
/// it (a name, a description, notes). Dates, numbers, amounts and pills stay
/// at their declared width.
const double kStretchableColumnMinWidth = 160;

/// Resolve every column's rendered width for one table [available] pixels
/// wide (docs/entity-lists.md § A dragged column width is a device
/// preference).
///
/// 1. A width the user dragged ([dragged]) wins, clamped to
///    [kListColumnMinWidth]..[kListColumnMaxWidth].
/// 2. Otherwise the column's declared width; a flex column is left out of the
///    map and renders `Expanded`.
/// 3. With no flex column and width to spare, the spare goes to the
///    stretchable columns ([kStretchableColumnMinWidth], start-aligned, not
///    dragged), in proportion to their widths — so the right of a wide window
///    is not an empty strip while a client name is cut short.
Map<String, double> resolveColumnWidths<T>({
  required List<ColumnDefinition<T>> columns,
  required Map<String, double> dragged,
  required double available,
}) {
  final out = <String, double>{};
  for (final c in columns) {
    final d = dragged[c.id];
    if (d != null) {
      out[c.id] = d.clamp(kListColumnMinWidth, kListColumnMaxWidth);
    } else if (!c.isFlex) {
      out[c.id] = c.width!;
    }
  }
  if (columns.any((c) => !out.containsKey(c.id))) return out;
  // One pixel of slack: the rows' own chrome is measured, not derived, and a
  // sum that lands a hair past the row's width is an overflow.
  final spare = available - computeTableMinWidth(columns, widths: out) - 1;
  if (spare < 1) return out;
  final grow = [
    for (final c in columns)
      if (!dragged.containsKey(c.id) &&
          c.align == ColumnAlign.start &&
          c.width! >= kStretchableColumnMinWidth)
        c,
  ];
  if (grow.isEmpty) return out;
  final total = grow.fold<double>(0, (sum, c) => sum + c.width!);
  for (final c in grow) {
    out[c.id] = c.width! + (spare * c.width! / total).floorToDouble();
  }
  return out;
}
