import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/router.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/utils/show_seconds.dart';
import 'package:admin/ui/core/widgets/client_name_label.dart';
import 'package:admin/ui/features/tasks/widgets/inline_timer_toggle_button.dart';
import 'package:admin/ui/features/tasks/widgets/task_schedule_slot.dart';
import 'package:admin/ui/features/tasks/widgets/running_duration_label.dart';
import 'package:admin/ui/features/tasks/widgets/task_actions.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/list/master_detail_nav_scope.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/core/widgets/user_avatar.dart';
import 'package:admin/ui/features/projects/widgets/project_name_label.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:provider/provider.dart';

/// One card in a kanban column: the title, then who it is for (client,
/// project), then a footer of time · assignee · timer — each line present only
/// when it has something to say. Tapping opens the task; the column wraps the
/// whole card in its drag (`docs/tasks-views.md` § A kanban card).
class KanbanCard extends StatelessWidget {
  const KanbanCard({
    super.key,
    required this.task,
    required this.companyId,
    this.showTimerButton = true,
    this.fields,
    this.selected = false,
    this.moveTargets = const [],
    this.onMoveTo,
    this.showMenu = true,
  });

  /// The lines to draw; null is every field at its default.
  final Set<KanbanCardField>? fields;

  /// True for the task open in the pane beside the board.
  final bool selected;

  /// The other columns, and what a menu (or screen-reader) move to one of them
  /// calls. With no [onMoveTo] the card offers no moves.
  final List<TaskStatus> moveTargets;
  final ValueChanged<TaskStatus>? onMoveTo;

  /// False on the drag ghost.
  final bool showMenu;

  final Task task;

  /// Active company id for the inline timer toggle (threaded by value —
  /// see [KanbanColumn.companyId]).
  final String companyId;

