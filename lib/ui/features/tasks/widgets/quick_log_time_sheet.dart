import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/router.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/tasks/quick_log.dart';
import 'package:admin/domain/tasks/task_day.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/widgets/client_picker_field.dart';
import 'package:admin/ui/core/widgets/entity_picker_field.dart';
import 'package:admin/ui/core/widgets/example_hint.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/in_date_field.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;
import 'package:admin/ui/features/tasks/widgets/time_log_problem_message.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/utils/notes_html.dart';

/// The Tasks views' **Log time** — add a block of worked time to an existing
/// task, or to a new one, without leaving the daily / weekly view.
///
/// It used to open the full new-task editor with a 30-minute entry, so time
/// could only ever be logged against a *new* task (user report, Nov 2026).
/// Every mainstream timesheet (Harvest, Clockify, Toggl) and React's
/// `QuickLogTimeModal` instead use one small form: pick a task (or type a new
/// one), enter a duration, save. This is that form, with the task field the
/// React modal lacks.
///
/// * **Task** empty means "a new task", which is why its hint reads New Task.
///   Picking one hides the new-task fields (description, client, project).
/// * **Duration** starts empty and is required — a pre-filled 30 minutes was a
///   believable but wrong entry for anyone who pressed Save without looking.
/// * Where the block lands on the day is `appendQuickLogEntry`'s decision.
/// * The save goes through the outbox (`create` / `save`), so it works offline.
/// * **Edit** hands the same draft to the full editor for anything else.
Future<void> showQuickLogTimeSheet(
  BuildContext context, {
  required String companyId,
  required Date day,
}) {
  final body = _QuickLogTimeSheet(
    companyId: companyId,
    day: day,
    hostContext: context,
  );
  // Same responsive split as `showCreateTaskFromLineItemSheet`.
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<void>(
      context: context,
      anchorPoint: foldAnchorPoint(context),
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: body,
    ),
  );
}

/// The picker's label for a task: its description, then its number.
String quickLogTaskLabel(Task t) {
  final label = taskPrimaryLabel(t, max: 80);
  if (t.number.isEmpty || label == '#${t.number}') return label;
  return '$label · #${t.number}';
}

class _QuickLogTimeSheet extends StatefulWidget {
  const _QuickLogTimeSheet({
    required this.companyId,
    required this.day,
    required this.hostContext,
  });

  final String companyId;
  final Date day;

  /// The Tasks view's context. It stays mounted after the sheet closes, so it
  /// drives the toast's Open action and the Edit hand-off.
  final BuildContext hostContext;

  @override
  State<_QuickLogTimeSheet> createState() => _QuickLogTimeSheetState();
}

class _QuickLogTimeSheetState extends State<_QuickLogTimeSheet> {
  late final Services _services = context.read<Services>();
  late final Formatter? _formatter = _services.formatterIfReady(
    widget.companyId,
  );
  late final Stream<Company?> _company = _services.company.watchCompany(
    widget.companyId,
  );

  late Date _day = widget.day;
  final TextEditingController _description = TextEditingController();
  final TextEditingController _durationText = TextEditingController();
  Duration? _duration;
  bool _durationInvalid = false;
  bool _billable = true;
  bool _busy = false;

  /// Empty means a new task.
  String _taskId = '';
  Task? _task;
  String _clientId = '';
  String _projectId = '';

  /// Why the last save was refused (a time-log overlap, say), shown above the
  /// buttons until the user changes something.
  String? _error;

  /// Seeded once from the company's first status, as the line-item sheet does
  /// (`create_task_from_line_item_sheet.dart` explains why: a blank status
  /// leaves a new task in no kanban column until the server round trip).
  String _statusId = '';
  StreamSubscription<List<TaskStatus>>? _statusSeed;

  bool get _canCreate =>
      _services.auth.session.value?.currentCompany?.can('create_task') ?? false;

  bool get _isNew => _taskId.isEmpty;

