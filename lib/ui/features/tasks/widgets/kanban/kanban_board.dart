import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/session_permissions.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';
import 'package:admin/ui/features/tasks/view_models/kanban_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_column.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:admin/app/router.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/list/master_detail_nav_scope.dart';
import 'package:admin/ui/core/widgets/client_name_label.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/features/projects/widgets/project_name_label.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_card.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_card_slot.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_drag_scroller.dart';

/// The horizontal board: one column per [TaskStatus], cards inside drag
/// between columns. Reads [KanbanViewModel] off the ambient `Provider`.
///
/// Drop semantics:
///   * Drop a [Task] on a column → that task's `status_id` becomes the
///     column's id; the column's `task_ids` array appends the task at
///     the bottom.
///   * Drop a [Task] on another card → that task lands above the target
///     card in the same column.
///   * Within-column moves are detected by `task.statusId == target.id`.
///
/// The board only ever calls `commitReorder` once per drop, with the
/// **entire** board layout — so changes that span columns write to both
/// the source and target columns transactionally.
/// Widest a kanban column gets. On a phone it narrows to the viewport so the
/// next column always shows its edge — see [KanbanBoard].
const double kKanbanColumnWidth = 320;

/// Inner card width — the column's content area after its inner padding
/// (`InSpacing.sm * 2`). Used by the column-header drag feedback so the
/// floating preview matches the resting header's footprint.
const double kKanbanCardWidth = kKanbanColumnWidth - InSpacing.sm * 2;

/// The board: one column per [TaskStatus], or — grouped — one lane per client
/// / project / assignee crossing those columns. Reads [KanbanViewModel] off
/// the ambient `Provider`; how it is drawn comes in as [prefs].
class KanbanBoard extends StatefulWidget {
  const KanbanBoard({
    super.key,
    this.prefs = const KanbanPrefs(),
    this.onPrefsChanged,
  });

  final KanbanPrefs prefs;

  /// Null leaves the columns un-collapsible.
  final ValueChanged<KanbanPrefs>? onPrefsChanged;

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

/// One column as the board lays it out.
class _Col {
  const _Col(this.status, this.tasks, {this.collapsed = false});

  final TaskStatus status;
  final List<Task> tasks;
  final bool collapsed;

  /// The leading column of tasks on no status: no drops, no create, no fold.
  bool get isNoStatus => status.id == KanbanViewModel.noStatusId;
}

class _KanbanBoardState extends State<KanbanBoard> {
  static const double _columnGap = 12;

  /// How much of the next column a phone keeps in view, so the board reads as
  /// something that scrolls sideways.
  static const double _phonePeek = 28;

  final ScrollController _scroll = ScrollController();
  final ScrollController _lanesScroll = ScrollController();
  final GlobalKey _lanesKey = GlobalKey();
  final KanbanDragScroller _scroller = KanbanDragScroller();

  /// Lanes folded shut where there is nowhere to save the choice (no
  /// `onPrefsChanged`); otherwise it lives in [KanbanPrefs.closedLanes].
  final Set<String> _closedLanes = {};

  bool _laneClosed(String key) =>
      widget.prefs.isLaneClosed(key) || _closedLanes.contains(key);

  void _toggleLane(String key) {
    final save = widget.onPrefsChanged;
    if (save != null) return save(widget.prefs.toggleLane(key));
    setState(
      () => _closedLanes.contains(key)
          ? _closedLanes.remove(key)
          : _closedLanes.add(key),
    );
  }

  /// Where each column starts while the board snaps (a phone), else null.
  List<double>? _snapStops;
  DateTime _lastHop = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _hopInterval = Duration(milliseconds: 700);

  /// Names of whatever the lanes group by, for SORTING them — the titles
  /// resolve on their own, through the name labels. Watched rather than read
  /// once: a lane order that never noticed a rename would be a second copy of
  /// state Drift owns.
  Map<String, String> _laneNames = const {};
  StreamSubscription<Map<String, String>>? _laneNamesSub;

  @override
  void initState() {
    super.initState();
    _scroller.addListener(_onDragTick);
    _watchLaneNames();
  }

  @override
  void didUpdateWidget(KanbanBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs.groupBy != widget.prefs.groupBy) _watchLaneNames();
  }

