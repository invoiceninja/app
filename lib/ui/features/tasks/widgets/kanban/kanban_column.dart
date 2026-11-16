import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/router.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/task_status_colors.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_board.dart'
    show kKanbanCardWidth;
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_card.dart';
import 'dart:async';
import 'package:admin/app/env.dart';
import 'package:admin/ui/core/utils/show_seconds.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_card_slot.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_drag_scroller.dart';
import 'package:admin/utils/formatting.dart';

/// How long the user must hold on a drag handle before the drag begins.
/// Down from Flutter's `kLongPressTimeout` (≈500ms) — fast enough that
/// the drag feels responsive on desktop but still distinguishable from a
/// short tap so the underlying tap-to-detail / vertical-scroll gestures
/// aren't accidentally captured.
const _kDragStartDelay = Duration(milliseconds: 200);

/// Builds the card for a task; `ghost` is the copy that rides under the
/// pointer during a drag.
typedef KanbanCardBuilder =
    Widget Function(BuildContext context, Task task, {required bool ghost});

/// One column on the kanban board. Renders the status header + a scrollable
/// list of cards, each a [KanbanCardSlot]: cards can be dropped onto cards
/// (insert above) or onto the empty area below (append).
///
/// A card drags whole — at once with a mouse, on a long press under a finger
/// (where a plain drag has to stay the column's scroll) — and a tap still opens
/// the task. Only the column header keeps a handle (`Icons.drag_indicator`):
/// reordering statuses is rare, and a header that moved under any drag would
/// be a trap.
class KanbanColumn extends StatefulWidget {
  const KanbanColumn({
    super.key,
    required this.status,
    required this.tasks,
    required this.companyId,
    required this.onAcceptTask,
    this.onAcceptStatus,
    this.canEdit = true,
    this.canCreate = true,
    this.scroller,
    this.cardBuilder,
    this.onToggleCollapse,
    this.onQuickAdd,
  });

  /// Creates a task titled by what was typed into the footer, in this
  /// column. Null makes the footer open the full create form instead.
  final Future<void> Function(String description)? onQuickAdd;

  final TaskStatus status;
  final List<Task> tasks;

  /// Active company id — threaded by value into each card's inline timer
  /// toggle (drag-feedback cards render in the Overlay, outside the
  /// KanbanViewModel Provider, so it can't be read from context there).
  final String companyId;

  /// Called when the user drops [task] onto this column. [beforeTaskId] is
  /// the id of the card the dragged task should appear *above*, or null
  /// to append at the bottom. Null makes the column no drop target at all —
  /// the "no status" column, which cards only ever leave.
  final void Function(Task task, String? beforeTaskId)? onAcceptTask;

  /// Called when the user drops [droppedStatus]'s column header onto this
  /// column. The board reorders the column set so [droppedStatus] lands
  /// where this column currently sits. Null disables column reorder.
  final void Function(TaskStatus droppedStatus)? onAcceptStatus;

  /// Whether the active user may rearrange the board. When false nothing
  /// drags and drops are no-ops — read-only users can't initiate a drop the
  /// server would reject anyway. NOT the gate on [canCreate].
  final bool canEdit;

  /// Whether the active user may start a new task — the `+ New Task` footer.
  ///
  /// Split from [canEdit] because the two ask different questions. This one is
  /// `create_task` (the token the server authorizes a create against; `can()`
  /// never derives it from `edit_task`). Since the kanban screen has no FAB
  /// (invoiceninja/flutter#135) this footer is the board's only create path,
  /// so conflating the two would leave a create-only user with no way to add a
  /// task at all.
  final bool canCreate;

  /// The board's drag pointer; the column scrolls itself up and down under it.
  final KanbanDragScroller? scroller;

  /// How a card is drawn. Null is a plain [KanbanCard].
  final KanbanCardBuilder? cardBuilder;

  /// Folds the column down to a strip. Null draws no control.
  final VoidCallback? onToggleCollapse;