  @override
  void initState() {
    super.initState();
    _statusSeed = _services.taskStatuses
        .watchAll(companyId: widget.companyId)
        .listen((statuses) {
          if (!mounted || statuses.isEmpty) return;
          _statusSeed?.cancel();
          _statusSeed = null;
          _statusId = statuses.first.id;
        }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _statusSeed?.cancel();
    _description.dispose();
    _durationText.dispose();
    super.dispose();
  }

  bool get _useComma => _formatter?.settings.useCommaAsDecimalPlace ?? false;

  bool _canEdit(Task t) =>
      _services.auth.session.value?.canEditRecord(
        'task',
        createdBy: t.userId,
        assignedTo: t.assignedUserId,
        recordId: t.id,
      ) ??
      false;

  void _onDurationChanged(String raw) {
    final parsed = parseDurationInput(
      _useComma ? raw : raw.replaceAll(',', '.'),
    );
    setState(() {
      _error = null;
      _duration = parsed == null || parsed <= Duration.zero ? null : parsed;
      // Flag only once there is something to judge — never an empty field.
      _durationInvalid = raw.trim().isNotEmpty && _duration == null;
    });
  }

  void _applyDurationPreset(int minutes) {
    final next = Duration(minutes: minutes);
    _durationText.text = formatDuration(next, showSeconds: false);
    setState(() {
      _error = null;
      _duration = next;
      _durationInvalid = false;
    });
  }

  bool get _taskBlocked {
    final t = _task;
    return t != null && (t.isRunning || t.isInvoiced);
  }

  bool get _canSave =>
      !_busy &&
      _duration != null &&
      !_taskBlocked &&
      (_isNew ? _canCreate : true);

  Task _newTaskDraft({List<TimeEntry> timeLog = const []}) =>
      emptyTask().copyWith(
        description: htmlFromPlainText(_description.text.trim()),
        clientId: _clientId,
        // A project always belongs to a client; sending one without the other
        // 422s, so the project picker sets the client too.
        projectId: _clientId.isEmpty ? '' : _projectId,
        statusId: _statusId,
        timeLog: timeLog,
      );

  /// The block for a new task: its log is empty, so the placement can't fail.
  List<TimeEntry> _newTaskLog(Duration duration) =>
      appendQuickLogEntry(
        log: const [],
        day: _day,
        duration: duration,
        now: DateTime.now(),
        billable: _billable,
      ).log ??
      const [];

  /// The task as stored now — never the picker's copy, which can be a frame
  /// behind a timer started or an entry added elsewhere.
  Future<Task?> _freshTask() => _services.tasks
      .watch(companyId: widget.companyId, id: _taskId)
      .first
      .timeout(const Duration(seconds: 5), onTimeout: () => _task);

  Future<void> _save() async {
    final duration = _duration;
    if (!_canSave || duration == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final String savedId;
    try {
      if (_isNew) {
        final result = await _services.tasks.create(
          companyId: widget.companyId,
          draft: _newTaskDraft(timeLog: _newTaskLog(duration)),
        );
        savedId = result.entity.id;
      } else {
        final task = await _freshTask();
        if (!mounted) return;
        if (task == null || task.isRunning || task.isInvoiced) {
          setState(() {
            _busy = false;
            _error = context.tr('stop_task_to_add_task_entry');
          });
          return;
        }
        final placed = appendQuickLogEntry(
          log: task.timeLog,
          day: _day,
          duration: duration,
          now: DateTime.now(),
          billable: _billable,
        );
        final log = placed.log;
        if (log == null) {
          setState(() {
            _busy = false;
            _error = placed.problem == null
                ? context.tr('please_enter_a_valid_duration')
                : timeLogProblemMessage(
                    context,
                    placed.problem!,
                    formatter: _formatter,
                  );
          });
          return;
        }
        await _services.tasks.save(
          companyId: widget.companyId,
          task: task.copyWith(timeLog: log),
        );
        savedId = task.id;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      Notify.error(context, context.tr('error'), error: error);
      return;
    }
    // Outside the try: the write is queued, so nothing after it may re-arm
    // Save and invite a duplicate. The sheet may also have been dismissed
    // mid-save, and popping then would pop the Tasks view underneath it.
    if (!mounted) return;
    final host = widget.hostContext;
    final logged = formatDuration(duration, showSeconds: false);
    final day = _formatter?.date(_day.toIso()) ?? '';
    Notify.success(
      context,
      _isNew ? context.tr('created_task') : context.tr('updated_task'),
      detail: day.isEmpty ? logged : '$logged · $day',
      action: NotifyAction(context.tr('open'), () {
        if (host.mounted) goEntityFullDetail(host, '/tasks', savedId);
      }),
    );
    navigator.pop();
  }

  /// Hand the same draft to the full editor — client, project, rate, custom
  /// fields and the entry's exact times all live there.
  Future<void> _openEditor() async {
    final host = widget.hostContext;
    final duration = _duration;
    if (_isNew) {
      final draft = _newTaskDraft(
        timeLog: duration == null ? const [] : _newTaskLog(duration),
      );
      Navigator.of(context).pop();
      goEntityCreateFullWidth(host, '/tasks', extra: draft);
      return;
    }
    final task = await _freshTask();
    if (!mounted || task == null) return;
    final placed = duration == null || _taskBlocked
        ? null
        : appendQuickLogEntry(
            log: task.timeLog,
            day: _day,
            duration: duration,
            now: DateTime.now(),
            billable: _billable,
          ).log;
    Navigator.of(context).pop();
    if (!host.mounted) return;
    await goEntityEditWithDraft(
      host,
      '/tasks',
      task.id,
      placed == null ? task : task.copyWith(timeLog: placed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: InSpacing.md(context));
    return FormSaveScope(
      onSubmit: _save,
      enabled: _canSave,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(InSpacing.lg(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                headingLevel: 1,
                child: Text(
                  context.tr('log_time'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SizedBox(height: InSpacing.lg(context)),
              _taskPicker(context),
              if (_isNew) ...[
                gap,
                LabeledField(
                  label: context.tr('description'),
                  child: TextField(
                    controller: _description,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.tr('description'),
                    ),
                  ),
                ),
                gap,
                ClientPickerField(
                  companyId: widget.companyId,
                  selectedClientId: _clientId,
                  onSelected: (c) => setState(() {
                    final next = c?.id ?? '';
                    // A project belongs to one client; a new client drops it.
                    if (next != _clientId) _projectId = '';
                    _clientId = next;
                  }),
                ),
                gap,
                _projectPicker(context),
              ],
              gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _durationField(context)),
                  const SizedBox(width: InSpacing.sm),
                  Expanded(
                    child: InDateField(
                      value: DateTime(_day.year, _day.month, _day.day),
                      onChanged: (picked) {
                        if (picked == null) return;
                        setState(() {
                          _error = null;
                          _day = Date(picked.year, picked.month, picked.day);
                        });
                      },
                      formatter: _formatter,
                      labelText: context.tr('date'),
                    ),
                  ),
                ],
              ),
              StreamBuilder<Company?>(
                stream: _company,
                builder: (context, snap) {
                  // The toggle means nothing when the company keeps every
                  // entry billable; default to showing it until it loads.
                  final allow =
                      snap.data?.settings.allowBillableTaskItems ?? true;
                  if (!allow) return const SizedBox.shrink();
                  return SwitchListTile(
                    value: _billable,
                    onChanged: (v) => setState(() => _billable = v),
                    title: Text(context.tr('billable')),
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
              if (_error != null) ...[
                SizedBox(height: InSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              SizedBox(height: InSpacing.lg(context)),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy || (_isNew && !_canCreate)
                        ? null
                        : _openEditor,
                    child: Text(context.tr('edit')),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 40),
                    ),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(context.tr('cancel')),
                  ),
                  SizedBox(width: InSpacing.md(context)),
                  PrimaryDialogAction(
                    label: context.tr('save'),
                    onPressed: _canSave ? _save : null,
                    busy: _busy,
                    // Starts disabled (no duration yet), and a field owns focus.
                    autofocus: false,
                    showEnterHint: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskPicker(BuildContext context) {
    // A running task can't take a second entry until it stops: the server
    // rejects a log whose running entry is not last.
    final errorText = (_task?.isRunning ?? false)
        ? context.tr('stop_task_to_add_task_entry')
        : null;
    return EntityPickerField<Task>(
      label: context.tr('task'),
      cacheKey: (widget.companyId, _day),
      selectedId: _taskId,
      itemsStream: () => _services.tasks
          .watchAllActive(companyId: widget.companyId)
          .map((tasks) => quickLogCandidates(tasks.where(_canEdit), day: _day)),
      watchById: (id) =>
          _services.tasks.watch(companyId: widget.companyId, id: id),
      displayString: quickLogTaskLabel,
      idOf: (t) => t.id,
      hintText: _canCreate ? context.tr('new_task') : context.tr('task'),
      emptyHintKey: 'no_records_found',
      errorText: errorText,
      onChanged: (t) => setState(() {
        _error = null;
        _taskId = t?.id ?? '';
        _task = t;
      }),
    );
  }

  Widget _projectPicker(BuildContext context) {
    final clientId = _clientId;
    return EntityPickerField<Project>(
      label: context.tr('project'),
      cacheKey: (widget.companyId, clientId),
      selectedId: _projectId,
      itemsStream: () => clientId.isEmpty
          ? _services.projects.watchPage(
              companyId: widget.companyId,
              loadedPages: 100,
            )
          : _services.projects.watchForClient(
              companyId: widget.companyId,
              clientId: clientId,
            ),
      watchById: (id) =>
          _services.projects.watch(companyId: widget.companyId, id: id),
      displayString: (p) => p.name.isEmpty ? p.id : p.name,
      idOf: (p) => p.id,
      emptyHintKey: 'no_records_found',
      onChanged: (p) => setState(() {
        _projectId = p?.id ?? '';
        if (p != null && p.clientId.isNotEmpty) _clientId = p.clientId;
      }),
    );
  }

  Widget _durationField(BuildContext context) => LabeledField(
    label: context.tr('duration'),
    child: TextField(
      controller: _durationText,
      onChanged: _onDurationChanged,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FormSaveScope.maybeOf(context)?.trySubmit(),
      decoration: InputDecoration(
        labelText: context.tr('duration'),
        hintText: exampleHint(context, kDurationExample),
        errorText: _durationInvalid
            ? context.tr('please_enter_a_valid_duration')
            : null,
        // The same presets the time-log table and the line-item sheet offer.
        suffixIcon: PopupMenuButton<int>(
          tooltip: context.tr('duration'),
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          padding: EdgeInsets.zero,
          iconSize: 18,
          onSelected: _applyDurationPreset,
          itemBuilder: (_) => [
            for (final m in const [15, 30, 45, 60, 90, 120, 180, 240])
              PopupMenuItem<int>(
                value: m,
                child: Text(
                  formatDuration(Duration(minutes: m), showSeconds: false),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
        suffixIconConstraints: BoxConstraints(
          minWidth: actionButtonSize(),
          minHeight: actionButtonSize(),
        ),
      ),
    ),
  );
}