  void _watchLaneNames() {
    _laneNamesSub?.cancel();
    _laneNamesSub = null;
    _laneNames = const {};
    final services = context.read<Services>();
    final companyId = context.read<KanbanViewModel>().companyId;
    final Stream<Map<String, String>>? names = switch (widget.prefs.groupBy) {
      KanbanGroupBy.none => null,
      KanbanGroupBy.client =>
        services.clients
            .watchAllNames(companyId: companyId)
            .map((rows) => {for (final r in rows) r.id: r.name}),
      KanbanGroupBy.project =>
        services.projects
            .watchAllNames(companyId: companyId)
            .map((rows) => {for (final r in rows) r.id: r.name}),
      KanbanGroupBy.assignee =>
        services.user
            .watchAllForPicker(companyId: companyId)
            .map((rows) => {for (final u in rows) u.id: u.displayName}),
    };
    _laneNamesSub = names?.listen((next) {
      if (mounted) setState(() => _laneNames = next);
    });
  }

  @override
  void dispose() {
    _laneNamesSub?.cancel();
    _scroller.dispose();
    _scroll.dispose();
    _lanesScroll.dispose();
    super.dispose();
  }

  /// One tick of a card drag: scroll the board sideways when the pointer is
  /// in a side band, and the lanes up or down when it is near their top or
  /// bottom. (A column scrolls itself — it listens to the same scroller.)
  void _onDragTick() {
    _scroller.scroll(
      _lanesScroll,
      _lanesKey.currentContext?.findRenderObject(),
    );
    final at = _scroller.position;
    final box = context.findRenderObject();
    if (at == null || box is! RenderBox || !box.hasSize) return;
    if (!_scroll.hasClients) return;
    var v = KanbanDragScroller.edgeVelocity(
      box.globalToLocal(at).dx,
      box.size.width,
    );
    if (v == 0) return;
    // The list's offset grows towards the END edge, which in a right-to-left
    // locale is the physical left.
    if (Directionality.of(context) == TextDirection.rtl) v = -v;
    final p = _scroll.position;
    final stops = _snapStops;
    if (stops == null) {
      final next = (p.pixels + v * KanbanDragScroller.step).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      if (next != p.pixels) _scroll.jumpTo(next);
      return;
    }
    // A snapping board would pull every small step back to its boundary, so
    // it turns one whole column at a time, pausing on each long enough to
    // drop there.
    final now = DateTime.now();
    if (now.difference(_lastHop) < _hopInterval) return;
    final target = _ColumnSnapPhysics.neighbour(
      stops,
      p.pixels,
      v.sign,
    ).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (target == p.pixels) return;
    _lastHop = now;
    unawaited(
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  void _toggleCollapsed(String statusId) =>
      widget.onPrefsChanged?.call(widget.prefs.toggleCollapsed(statusId));

  void _create(BuildContext context, TaskStatus status) =>
      goEntityCreateFullWidth(
        context,
        '/tasks',
        extra: emptyTask().copyWith(statusId: status.id),
      );

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<KanbanViewModel>();

    if (vm.isResolving && vm.statuses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.statuses.isEmpty) {
      // Surface the "Create a status" CTA inline so users discover the
      // settings screen from the kanban itself. Admins only: the server's
      // `StoreTaskStatusRequest` asks `isAdmin()`, and the router bounces
      // anyone else's `/new` back to the list.
      final mayCreate = sessionMayCreate(context, EntityType.taskStatus);
      return EmptyState(
        icon: Icons.label_outline,
        title: context.tr('no_task_statuses'),
        subtitle: context.tr('no_task_statuses_hint'),
        action: !mayCreate
            ? null
            : FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                icon: const Icon(Icons.add),
                label: Text(context.tr('new_task_status')),
                onPressed: () => context.go('/settings/task_statuses/new'),
              ),
      );
    }

    final me = context.read<Services>().auth.session.value?.currentCompany;
    final canEdit = me?.can('edit_task') ?? false;
    // A separate token, deliberately. `can()` grants `edit ⇒ view` and
    // `delete ⇒ edit` but never `edit ⇒ create`, so an edit-only user really
    // cannot create — and `create_task` is both what the server authorizes a
    // create against and what React's `Kanban.tsx` gates its own per-column
    // `+` on. Never folded with a filter: with no FAB
    // (invoiceninja/flutter#135) this is the board's only create path.
    final canCreate = me?.can('create_task') ?? false;

    final prefs = widget.prefs;
    final orphans = vm.tasksFor(KanbanViewModel.noStatusId);
    final cols = [
      // Only while it holds something: an always-empty leading column would
      // read as a status nobody can drop into.
      if (orphans.isNotEmpty)
        _Col(
          TaskStatus(
            id: KanbanViewModel.noStatusId,
            name: context.tr('no_status'),
            color: '',
            statusOrder: -1,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            archivedAt: null,
            isDeleted: false,
          ),
          orphans,
        ),
      for (final s in vm.statuses)
        _Col(
          s,
          vm.tasksFor(s.id),
          collapsed:
              widget.onPrefsChanged != null &&
              prefs.collapsedStatusIds.contains(s.id),
        ),
    ];

    // The board is the list behind an open task pane, so it owes the pane
    // what a list owes it: the visible ids in order (J / K step through them)
    // and the objects (the pane seeds its first frame from the card clicked).
    final selectedId = selectedIdFromRoute(context);
    final all = [for (final c in cols) ...c.tasks];
    MasterDetailNavScope.maybeOf(context)?.update(
      selectedId: selectedId,
      itemIds: [for (final t in all) t.id],
      items: all,
    );

    Widget card(BuildContext context, Task t, {required bool ghost}) =>
        KanbanCard(
          task: t,
          companyId: vm.companyId,
          fields: prefs.fields,
          selected: !ghost && t.id == selectedId,
          showTimerButton: !ghost,
          showMenu: !ghost,
          moveTargets: [
            for (final s in vm.statuses)
              if (s.id != t.statusId) s,
          ],
          // A menu move has no position to point at, so it lands on top —
          // where the user will see it arrive.
          onMoveTo: canEdit
              ? (s) => vm.moveTask(t, toStatusId: s.id, toTop: true)
              : null,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = Breakpoints.isPhone(context);
        // Wide: 24 to match `EntityListScreenScaffold`'s table-card padding,
        // so the first column sits under the same edge as the list it swaps
        // with. It is the SCROLLABLE's padding, not a box around it, so
        // columns scroll out under the pane's edge rather than being cut 24 px
        // short of it.
        final side = phone ? InSpacing.lg(context) : 24.0;
        // A phone shows one column and the edge of the next, and settles on a
        // column boundary: a board left resting between two columns shows
        // neither.
        final columnWidth = phone
            ? math.min(
                kKanbanColumnWidth,
                constraints.maxWidth - side - _columnGap - _phonePeek,
              )
            : kKanbanColumnWidth;
        // A phone comes to rest with a column at the viewport's start, so the
        // stops are where each column begins — not a fixed stride, because a
        // folded column is a 44 px strip.
        List<double>? stops;
        if (phone) {
          stops = [];
          var at = 0.0;
          for (final c in cols) {
            stops.add(at);
            at +=
                (c.collapsed ? KanbanCollapsedColumn.width : columnWidth) +
                _columnGap;
          }
        }
        _snapStops = stops;
        final physics = stops == null ? null : _ColumnSnapPhysics(stops: stops);
        final padding = EdgeInsetsDirectional.symmetric(
          horizontal: side,
          vertical: InSpacing.md(context),
        );

        if (prefs.groupBy != KanbanGroupBy.none) {
          return _lanes(
            context,
            vm: vm,
            cols: cols,
            card: card,
            canEdit: canEdit,
            canCreate: canCreate,
            columnWidth: columnWidth,
            viewport: constraints.maxWidth,
            side: side,
            padding: padding,
            physics: physics,
          );
        }

        // lint: allow-keep-alives a column scrolled away mid-drag must not lose its drag or scroll
        return ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: physics,
          padding: padding,
          itemCount: cols.length,
          separatorBuilder: (_, _) => const SizedBox(width: _columnGap),
          itemBuilder: (context, i) {
            final col = cols[i];
            final status = col.status;
            if (col.collapsed) {
              return SizedBox(
                width: KanbanCollapsedColumn.width,
                child: KanbanCollapsedColumn(
                  status: status,
                  count: col.tasks.length,
                  onExpand: () => _toggleCollapsed(status.id),
                  onAcceptTask: canEdit
                      ? (task) => vm.moveTask(task, toStatusId: status.id)
                      : null,
                ),
              );
            }
            return SizedBox(
              width: columnWidth,
              child: KanbanColumn(
                status: status,
                tasks: col.tasks,
                companyId: vm.companyId,
                canEdit: canEdit,
                canCreate: canCreate && !col.isNoStatus,
                scroller: _scroller,
                cardBuilder: card,
                onQuickAdd: (text) =>
                    vm.quickAdd(statusId: status.id, description: text),
                onToggleCollapse:
                    col.isNoStatus || widget.onPrefsChanged == null
                    ? null
                    : () => _toggleCollapsed(status.id),
                onAcceptTask: col.isNoStatus
                    ? null
                    : (task, beforeTaskId) => vm.moveTask(
                        task,
                        toStatusId: status.id,
                        beforeTaskId: beforeTaskId,
                      ),
                onAcceptStatus: col.isNoStatus
                    ? null
                    : (dropped) => _onAcceptStatus(vm, status, dropped),
              ),
            );
          },
        );
      },
    );
  }

  /// Drop a column on top of another column → reorder the status set so
  /// the dropped status lands at the target column's current position.
  /// Calls [KanbanViewModel.commitStatusReorder] with the new id list.
  void _onAcceptStatus(
    KanbanViewModel vm,
    TaskStatus targetStatus,
    TaskStatus droppedStatus,
  ) {
    if (droppedStatus.id == targetStatus.id) return;
    final ordered = vm.statuses.map((s) => s.id).toList(growable: true)
      ..removeWhere((id) => id == droppedStatus.id);
    final targetIndex = ordered.indexWhere((id) => id == targetStatus.id);
    if (targetIndex < 0) {
      ordered.add(droppedStatus.id);
    } else {
      ordered.insert(targetIndex, droppedStatus.id);
    }
    vm.commitStatusReorder(ordered);
  }

  // ---------------------------------------------------------------- lanes

  /// What a task is grouped under: the id of its client / project / assignee,
  /// or '' for none.
  String _laneKey(Task t) => switch (widget.prefs.groupBy) {
    KanbanGroupBy.client => t.clientId,
    KanbanGroupBy.project => t.projectId,
    KanbanGroupBy.assignee => t.assignedUserId,
    KanbanGroupBy.none => '',
  };

  Widget _laneTitle(BuildContext context, String key) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: context.inTheme.ink,
    );
    final groupBy = widget.prefs.groupBy;
    if (key.isEmpty) {
      return Text(
        context.tr(switch (groupBy) {
          KanbanGroupBy.client => 'no_client',
          KanbanGroupBy.project => 'no_project',
          _ => 'unassigned',
        }),
        style: style,
      );
    }
    return switch (groupBy) {
      KanbanGroupBy.client => ClientNameLabel(clientId: key, style: style),
      KanbanGroupBy.project => ProjectNameLabel(projectId: key, style: style),
      _ => UserNameLabel(userId: key, style: style),
    };
  }

  /// The grouped layout: one row of column headers, then a lane per group,
  /// each lane a row of cells under those headers. The whole of it scrolls
  /// sideways as one sheet, the lanes up and down beneath the fixed headers.
  ///
  /// A card moves between columns inside its own lane only. Dropping it in
  /// another lane would have to rewrite its client / project / assignee, and a
  /// status board is the wrong place to do that by accident.
  Widget _lanes(
    BuildContext context, {
    required KanbanViewModel vm,
    required List<_Col> cols,
    required KanbanCardBuilder card,
    required bool canEdit,
    required bool canCreate,
    required double columnWidth,
    required double viewport,
    required double side,
    required EdgeInsetsGeometry padding,
    required ScrollPhysics? physics,
  }) {
    final tokens = context.inTheme;
    double widthOf(_Col c) =>
        c.collapsed ? KanbanCollapsedColumn.width : columnWidth;
    final sheet =
        cols.fold<double>(0, (sum, c) => sum + widthOf(c)) +
        _columnGap * (cols.length - 1);

    final keys = {
      for (final c in cols)
        for (final t in c.tasks) _laneKey(t),
    }.toList();
    // Until the names arrive (or for a record the roster no longer holds) a
    // lane sorts by its id: stable, which is what matters while it lasts.
    final sortNames = {
      for (final k in keys) k: (_laneNames[k] ?? k).toLowerCase(),
    };
    // Named lanes by name; the "none" lane last.
    keys.sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      final byName = sortNames[a]!.compareTo(sortNames[b]!);
      return byName != 0 ? byName : a.compareTo(b);
    });

    Widget row(List<Widget> cells) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: _columnGap,
      children: cells,
    );

    final headers = row([
      for (final c in cols)
        SizedBox(
          width: widthOf(c),
          child: c.collapsed
              ? KanbanCollapsedColumn(
                  status: c.status,
                  count: c.tasks.length,
                  compact: true,
                  onExpand: () => _toggleCollapsed(c.status.id),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surfaceAlt,
                    border: Border.all(color: tokens.border),
                    borderRadius: BorderRadius.circular(InRadii.r3),
                  ),
                  child: KanbanColumnHeader(
                    status: c.status,
                    tasks: c.tasks,
                    onCreate: canCreate && !c.isNoStatus
                        ? () => _create(context, c.status)
                        : null,
                    onToggleCollapse:
                        c.isNoStatus || widget.onPrefsChanged == null
                        ? null
                        : () => _toggleCollapsed(c.status.id),
                  ),
                ),
        ),
    ]);

    Widget lane(String key) {
      final closed = _laneClosed(key);
      final inLane = [
        for (final c in cols) c.tasks.where((t) => _laneKey(t) == key).toList(),
      ];
      final laneTasks = [for (final l in inLane) ...l];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The lane's name stays at the viewport's start edge while the
          // sheet scrolls sideways under it — off screen it would leave a
          // phone's second column with no idea whose cards it was showing.
          _PinnedStart(
            scroll: _scroll,
            width: math.max(0, viewport - side * 2),
            max: math.max(0, sheet - (viewport - side * 2)),
            child: InkWell(
              borderRadius: BorderRadius.circular(InRadii.r1),
              onTap: () => _toggleLane(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      closed ? Icons.chevron_right : Icons.expand_more,
                      size: 18,
                      color: tokens.ink3,
                      semanticLabel: context.tr(closed ? 'expand' : 'collapse'),
                    ),
                    const SizedBox(width: 4),
                    Flexible(child: _laneTitle(context, key)),
                    const SizedBox(width: 8),
                    Text(
                      '${laneTasks.length}',
                      style: TextStyle(fontSize: 12, color: tokens.ink3),
                    ),
                    const SizedBox(width: 12),
                    KanbanTimeTotal(tasks: laneTasks),
                  ],
                ),
              ),
            ),
          ),
          if (!closed)
            row([
              for (var i = 0; i < cols.length; i++)
                SizedBox(
                  width: widthOf(cols[i]),
                  child: _LaneCell(
                    col: cols[i],
                    tasks: inLane[i],
                    card: card,
                    cardWidth: columnWidth - InSpacing.sm * 2,
                    canEdit: canEdit,
                    scroller: _scroller,
                    accepts: (t) => _laneKey(t) == key,
                    onDrop: (task, before) => vm.moveTask(
                      task,
                      toStatusId: cols[i].status.id,
                      beforeTaskId: before,
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: 8),
        ],
      );
    }

    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: physics,
      padding: padding,
      child: SizedBox(
        width: sheet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headers,
            const SizedBox(height: 4),
            Expanded(
              // lint: allow-keep-alives a lane scrolled away mid-drag must not lose its drag or scroll
              child: ListView.builder(
                key: _lanesKey,
                controller: _lanesScroll,
                itemCount: keys.length,
                itemBuilder: (context, i) => lane(keys[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds [child] at the start edge of the viewport while the sheet it sits in
/// scrolls sideways by [scroll], for as far as [max].
class _PinnedStart extends StatelessWidget {
  const _PinnedStart({
    required this.scroll,
    required this.width,
    required this.max,
    required this.child,
  });

  final ScrollController scroll;
  final double width;
  final double max;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final dx = scroll.hasClients
            ? scroll.offset.clamp(0.0, max).toDouble()
            : 0.0;
        return Transform.translate(
          offset: Offset(rtl ? -dx : dx, 0),
          child: child,
        );
      },
      child: SizedBox(width: width, child: child),
    );
  }
}

/// One lane × column cell: that lane's cards on that status, and the drop
/// target for the lane's own cards.
class _LaneCell extends StatelessWidget {
  const _LaneCell({
    required this.col,
    required this.tasks,
    required this.card,
    required this.cardWidth,
    required this.canEdit,
    required this.scroller,
    required this.accepts,
    required this.onDrop,
  });

  final _Col col;
  final List<Task> tasks;
  final KanbanCardBuilder card;
  final double cardWidth;
  final bool canEdit;
  final KanbanDragScroller scroller;
  final bool Function(Task) accepts;
  final void Function(Task task, String? beforeTaskId) onDrop;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final droppable = canEdit && !col.isNoStatus;
    Widget cell(bool hovering) => Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: col.collapsed
          ? const EdgeInsets.symmetric(vertical: 14)
          : const EdgeInsetsDirectional.fromSTEB(
              InSpacing.sm,
              InSpacing.sm,
              InSpacing.sm,
              0,
            ),
      // An empty cell is only a place to drop: drawn, a lane of them reads as
      // a grid of blank cards.
      decoration: BoxDecoration(
        color: hovering
            ? tokens.accentSoft
            : tasks.isEmpty
            ? null
            : tokens.surfaceAlt,
        border: Border.all(
          color: hovering
              ? tokens.accent
              : tasks.isEmpty
              ? Colors.transparent
              : tokens.border,
        ),
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      child: col.collapsed
          ? Center(
              child: Text(
                tasks.isEmpty ? '' : '${tasks.length}',
                style: TextStyle(fontSize: 12, color: tokens.ink3),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in tasks)
                  KanbanCardSlot(
                    task: t,
                    card: card(context, t, ghost: false),
                    ghost: card(context, t, ghost: true),
                    width: cardWidth,
                    canDrag: canEdit,
                    scroller: scroller,
                    accepts: accepts,
                    onDropAbove: droppable
                        ? (dropped) => onDrop(dropped, t.id)
                        : null,
                  ),
              ],
            ),
    );
    if (!droppable) return cell(false);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data, null),
      // Only an empty cell lights up: over a card, the bar above that card is
      // the indicator.
      builder: (context, candidate, _) =>
          cell(candidate.isNotEmpty && tasks.isEmpty),
    );
  }
}