  @override
  State<KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<KanbanColumn> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.scroller?.addListener(_onDragTick);
  }

  @override
  void didUpdateWidget(KanbanColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroller != widget.scroller) {
      oldWidget.scroller?.removeListener(_onDragTick);
      widget.scroller?.addListener(_onDragTick);
    }
  }

  @override
  void dispose() {
    widget.scroller?.removeListener(_onDragTick);
    _scroll.dispose();
    super.dispose();
  }

  /// A long column's far end is off screen, and a drag cannot scroll to it.
  void _onDragTick() => widget.scroller?.scroll(
    _scroll,
    _listKey.currentContext?.findRenderObject(),
  );

  Widget _card(BuildContext context, Task t, {required bool ghost}) =>
      widget.cardBuilder?.call(context, t, ghost: ghost) ??
      KanbanCard(
        task: t,
        companyId: widget.companyId,
        showTimerButton: !ghost,
        showMenu: !ghost,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final status = widget.status;
    final tasks = widget.tasks;
    final canEdit = widget.canEdit;
    final onAcceptTask = canEdit ? widget.onAcceptTask : null;
    final onAcceptStatus = canEdit ? widget.onAcceptStatus : null;
    // Column header: dot · name · count · total · controls. The handle is the
    // only draggable region; the whole header is still a DragTarget so a
    // dropped column lands on it.
    final headerDragHandle = onAcceptStatus != null
        ? _DragHandle<TaskStatus>(
            data: status,
            feedback: SizedBox(
              width: kKanbanCardWidth,
              child: KanbanColumnHeader(status: status, tasks: tasks),
            ),
            tokens: tokens,
            tooltipKey: 'drag_to_reorder',
          )
        : null;

    final header = KanbanColumnHeader(
      status: status,
      tasks: tasks,
      dragHandle: headerDragHandle,
      onToggleCollapse: widget.onToggleCollapse,
    );

    Widget headerSlot = header;
    if (onAcceptStatus != null) {
      headerSlot = DragTarget<TaskStatus>(
        onWillAcceptWithDetails: (details) => details.data.id != status.id,
        onAcceptWithDetails: (details) => onAcceptStatus(details.data),
        builder: (context, candidate, rejected) {
          if (candidate.isEmpty) return header;
          // Highlight the target header with a thin accent strip on top.
          return Stack(
            children: [
              header,
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(height: 3, color: tokens.accent),
              ),
            ],
          );
        },
      );
    }

    Widget list() => ListView.builder(
      key: _listKey,
      controller: _scroll,
      padding: const EdgeInsets.all(InSpacing.sm),
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final t = tasks[i];
        return KanbanCardSlot(
          task: t,
          card: _card(context, t, ghost: false),
          ghost: _card(context, t, ghost: true),
          canDrag: canEdit,
          scroller: widget.scroller,
          onDropAbove: onAcceptTask == null
              ? null
              : (dropped) => onAcceptTask(dropped, t.id),
        );
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headerSlot,
          Divider(height: 1, color: tokens.border),
          Expanded(
            child: onAcceptTask == null
                ? list()
                : DragTarget<Task>(
                    onAcceptWithDetails: (details) =>
                        onAcceptTask(details.data, null),
                    builder: (context, candidate, rejected) {
                      // Empty column + hovering card → paint a "drop here"
                      // hint so the user sees that the empty body is a valid
                      // target.
                      if (tasks.isEmpty && candidate.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(InSpacing.sm),
                          child: Container(
                            decoration: BoxDecoration(
                              color: tokens.accentSoft,
                              border: Border.all(color: tokens.accent),
                              borderRadius: BorderRadius.circular(InRadii.r2),
                            ),
                            alignment: Alignment.center,
                            child: Padding(
                              padding: EdgeInsets.all(InSpacing.md(context)),
                              child: Icon(
                                Icons.add,
                                size: 20,
                                color: tokens.accent,
                              ),
                            ),
                          ),
                        );
                      }
                      return list();
                    },
                  ),
          ),
          // Per-column quick-add (admin-portal + React parity): seeds the new
          // task with this column's status so it lands in the right column.
          // Since invoiceninja/flutter#135 removed the screen's FAB this is the
          // board's only create path — hence [canCreate] rather than [canEdit].
          if (widget.canCreate) ...[
            Divider(height: 1, color: tokens.border),
            _CreateFooter(
              onOpenForm: () => goEntityCreateFullWidth(
                context,
                '/tasks',
                extra: emptyTask().copyWith(statusId: status.id),
              ),
              onQuickAdd: widget.onQuickAdd,
            ),
          ],
        ],
      ),
    );
  }
}