  /// False on the drag-feedback ghost so an inert button doesn't ride along.
  final bool showTimerButton;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final identity = task.description.isEmpty
        ? (task.number.isEmpty ? '—' : '#${task.number}')
        : task.description;
    final running = task.isRunning && task.timeLog.isNotEmpty;
    final shown = fields ?? KanbanCardField.defaults;
    bool has(KanbanCardField f) => shown.contains(f);
    final moves = onMoveTo == null ? const <TaskStatus>[] : moveTargets;
    final metaStyle = TextStyle(fontSize: 12, color: tokens.ink3);
    final slot = running ? null : taskScheduleSlot(context, task);
    final seconds = watchShowSeconds(context);
    final logged = task.loggedDuration();
    // A task nobody has worked on or booked says nothing with `0:00`, so the
    // slot is left empty — a column of untouched cards read as a column of
    // zeros.
    final Widget? time = !has(KanbanCardField.time)
        ? null
        : running
        ? RunningDurationLabel(
            start: task.timeLog.last.start!,
            precision: const Duration(minutes: 1),
            secondsPastDay: true,
            dotSize: 6,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        // Same swap as the narrow list row: a booked-but-unstarted task shows
        // WHEN rather than a duration.
        : (slot == null && logged == Duration.zero)
        ? null
        : Text(
            slot?.text ??
                formatDuration(
                  logged,
                  compactDays: true,
                  showSeconds: seconds,
                  secondsPastDay: seconds,
                ),
            style: TextStyle(
              fontSize: 12,
              color: slot?.color ?? tokens.ink2,
              fontWeight: slot == null ? FontWeight.normal : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
    final timer = showTimerButton && TaskActions.canTimeTask(context, task);
    final menu = showMenu;
    final assigned =
        has(KanbanCardField.assignee) && task.assignedUserId.isNotEmpty;
    final pad = InSpacing.md(context);
    // The assignee and the timer sit in the card's bottom-end corner, BESIDE
    // the lines under the title rather than on a row of their own — a row
    // holding only a play button cost every untouched card a third of its
    // height. Those lines give up the corner's width; the title never does.
    final cornerWidth =
        (timer ? _timerTarget : 0.0) +
        (assigned ? _avatarSize + (timer ? 2 : pad) : 0.0);
    final hasCorner = cornerWidth > 0;
    final underTitle = [
      if (has(KanbanCardField.client) && task.clientId.isNotEmpty)
        _MetaLine(
          icon: Icons.person_outline,
          child: ClientNameLabel(clientId: task.clientId, style: metaStyle),
        ),
      // Its own line, never joined to the client: two names sharing one line
      // of a 300 px card are each cut to half (invoiceninja/app#195). The
      // icons are what tell them apart.
      if (has(KanbanCardField.project) && task.projectId.isNotEmpty)
        _MetaLine(
          icon: Icons.work_outline,
          child: ProjectNameLabel(projectId: task.projectId, style: metaStyle),
        ),
      ?time,
    ];
    final card = Material(
      color: selected ? tokens.accentSoft : tokens.surface,
      shape: RoundedRectangleBorder(
        // Running takes the accent; invoiced `tokens.paid`, so the two signals
        // stay apart. The open card takes it too, with a fill.
        side: BorderSide(
          color: running || selected
              ? tokens.accent
              : task.isInvoiced
              ? tokens.paid
              : tokens.border,
        ),
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A second tap on the open card closes its pane, as a list row's
        // does.
        onTap: selected
            ? () =>
                  MasterDetailNavScope.requestClose(context, basePath: '/tasks')
            : () => goEntityRecord(context, EntityType.task, task.id),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                pad,
                menu ? 6 : 10,
                menu ? 2 : pad,
                10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (has(KanbanCardField.number) &&
                      task.description.isNotEmpty &&
                      task.number.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: menu ? 4 : 0),
                      child: Text(
                        '#${task.number}',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.ink3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          // The menu button is taller than a line of title;
                          // this centres the first line on its glyph.
                          padding: EdgeInsets.only(
                            top: menu ? (_menuSize - 17) / 2 : 0,
                          ),
                          child: Text(
                            identity,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: tokens.ink,
                            ),
                          ),
                        ),
                      ),
                      if (task.isInvoiced) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.attach_money, size: 14, color: tokens.paid),
                      ],
                      if (menu) _CardMenu(card: this, moves: moves),
                    ],
                  ),
                  if (underTitle.isNotEmpty)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        // The menu button's box already leaves air under a
                        // one-line title.
                        top: menu ? 1 : 4,
                        // `pad` of it is already the card's own padding.
                        end: hasCorner
                            ? cornerWidth -
                                  (timer ? pad : 0) +
                                  (menu ? pad - 2 : 0)
                            : (menu ? pad - 2 : 0),
                      ),
                      child: ConstrainedBox(
                        // One line is shorter than the corner; hold the
                        // title clear of it.
                        constraints: BoxConstraints(
                          minHeight: hasCorner ? _cornerClearance : 0,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 2,
                          children: underTitle,
                        ),
                      ),
                    )
                  else if (hasCorner)
                    const SizedBox(height: _cornerClearance),
                ],
              ),
            ),
            if (hasCorner)
              PositionedDirectional(
                end: timer ? 2 : pad,
                bottom: timer ? 1 : 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (assigned)
                      UserAvatar(
                        userId: task.assignedUserId,
                        companyId: companyId,
                        size: _avatarSize,
                      ),
                    if (assigned && timer) const SizedBox(width: 2),
                    if (timer)
                      InlineTimerToggleButton(
                        task: task,
                        companyId: companyId,
                        iconSize: 18,
                        minTapTarget: _timerTarget,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (moves.isEmpty) return card;
    // Drag is the only way to move a card that a pointer can see, and a
    // screen reader cannot drag at all — so every move is an action too.
    return Semantics(
      customSemanticsActions: {
        for (final status in moves)
          CustomSemanticsAction(
            label: '${context.tr('move_to')} ${status.name}',
          ): () =>
              onMoveTo!(status),
      },
      child: card,
    );
  }

  /// The `⋮` button: 36 under a finger, like the timer beside it, 28 with a
  /// pointer.
  static double get _menuSize => Env.isTouchPrimary ? 36 : 28;

  static const double _timerTarget = 36;
  static const double _avatarSize = 20;

  /// Height under the title that keeps it clear of the corner's glyphs.
  static const double _cornerClearance = 20;
}

/// One muted `icon · name` line under a card's title.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Row(
      children: [
        Icon(icon, size: 13, color: tokens.ink4),
        const SizedBox(width: 5),
        Expanded(child: child),
      ],
    );
  }
}

/// The card's `⋮`: where it can go (`Move to`), then everything the task's
/// own actions menu offers. Also opens on a secondary click anywhere on the
/// card's title row.
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.card, required this.moves});

  final KanbanCard card;
  final List<TaskStatus> moves;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final services = context.read<Services>();
    final task = card.task;
    final side = KanbanCard._menuSize;
    return BackDismissibleMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        if (moves.isNotEmpty)
          SubmenuButton(
            leadingIcon: const Icon(Icons.drive_file_move_outline, size: 18),
            menuChildren: [
              for (final status in moves)
                MenuItemButton(
                  onPressed: () => card.onMoveTo!(status),
                  child: Text(status.name),
                ),
            ],
            child: Text(context.tr('move_to')),
          ),
        ...EntityActionItem.menuChildrenFor<TaskAction>(
          context,
          TaskActions.itemsFor(
            context,
            task,
            (action) => TaskActions.dispatch(
              context,
              services,
              card.companyId,
              task,
              action,
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: Icon(Icons.more_vert, size: 18, color: tokens.ink4),
        tooltip: context.tr('actions'),
        style: IconButton.styleFrom(
          fixedSize: Size(side, side),
          minimumSize: Size.zero,
          maximumSize: Size.infinite,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
