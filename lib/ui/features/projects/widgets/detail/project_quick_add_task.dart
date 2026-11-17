import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/domain/tasks/task_schedule.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;
import 'package:admin/ui/features/tasks/widgets/task_actions.dart';

/// Type a description, press Enter, get a task on this project
/// (invoiceninja/ui#3383). Built for rapid entry: focus stays in the field
/// after each create, Escape clears it, and there is no toast — the new task
/// appearing in the list right under the field is the feedback (an unsynced
/// create sorts first). The full form is the record's `+ Task` tile: the
/// embedded list drops its own New wherever this field is offered (one create
/// control per toolbar, `ProjectDetailTabs`).
///
/// **Start** beside it creates the task already running — one open time entry
/// planned by `planTaskStart` (the rule every start path follows,
/// `docs/task-scheduling.md`) and the company's In-progress status, the move
/// `TaskActions` makes when a task starts. The field may be empty for it: the
/// server takes a task with no description, and "start the clock, name it
/// later" is the case the button exists for.
///
/// It heads the project's **Tasks tab**. It used to sit in a Tasks card above
/// the tabs, over a second copy of the list the tab one scroll down already
/// showed.
class ProjectQuickAddTask extends StatefulWidget {
  const ProjectQuickAddTask({
    super.key,
    required this.project,
    required this.companyId,
  });

  final Project project;
  final String companyId;

  /// Whether the field is offered: only where a task could be created at all,
  /// and not on an archived, deleted or not-yet-synced project.
  static bool appliesTo(Project project, {required bool canCreateTask}) =>
      canCreateTask &&
      project.archivedAt == null &&
      !project.isDeleted &&
      !project.id.startsWith('tmp_');

  @override
  State<ProjectQuickAddTask> createState() => _ProjectQuickAddTaskState();
}

class _ProjectQuickAddTaskState extends State<ProjectQuickAddTask> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _create({bool start = false}) async {
    final description = _controller.text.trim();
    if ((description.isEmpty && !start) || _busy) return;
    final services = context.read<Services>();
    final p = widget.project;
    setState(() => _busy = true);
    try {
      var draft = emptyTask().copyWith(
        description: description,
        projectId: p.id,
        clientId: p.clientId,
        rate: p.taskRate,
      );
      // The company's In-progress status for a started task; otherwise — or
      // where the company has none this app recognises — its first status
      // (board order), never blank: a blank status puts the task in no kanban
      // column until the server assigns one — offline, never (see
      // `create_task_from_line_item_sheet.dart`).
      final inProgress = start
          ? await TaskActions.inProgressStatusId(
              context,
              services,
              widget.companyId,
              draft,
            )
          : null;
      final statuses = await services.taskStatuses
          .watchAll(companyId: widget.companyId)
          .first;
      final now = DateTime.now();
      draft = draft.copyWith(
        statusId: inProgress ?? (statuses.isEmpty ? '' : statuses.first.id),
        // Orders this create among other unsynced ones — see
        // `TaskDao.watchForProject`.
        updatedAt: now.toUtc(),
      );
      if (start) {
        // Through the planner like every other start path, never a hand-made
        // running entry. On an empty log it can only append.
        final plan = planTaskStart(draft.timeLog, now: now);
        if (plan.outcome != TaskStartOutcome.append) return;
        draft = draft.copyWith(timeLog: plan.entries);
      }
      await services.tasks.create(companyId: widget.companyId, draft: draft);
      if (!mounted) return;
      _controller.clear();
      // Rapid entry continues after Enter; after Start the user is off to
      // work, and a soft keyboard left up would cover the row that started.
      if (start) {
        _focus.unfocus();
      } else {
        _focus.requestFocus();
      }
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
    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _controller.clear();
          _focus.unfocus();
        },
      },
      child: TextField(
        key: const Key('project_quick_add_task'),
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _create(),
        // Keep focus (and the soft keyboard) up between creates.
        onEditingComplete: () {},
        decoration: InputDecoration(
          isDense: true,
          hintText: context.tr('new_task'),
          prefixIcon: Icon(Icons.add, size: 18, color: tokens.ink3),
          // The app's Enter glyph, on a keyboard-first device only — it says
          // "press Enter" to someone who has one.
          suffixIcon: Env.isTouchPrimary
              ? null
              : ExcludeSemantics(
                  child: Center(
                    widthFactor: 1,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: Opacity(
                        opacity: 0.5,
                        child: Text('↵', style: TextStyle(color: tokens.ink3)),
                      ),
                    ),
                  ),
                ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(child: field),
        SizedBox(width: InSpacing.md(context)),
        OutlinedButton.icon(
          key: const Key('project_quick_add_start'),
          // Disabled while a create is in flight: a second tap would start a
          // second running task.
          onPressed: _busy ? null : () => _create(start: true),
          // The app's one Start glyph (flutter#153), as on every task surface.
          icon: const Icon(Icons.play_circle_outlined, size: 18),
          label: Text(context.tr('start')),
          // In a Row the theme's infinite-width minimum would crash it. As
          // tall as the field beside it — 40 with a pointer, a touch target
          // on touch — so no density takes 8 off it.
          style: OutlinedButton.styleFrom(
            minimumSize: Size(64, Env.isTouchPrimary ? 48 : 40),
            visualDensity: VisualDensity.standard,
          ),
        ),
      ],
    );
  }
}
