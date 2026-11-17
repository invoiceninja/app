import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/domain/tasks/task_schedule.dart';
import 'package:admin/domain/tasks/task_time_summary.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/show_seconds.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/running_duration_label.dart';
import 'package:admin/utils/formatting.dart';

/// The top of the task form's time-log column: the timer, and where the
/// draft's time stands.
///
/// * **The clock** is the running entry's own elapsed time, large — and only
///   while one runs. A stopped task gets no `0:00:00`: a zero clock reads as
///   a figure, and the strip below already says what has been logged.
/// * **The button** is the form's one Start / Resume / Stop. It works on the
///   draft through the view model, whose `startTimer` goes through
///   `planTaskStart` like every other start path (`docs/task-scheduling.md`),
///   and Resume is offered only where there is worked time to resume. Hidden
///   on an invoiced task, like every other control of the time log.
/// * **The strip** carries the record screen's rules over to the draft, from
///   the same computation (`TaskTimeSummary`): Logged and Billable tick while
///   the timer runs; Billable is left out where the company bills no task
///   items; Booked shows only when something is booked; the estimate and its
///   bar only when the task has one, with an overrun as a negative Remaining
///   in the overdue ink.
///
/// No billable switch for the task as a whole: billable is a property of each
/// entry, and the table below sets it per row.
class TaskEditTimerCard extends StatefulWidget {
  const TaskEditTimerCard({
    super.key,
    required this.vm,
    required this.locked,
    required this.allowBillable,
  });

  final TaskEditViewModel vm;
  final bool locked;

  /// Company `allow_billable_task_items`; false hides the Billable figure.
  final bool allowBillable;

  /// Below this width the button drops its label, as the time log's header
  /// did when it held it.
  static const double _compactWidth = 480;

  @override
  State<TaskEditTimerCard> createState() => _TaskEditTimerCardState();
}

class _TaskEditTimerCardState extends State<TaskEditTimerCard> {
  /// Once a second while a timer runs, so the strip's figures tick with the
  /// clock; not at all otherwise.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_onVmChanged);
    _syncTicker();
  }

  @override
  void didUpdateWidget(TaskEditTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm != widget.vm) {
      oldWidget.vm.removeListener(_onVmChanged);
      widget.vm.addListener(_onVmChanged);
      _syncTicker();
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onVmChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onVmChanged() {
    _syncTicker();
    if (mounted) setState(() {});
  }

  void _syncTicker() {
    final running = widget.vm.hasRunningEntry;
    if (running == (_ticker != null)) return;
    _ticker?.cancel();
    _ticker = running
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final vm = widget.vm;
    final running = vm.hasRunningEntry ? vm.draft.timeLog.last : null;
    final summary = TaskTimeSummary.of(vm.draft, vm.now());
    final strip = _SummaryStrip(
      summary: summary,
      allowBillable: widget.allowBillable,
      running: running != null,
    );
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r3),
      ),
      padding: EdgeInsets.all(InSpacing.lg(context)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < TaskEditTimerCard._compactWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // The clock while a timer runs; otherwise the strip takes
                  // its place, so a stopped task's card is one row.
                  Expanded(
                    child: running == null ? strip : _Clock(entry: running),
                  ),
                  if (!widget.locked) ...[
                    SizedBox(width: InSpacing.md(context)),
                    _TimerButton(vm: vm, compact: compact),
                  ],
                ],
              ),
              if (running != null) ...[
                SizedBox(height: InSpacing.md(context)),
                Divider(height: 1, color: tokens.border),
                SizedBox(height: InSpacing.md(context)),
                strip,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The running entry's elapsed time, large, with the pulsing dot every
/// running timer in the app wears.
class _Clock extends StatelessWidget {
  const _Clock({required this.entry});

  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final start = entry.start;
    if (start == null) return const SizedBox.shrink();
    return Semantics(
      label: context.tr('running'),
      child: FittedBox(
        // A run past a day reads `1d 03h 12m`; on a phone it shrinks rather
        // than pushing the Stop button off the card.
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: RunningDurationLabel(
          start: start,
          secondsPastDay: true,
          dotSize: 10,
          style: TextStyle(
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
            color: context.inTheme.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Start, Resume or Stop — whichever the draft calls for.
class _TimerButton extends StatelessWidget {
  const _TimerButton({required this.vm, required this.compact});

  final TaskEditViewModel vm;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String labelKey,
      VoidCallback onPressed,
    ) = vm.hasRunningEntry
        ? (Icons.stop_circle_outlined, 'stop', vm.stopTimer)
        // `hasStoppedEntries` is true for a booking too, so it alone offered
        // "Resume" on a task that has never been worked — the mislabel
        // invoiceninja/flutter#149 opens with.
        : (vm.hasStoppedEntries && vm.scheduleState == TaskScheduleState.none)
        ? (Icons.play_circle_outlined, 'resume', vm.resumeTimer)
        : (Icons.play_circle_outlined, 'start', vm.startTimer);
    if (compact) {
      return Tooltip(
        message: context.tr(labelKey),
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
          ),
          onPressed: onPressed,
          child: Icon(icon, semanticLabel: context.tr(labelKey)),
        ),
      );
    }
    // `minimumSize` per call: the theme's `Size.fromHeight(44)` is infinite
    // width, which a `Row` cannot lay out (CLAUDE.md § Design system (v2)).
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
      icon: Icon(icon),
      label: Text(context.tr(labelKey)),
      onPressed: onPressed,
    );
  }
}

/// Logged · Billable · Booked · Estimate, each present only when it has
/// something to say (see [TaskEditTimerCard]).
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.summary,
    required this.allowBillable,
    required this.running,
  });

  final TaskTimeSummary summary;
  final bool allowBillable;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final seconds = watchShowSeconds(context);
    // What the task list and the record show for a total: seconds while it
    // can tick, the day form past 24 hours.
    String total(Duration d) =>
        formatDuration(d, compactDays: true, secondsPastDay: seconds);
    // A booking and an estimate are typed in minutes; their seconds are
    // always `:00`.
    String short(Duration d) =>
        formatDuration(d, compactDays: true, showSeconds: false);
    return Wrap(
      spacing: InSpacing.xl,
      runSpacing: InSpacing.md(context),
      children: [
        _Figure(
          label: context.tr('logged'),
          value: total(summary.worked),
          valueColor: running ? tokens.accent : null,
        ),
        if (allowBillable)
          _Figure(
            label: context.tr('billable'),
            value: total(summary.billable),
          ),
        if (summary.booked > Duration.zero)
          _Figure(label: context.tr('booked'), value: short(summary.booked)),
        if (summary.hasEstimate) _EstimateFigure(summary: summary),
      ],
    );
  }
}