/// The column's `+ New Task`. With [onQuickAdd] a tap turns it into a field:
/// type a title, Enter, and the card is in the column with the field still
/// open for the next — a board is where a list of things to do gets typed in
/// one go, and a full form per card is the wrong price for that. The full
/// form stays one tap away, beside the field. Without [onQuickAdd] the tap
/// opens the form directly.
class _CreateFooter extends StatefulWidget {
  const _CreateFooter({required this.onOpenForm, this.onQuickAdd});

  final VoidCallback onOpenForm;
  final Future<void> Function(String description)? onQuickAdd;

  @override
  State<_CreateFooter> createState() => _CreateFooterState();
}

class _CreateFooterState extends State<_CreateFooter> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Leaving an empty field puts the button back; leaving a typed one keeps
  /// it, so a stray click never throws a title away.
  void _onFocusChanged() {
    if (!_focus.hasFocus && _controller.text.trim().isEmpty && !_busy) {
      setState(() => _open = false);
    }
  }

  void _close() {
    _controller.clear();
    _focus.unfocus();
    setState(() => _open = false);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onQuickAdd!(text);
      if (!mounted) return;
      _controller.clear();
      _focus.requestFocus();
    } catch (e) {
      if (mounted) {
        Notify.error(context, context.tr('could_not_save'), error: e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    const corners = BorderRadius.vertical(bottom: Radius.circular(InRadii.r3));
    if (!_open) {
      return InkWell(
        onTap: widget.onQuickAdd == null
            ? widget.onOpenForm
            : () {
                setState(() => _open = true);
                _focus.requestFocus();
              },
        borderRadius: corners,
        child: Padding(
          padding: EdgeInsets.all(InSpacing.md(context)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 16, color: tokens.ink3),
              const SizedBox(width: 6),
              Text(
                context.tr('new_task'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tokens.ink3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final side = Env.isTouchPrimary ? 44.0 : 32.0;
    return Padding(
      padding: const EdgeInsets.all(InSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _close,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _submit(),
                // Keep focus (and the soft keyboard) up between creates.
                onEditingComplete: () {},
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.tr('new_task'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.open_in_full, size: 16, color: tokens.ink3),
            tooltip: context.tr('more_fields'),
            style: IconButton.styleFrom(
              fixedSize: Size(side, side),
              minimumSize: Size.zero,
              maximumSize: Size.infinite,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: widget.onOpenForm,
          ),
        ],
      ),
    );
  }
}

/// A column folded away: a strip showing its colour, count and (upright, down
/// its length) its name. Still a drop target — a card dropped on it joins the
/// bottom of that status — and a tap opens it again.
class KanbanCollapsedColumn extends StatelessWidget {
  const KanbanCollapsedColumn({
    super.key,
    required this.status,
    required this.count,
    required this.onExpand,
    this.onAcceptTask,
    this.compact = false,
  });

  /// The strip's width.
  static const double width = 44;

  final TaskStatus status;
  final int count;
  final VoidCallback onExpand;
  final ValueChanged<Task>? onAcceptTask;

  /// True in the lanes' header row, which has no height for the name.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final name = status.name.isEmpty
        ? context.tr('no_name_fallback')
        : status.name;
    final dot = taskStatusColors(
      context,
      name: status.name,
      color: status.color,
    ).fg;
    Widget strip(bool hovering) => Tooltip(
      message: '${context.tr('expand_column')}: $name',
      child: Material(
        color: hovering ? tokens.accentSoft : tokens.surfaceAlt,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: hovering ? tokens.accent : tokens.border),
          borderRadius: BorderRadius.circular(InRadii.r3),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 10),
                  Flexible(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final accept = onAcceptTask;
    if (accept == null) return strip(false);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.statusId != status.id,
      onAcceptWithDetails: (d) => accept(d.data),
      builder: (context, candidate, _) => strip(candidate.isNotEmpty),
    );
  }
}

/// A visible drag-handle icon that initiates a `LongPressDraggable<T>` on
/// hold. The handle itself is the only draggable region — wrap a tappable
/// parent around it and the parent's tap stays intact (gesture arena
/// hands the long-press to the draggable, the short-tap to the parent).
///
/// Shared between card and column-header drag so the affordance reads
/// consistently across the board.
class _DragHandle<T extends Object> extends StatelessWidget {
  const _DragHandle({
    required this.data,
    required this.feedback,
    required this.tokens,
    required this.tooltipKey,
  });

  final T data;

  /// The widget to render under the user's finger / cursor while
  /// dragging. The caller picks the size to match the source widget so
  /// the preview doesn't shrink.
  final Widget feedback;

  final InTheme tokens;
  final String tooltipKey;

  @override
  Widget build(BuildContext context) {
    final icon = MouseRegion(
      cursor: SystemMouseCursors.move,
      child: Tooltip(
        message: context.tr(tooltipKey),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.drag_indicator, size: 18, color: tokens.ink4),
        ),
      ),
    );
    return LongPressDraggable<T>(
      data: data,
      delay: _kDragStartDelay,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.85, child: feedback),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: icon),
      child: icon,
    );
  }
}

