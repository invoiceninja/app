import 'package:flutter/widgets.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/tasks/view_models/task_daily_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/quick_log_time_sheet.dart';
import 'package:admin/ui/features/tasks/widgets/task_actions.dart';

/// Static dispatch for the daily-view actions (start/stop a timer, log time,
/// duplicate yesterday). Mirrors `TaskActions` so the screen + header stay thin.
class TaskDailyActions {
  TaskDailyActions._();

  /// Start or stop [task]'s timer through the outbox. Delegates to the
  /// shared [TaskActions.toggleTimer] so the daily row, list rows, kanban
  /// card, and detail KPI all run one code path.
  static Future<void> toggleTimer(
    BuildContext context,
    Services services,
    String companyId,
    Task task,
  ) => TaskActions.toggleTimer(context, services, companyId, task);

  /// Open the quick-log dialog on [day]: add a duration to an existing task,
  /// or to a new one, without leaving the view (`quick_log_time_sheet.dart`).
  static Future<void> logTime(
    BuildContext context,
    String companyId,
    Date day,
  ) => showQuickLogTimeSheet(context, companyId: companyId, day: day);

  /// Clone every task with stopped entries on the previous day into a fresh
  /// task for the focused day, each entry shifted +24h. Running source entries
  /// are skipped (cloning a running timer would create a second running task).
  /// Today-only — the header gates the affordance.
  static Future<void> duplicateYesterday(
    BuildContext context,
    Services services,
    String companyId,
    TaskDailyViewModel vm,
  ) async {
    // Re-entry / re-tap guard (M2): a second tap before the first completes —
    // or after the success toast, while the same source set still reads from
    // yesterday — must not create a second full batch.
    if (!vm.beginDuplicate()) return;
    var created = 0;
    try {
      final sources = vm.tasksOnDay(vm.day.addDays(-1));
      for (final src in sources) {
        final draft = buildDuplicate(src);
        if (draft == null) continue;
        await services.tasks.create(companyId: companyId, draft: draft);
        created++;
      }
    } finally {
      vm.endDuplicate(created: created > 0);
    }
    if (!context.mounted) return;
    if (created == 0) {
      Notify.info(context, context.tr('no_entries_to_duplicate'));
    } else {
      Notify.success(context, context.tr('duplicated_tasks'));
    }
  }

  /// Build the next-day duplicate of [src]: stopped entries shifted +1 local
  /// calendar day, server-owned identity fields blanked (so the create gets a
  /// fresh number/order — cloning the source's unique number would 422).
  /// Returns null when [src] has no stopped entry to clone. Visible for tests.
  static Task? buildDuplicate(Task src) {
    final shifted = <TimeEntry>[
      for (final e in src.timeLog)
        if (e.start != null && e.stop != null)
          e.copyWith(start: _plusOneDay(e.start!), stop: _plusOneDay(e.stop!)),
    ];
    if (shifted.isEmpty) return null;
    return src.copyWith(
      id: '',
      number: '',
      statusOrder: 0,
      invoiceId: '',
      // A duplicate is a brand-new task, not the same calendar event — drop
      // the calendar link so the server's calendar-event dedupe guard (which
      // would 422 a second task for the same event) doesn't reject it.
      meta: null,
      archivedAt: null,
      isDeleted: false,
      isDirty: false,
      documents: const [],
      timeLog: shifted,
    );
  }

  /// Shift a UTC instant forward by one CALENDAR day in the user's local zone,
  /// preserving wall-clock time-of-day across DST transitions — a fixed +24h
  /// would drift an hour and could land the entry on the wrong local day.
  static DateTime _plusOneDay(DateTime utc) {
    final l = utc.toLocal();
    return DateTime(
      l.year,
      l.month,
      l.day + 1,
      l.hour,
      l.minute,
      l.second,
    ).toUtc();
  }
}