TextStyle _labelStyle(BuildContext context) =>
    TextStyle(fontSize: 12, color: context.inTheme.ink3);

TextStyle _valueStyle(BuildContext context, {Color? color}) => TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: color ?? context.inTheme.ink,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A label over its value, read as one by a screen reader.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _labelStyle(context)),
          const SizedBox(height: 2),
          LtrText(value, style: _valueStyle(context, color: valueColor)),
        ],
      ),
    );
  }
}

/// The estimate, a bar of how much of it the logged time has used, and —
/// once there is work to measure — what is left of it. An overrun is not
/// tidied away: the bar fills in the overdue ink and Remaining goes negative.
class _EstimateFigure extends StatelessWidget {
  const _EstimateFigure({required this.summary});

  final TaskTimeSummary summary;

  /// Wide enough for the bar to read as a bar beside a short `1:30`.
  static const double _minWidth = 140;

  static const int _barSteps = 1000;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    String short(Duration d) =>
        formatDuration(d, compactDays: true, showSeconds: false);
    final over = summary.isOver;
    final remaining = summary.remaining;
    final muted = _labelStyle(context);
    final filled = (summary.estimateProgress * _barSteps).round();
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _minWidth),
        // The bar takes the width of the widest text above or below it, not
        // the whole strip.
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('estimated_duration'), style: muted),
              const SizedBox(height: 2),
              LtrText(short(summary.estimate), style: _valueStyle(context)),
              const SizedBox(height: InSpacing.xs),
              ExcludeSemantics(
                child: Container(
                  height: 4,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: tokens.border,
                    borderRadius: BorderRadius.circular(InRadii.r1),
                  ),
                  // Flex, not `FractionallySizedBox`: the `IntrinsicWidth`
                  // above measures this, and a fractional box divides its
                  // child's width by the factor — NaN at zero progress.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (filled > 0)
                        Expanded(
                          flex: filled,
                          child: ColoredBox(
                            color: over ? tokens.overdue : tokens.accent,
                          ),
                        ),
                      if (filled < _barSteps)
                        Expanded(
                          flex: _barSteps - filled,
                          child: const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
              if (summary.showRemaining) ...[
                const SizedBox(height: InSpacing.xs),
                // Label and value, not a sentence: the bundles have no plural
                // forms and no word order a translation could not get wrong.
                Text(
                  over
                      ? '${context.tr('remaining')}: -${short(-remaining)}'
                      : '${context.tr('remaining')}: ${short(remaining)}',
                  style: over
                      ? muted.copyWith(
                          color: tokens.overdue,
                          fontWeight: FontWeight.w600,
                        )
                      : muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
