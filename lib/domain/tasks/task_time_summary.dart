import 'package:admin/data/models/domain/task.dart';

/// Where a task's time stands at one instant — what has been worked, what of
/// that bills, what is booked ahead, and how it sits against the estimate.
///
/// One computation for the two surfaces that summarise a task's time: the
/// record's standing card (`TaskDetailStanding`, on the saved task) and the
/// edit screen's timer card (`TaskEditTimerCard`, on the draft). Each figure
/// goes through `Task`'s own booking-aware getters, so a booking — a plan — is
/// never counted as worked or billable time (`docs/task-scheduling.md`).
class TaskTimeSummary {
  TaskTimeSummary.of(Task task, DateTime now)
    : worked = task.workedTime(now),
      billable = task.billableDuration(now),
      booked = task.bookedTime(now),
      estimate = Duration(
        seconds: task.estimatedSeconds > 0 ? task.estimatedSeconds : 0,
      );

  /// Time worked, billable or not (`Task.loggedDuration`).
  final Duration worked;

  /// The billable part of [worked] — what an invoice line would bill.
  final Duration billable;

  /// Time booked and not yet worked.
  final Duration booked;

  /// The task's estimate; zero when it has none.
  final Duration estimate;

  bool get hasEstimate => estimate > Duration.zero;

  /// Whether "remaining" says anything: not before any work (it would only
  /// restate the estimate) and not when the work lands exactly on it.
  bool get showRemaining =>
      hasEstimate && worked != Duration.zero && worked != estimate;

  /// The estimate has been overrun.
  bool get isOver => hasEstimate && worked > estimate;

  /// What is left of the estimate; negative once it is overrun.
  Duration get remaining => estimate - worked;

  /// [worked] as a share of the estimate, clamped to 0..1; 0 with none.
  double get estimateProgress =>
      hasEstimate ? (worked.inSeconds / estimate.inSeconds).clamp(0.0, 1.0) : 0;
}
