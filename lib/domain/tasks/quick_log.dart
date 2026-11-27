import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/tasks/task_day.dart';
import 'package:admin/domain/tasks/task_schedule.dart';

/// Where a quick-logged block lands in a task's time log — the rules behind
/// the Tasks views' **Log time** dialog (`quick_log_time_sheet.dart`).
///
/// A task has no stored date: its day is the local date of an entry's start,
/// so "log 1:30 on Tuesday" means choosing a start and stop on Tuesday. The
/// choice is:
///
///  * **Today** — the block ends now. That is what "I just spent 30 minutes on
///    this" means, and it keeps the entry out of the future, where
///    `isTimeEntryBooking` would read it as a plan rather than time worked.
///  * **Any other day** — the block starts at 09:00, the same anchor the weekly
///    grid (`weekly_merge.dart`) and React's quick-log modal use.
///
/// When that slot collides with the task's own entries — the usual case for an
/// existing task logged twice on one day — the block moves to start where the
/// day's last entry stopped. Overlap is the one shape the server rejects for a
/// second entry (`Request::checkTimeLog`, ported as [timeLogProblem]), and
/// a quick log has no start-time field the user could fix it with.
///
/// Returns the log to save, or the [TimeLogProblem] when even the moved block
/// can't fit (a running entry, which the caller refuses before this, or a
/// block that would run past an entry starting later that day).
({List<TimeEntry>? log, TimeLogProblem? problem}) appendQuickLogEntry({
  required List<TimeEntry> log,
  required Date day,
  required Duration duration,
  required DateTime now,
  bool billable = true,
  String description = '',
}) {
  TimeEntry block(DateTime start) => TimeEntry(
    start: start,
    stop: start.add(duration),
    description: description,
    billable: billable,
  );

  final dayStart = DateTime(day.year, day.month, day.day);
  DateTime first;
  if (day == Date(now.year, now.month, now.day)) {
    first = now.subtract(duration);
    // A block longer than the day so far would start yesterday and land on the
    // wrong day — start it at midnight instead.
    if (first.isBefore(dayStart)) first = dayStart;
  } else {
    first = dayStart.add(const Duration(hours: 9));
  }

  var candidate = [...log, block(first)];
  var problem = timeLogProblem(candidate);
  if (problem == null) return (log: candidate, problem: null);

  DateTime? lastStop;
  for (final e in log) {
    if (timeEntryLocalDate(e) != day) continue;
    final stop = e.stop?.toLocal();
    if (stop == null) continue;
    if (lastStop == null || stop.isAfter(lastStop)) lastStop = stop;
  }
  if (lastStop != null) {
    candidate = [...log, block(lastStop)];
    final moved = timeLogProblem(candidate);
    if (moved == null) return (log: candidate, problem: null);
    problem = moved;
  }
  return (log: null, problem: problem);
}

/// The tasks a quick log may add time to, best candidates first.
///
/// Invoiced tasks are left out: the server freezes an invoiced task's log, and
/// every other surface in the app treats one as read-only. A running task stays
/// in (the user is likely looking for it), and the dialog says why it can't
/// take a second entry.
///
/// Order: tasks with time on [day] first, then tasks with time in the week
/// around it, then the most recently updated — the task you are most likely
/// logging against is one you already worked on nearby.
List<Task> quickLogCandidates(Iterable<Task> tasks, {required Date day}) {
  final weekFrom = day.addDays(-6);
  final weekTo = day.addDays(6);
  int rank(Task t) {
    var best = 2;
    for (final e in t.timeLog) {
      final d = timeEntryLocalDate(e);
      if (d == null) continue;
      if (d == day) return 0;
      if (d.compareTo(weekFrom) >= 0 && d.compareTo(weekTo) <= 0) best = 1;
    }
    return best;
  }

  final ranked = [
    for (final t in tasks)
      if (!t.isInvoiced) (task: t, rank: rank(t)),
  ];
  ranked.sort((a, b) {
    final c = a.rank.compareTo(b.rank);
    if (c != 0) return c;
    final u = b.task.updatedAt.compareTo(a.task.updatedAt);
    return u != 0 ? u : a.task.id.compareTo(b.task.id);
  });
  return [for (final r in ranked) r.task];
}
