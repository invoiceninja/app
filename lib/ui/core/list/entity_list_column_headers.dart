import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/list_column_widths_controller.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/list/generic_list_view_model.dart';
import 'package:admin/ui/core/list/list_column_widths.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/core/widgets/selection_checkbox.dart';

/// Uppercase eyebrow column labels above the table rows at wide widths.
/// Iterates the VM's current `columns` so header widths and labels stay in
/// lock-step with whatever the user has chosen via the column picker.
///
/// Doubles as the desktop sort control: every header is clickable and the
/// active one shows a ↑/↓ indicator. Generic over the entity type — any
/// [GenericListViewModel] with `ColumnDefinition<T>` columns can use it.
class EntityListColumnHeaders<T> extends StatelessWidget {
  const EntityListColumnHeaders({super.key, required this.vm});

  final GenericListViewModel<T> vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: tokens.ink3,
    );
    return Container(
      // 5.1.30's header band: a `surfaceAlt` fill with a rule under it
      // (restored in Nov 2026 after a fill-less caption redesign).
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      // 12 at the Comfortable list density (5.1.30's); 2 at Compact
      // (docs/list-density.md). The 32 px select-all slot sets the rest of
      // the height.
      padding: ListDensityScope.isCompactOf(context)
          ? const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 2)
          : const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      child: Row(
        children: [
          // Leading actions slot — empty label, mirrors row's `…` menu.
          SizedBox(width: colWMoreMenu()),
          const SizedBox(width: kColActionsLeadingGap),
          // Avatar/checkbox slot. On desktop, hovering this slot reveals a
          // select-all checkbox.
          SizedBox(
            width: kColLeadingWidth,
            child: _HeaderSelectAllSlot<T>(vm: vm),
          ),
          const SizedBox(width: kColCellGap),
          // Each cell carries the gap after it, which is where its resize
          // handle sits — the same total width as cell + gap in the rows.
          for (final col in vm.columns)
            _HeaderCell<T>(column: col, labelStyle: labelStyle, vm: vm),
          // Pill column: reserved, unlabeled.
          const SizedBox(width: kColWPillSlot),
        ],
      ),
    );
  }
}

class _HeaderCell<T> extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.labelStyle,
    required this.vm,
  });
  final ColumnDefinition<T> column;
  final TextStyle labelStyle;
  final GenericListViewModel<T> vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final isActive = vm.sortField == column.id;
    final activeStyle = labelStyle.copyWith(color: tokens.ink2);
    final text = Text(
      // `resolveLabel`, not `context.tr(labelKey)`: a custom-field column
      // carries the COMPANY's own label ("Region"), which is user data with no
      // translation key.
      column.resolveLabel(context).toUpperCase(),
      style: isActive ? activeStyle : labelStyle,
    );
    final arrow = isActive
        ? Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
            child: Icon(
              vm.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: tokens.ink2,
            ),
          )
        : const SizedBox.shrink();
    final isEnd = column.align == ColumnAlign.end;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: isEnd ? [arrow, text] : [text, arrow],
    );
    final content = InkWell(
      // Display-only columns (tags, notes, a derived status, a "View" link)
      // have no Drift column to order by — a null `onTap` also drops the
      // hover/ripple affordance, so the header doesn't advertise a sort it
      // can't perform. `setSort` rejects them too (via `isValidColumnId`),
      // which covers the persisted-sort and deep-link paths.
      onTap: column.sortable
          ? () => vm.setSort(
              field: column.id,
              // Flip direction only when the active field is tapped again;
              // switching field keeps the current direction.
              ascending: isActive ? !vm.sortAscending : vm.sortAscending,
            )
          : null,
      child: Align(
        alignment: isEnd
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
          // Scale the label down a hair if it would otherwise overflow its
          // fixed column width — e.g. a long uppercased label whose width edges
          // a sub-pixel past `column.width` in the bundled Inter Tight font.
          // `scaleDown` only shrinks when needed (labels that fit are untouched)
          // and, unlike the bare Row, never throws a RenderFlex overflow.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: isEnd
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: row,
          ),
        ),
      ),
    );
    // The table's resolved width (a dragged one, or the stretch), else the
    // declared one — the same lookup every row's `CellSlot` makes.
    final width = ListColumnLayout.widthOf(context, column);
    final resize = ListColumnLayout.resizeOf(context);
    final withGap = Row(
      children: [
        Expanded(child: content),
        const SizedBox(width: kColCellGap),
      ],
    );
    final slot = resize == null
        ? withGap
        : LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                withGap,
                PositionedDirectional(
                  top: 0,
                  bottom: 0,
                  end: 0,
                  width:
                      kColCellGap + _ColumnResizeHandle.insetInto(column.align),
                  child: _ColumnResizeHandle(
                    columnId: column.id,
                    currentWidth: c.maxWidth - kColCellGap,
                    callbacks: resize,
                  ),
                ),
              ],
            ),
          );
    if (width == null) return Expanded(child: slot);
    return SizedBox(width: width + kColCellGap, child: slot);
  }
}