/// Settles a horizontal board with a column at the viewport's start (phones
/// only). `PageScrollPhysics` with the pages being the columns' own start
/// offsets — a column is narrower than the screen so that the next one shows,
/// and a folded one narrower still.
class _ColumnSnapPhysics extends ScrollPhysics {
  const _ColumnSnapPhysics({required this.stops, super.parent});

  /// Ascending scroll offsets the board may rest at.
  final List<double> stops;

  @override
  _ColumnSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _ColumnSnapPhysics(stops: stops, parent: buildParent(ancestor));

  /// The stop nearest [pixels].
  static double nearest(List<double> stops, double pixels) {
    var best = stops.first;
    for (final s in stops) {
      if ((s - pixels).abs() < (best - pixels).abs()) best = s;
    }
    return best;
  }

  /// The stop after ([direction] > 0) or before the one nearest [pixels].
  static double neighbour(List<double> stops, double pixels, double direction) {
    final i = stops.indexOf(nearest(stops, pixels));
    final next = (i + (direction > 0 ? 1 : -1)).clamp(0, stops.length - 1);
    return stops[next];
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range: let the parent bring it back.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent) ||
        stops.isEmpty) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    // A fling goes to the next stop in its direction; a release with no
    // speed goes to whichever is nearer.
    final double goal;
    if (velocity.abs() <= tolerance.velocity) {
      goal = nearest(stops, position.pixels);
    } else {
      final ahead = velocity > 0
          ? stops.where((s) => s > position.pixels + tolerance.distance)
          : stops.reversed.where(
              (s) => s < position.pixels - tolerance.distance,
            );
      goal = ahead.isEmpty ? nearest(stops, position.pixels) : ahead.first;
    }
    final target = goal.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