/// A column's title bar: color dot · name · count · total time · controls.
/// Public because the lanes layout draws one row of these above every lane.
class KanbanColumnHeader extends StatelessWidget {
  const KanbanColumnHeader({
    super.key,
    required this.status,
    required this.tasks,
    this.dragHandle,
    this.onToggleCollapse,
    this.onCreate,
  });

  final TaskStatus status;
  final List<Task> tasks;

  /// Optional drag handle rendered last. Null for read-only users (the
  /// column isn't draggable).
  final Widget? dragHandle;

  final VoidCallback? onToggleCollapse;

  /// A `+` in the header — the lanes layout's create, where a column has no
  /// footer of its own.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final dot = taskStatusColors(
      context,
      name: status.name,
      color: status.color,
    ).fg;
    final pad = InSpacing.md(context);
    final hasControls = onToggleCollapse != null || onCreate != null;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        pad,
        hasControls ? pad - 4 : pad,
        hasControls && dragHandle == null ? pad - 6 : pad,
        hasControls ? pad - 4 : pad,
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              // Never the raw id: a hashid means nothing to anyone.
              status.name.isEmpty
                  ? context.tr('no_name_fallback')
                  : status.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tasks.length.toString(),
            style: TextStyle(
              fontSize: 12,
              color: tokens.ink3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          KanbanTimeTotal(tasks: tasks),
          if (onCreate != null)
            _HeaderButton(
              icon: Icons.add,
              tooltip: context.tr('new_task'),
              onPressed: onCreate!,
            ),
          if (onToggleCollapse != null)
            _HeaderButton(
              icon: Icons.unfold_less,
              quarterTurns: 1,
              tooltip: context.tr('collapse_column'),
              onPressed: onToggleCollapse!,
            ),
          if (dragHandle != null) ...[const SizedBox(width: 2), dragHandle!],
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.quarterTurns = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final side = Env.isTouchPrimary ? 36.0 : 28.0;
    return IconButton(
      icon: RotatedBox(
        quarterTurns: quarterTurns,
        child: Icon(icon, size: 16, color: context.inTheme.ink3),
      ),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        fixedSize: Size(side, side),
        minimumSize: Size.zero,
        maximumSize: Size.infinite,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    );
  }
}

/// Time worked across a set of cards (a column, a lane) — what a status is worth, which on a
/// billing board is the question the count cannot answer. Nothing at all for
/// a column with no time on it. Re-reads once a minute while a card's timer
/// runs, the cadence the cards themselves tick at.
class KanbanTimeTotal extends StatefulWidget {
  const KanbanTimeTotal({super.key, required this.tasks});

  final List<Task> tasks;

  @override
  State<KanbanTimeTotal> createState() => _KanbanTimeTotalState();
}

class _KanbanTimeTotalState extends State<KanbanTimeTotal> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(KanbanTimeTotal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final running = widget.tasks.any((t) => t.isRunning);
    if (running == (_ticker != null)) return;
    _ticker?.cancel();
    _ticker = running
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final total = widget.tasks.fold(
      Duration.zero,
      (sum, t) => sum + t.loggedDuration(now),
    );
    if (total == Duration.zero) return const SizedBox.shrink();
    return Tooltip(
      message: context.tr('total_duration'),
      child: Text(
        formatDuration(
          total,
          compactDays: true,
          showSeconds: false,
          secondsPastDay: watchShowSeconds(context),
        ),
        style: TextStyle(
          fontSize: 12,
          color: context.inTheme.ink3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