/// The drag target on a header cell's trailing edge: the gap after the cell
/// plus a few pixels into it (docs/entity-lists.md § A dragged column width is
/// a device preference). Dragging sets the column's width live; letting go
/// saves it; a double-click or double-tap puts the declared width back.
///
/// The line it draws shows on hover and while dragging. On a touch-first
/// device, where nothing hovers, a faint one stays drawn so the edge reads as
/// something to pull.
class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.columnId,
    required this.currentWidth,
    required this.callbacks,
  });

  final String columnId;

  /// What the column renders at now — the start of a drag, whether its width
  /// came from the user, its definition or the stretch.
  final double currentWidth;
  final ColumnResizeCallbacks callbacks;

  /// How far the target reaches into the cell, past the gap: a finger needs
  /// more than a pointer. Never into an end-aligned cell — its label and sort
  /// arrow sit right there (an amount, a balance), and the header must stay a
  /// sort control across the whole label.
  static double insetInto(ColumnAlign align) {
    if (align == ColumnAlign.end) return 0;
    return Env.isTouchPrimary ? 16 : 6;
  }

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  bool _hovered = false;
  double? _startWidth;
  double _dragged = 0;

  void _onStart(DragStartDetails _) {
    setState(() {
      _startWidth = widget.currentWidth;
      _dragged = 0;
    });
  }

  void _onUpdate(DragUpdateDetails d) {
    final start = _startWidth;
    if (start == null) return;
    // Rightward widens in a left-to-right layout; the edge is on the left in
    // right-to-left, so leftward widens there.
    final sign = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    // The running total stays inside the limits too, so an edge pinned at
    // 56 px follows the pointer the moment it turns back.
    _dragged =
        (start + _dragged + sign * (d.primaryDelta ?? 0)).clamp(
          kListColumnMinWidth,
          kListColumnMaxWidth,
        ) -
        start;
    // Whole pixels, as the width is saved — nothing shifts on release.
    widget.callbacks.onUpdate(
      widget.columnId,
      (start + _dragged).roundToDouble(),
    );
  }

  void _onEnd() {
    if (_startWidth == null) return;
    setState(() => _startWidth = null);
    widget.callbacks.onEnd(widget.columnId);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final dragging = _startWidth != null;
    final Color? line = dragging
        ? tokens.accent
        : _hovered
        ? tokens.ink3
        : Env.isTouchPrimary
        ? tokens.border
        : null;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          // Translucent: a tap on the part over the cell still reaches the
          // header's sort control below; only a drag or a double-tap is ours.
          behavior: HitTestBehavior.translucent,
          // From the press, not from where the drag slop ran out: the edge
          // follows the pointer exactly.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: (_) => _onEnd(),
          onHorizontalDragCancel: _onEnd,
          onDoubleTap: () => widget.callbacks.onReset(widget.columnId),
          child: Align(
            // Centred on the gap between this column and the next.
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: kColCellGap / 2 - 1,
              ),
              child: SizedBox(
                width: 2,
                height: 16,
                child: line == null ? null : ColoredBox(color: line),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The wide-mode column header's leading slot. Empty at rest (5.1.30's
/// behaviour, restored in Nov 2026 after an always-drawn circle); hovering it
/// with a pointer reveals an empty select-all checkbox. While in multi-select
/// the checkbox is always visible and reflects whether *every* visible row is
/// selected — clicking it then toggles between "select all" and "clear".
class _HeaderSelectAllSlot<T> extends StatefulWidget {
  const _HeaderSelectAllSlot({required this.vm});
  final GenericListViewModel<T> vm;

  @override
  State<_HeaderSelectAllSlot<T>> createState() =>
      _HeaderSelectAllSlotState<T>();
}

class _HeaderSelectAllSlotState<T> extends State<_HeaderSelectAllSlot<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final selecting = vm.isInMultiselect;
    // Against the VISIBLE count, not `items.length` — see
    // `GenericListViewModel.visibleItemCount`. A collapsed group otherwise
    // pinned this to false forever and the checkbox became inert.
    final visible = vm.visibleItemCount;
    final allSelected = selecting && visible > 0 && vm.countSelected >= visible;

    Widget child;
    VoidCallback? onTap;
    if (selecting) {
      child = SelectionCheckbox(checked: allSelected);
      onTap = () {
        if (allSelected) {
          vm.clearSelection();
        } else {
          vm.selectAllVisible();
        }
      };
    } else if (_isHovered && vm.items.isNotEmpty) {
      child = const SelectionCheckbox(checked: false);
      onTap = vm.selectAllVisible;
    } else {
      child = const SizedBox.shrink();
    }

    Widget slot = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: kColLeadingWidth,
        height: kColLeadingWidth,
        child: Center(child: child),
      ),
    );
    if (onTap != null && !selecting) {
      // A bare box at rest — say what it does.
      slot = Tooltip(message: context.tr('select_all_visible'), child: slot);
    }
    return MouseRegion(
      onEnter: (_) {
        if (!_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: slot,
    );
  }
}
