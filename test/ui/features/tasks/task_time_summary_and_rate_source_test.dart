import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/company_settings_api_model.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/domain/tasks/task_rate.dart';
import 'package:admin/domain/tasks/task_time_summary.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart'
    show emptyClient;
import 'package:admin/ui/features/projects/view_models/project_edit_view_model.dart'
    show emptyProject;
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;

/// The two computations the task edit screen shares with the record screen:
/// what the timer card's strip shows (`TaskTimeSummary`, also behind
/// `TaskDetailStanding`) and which level a blank Rate field inherits from
/// (`resolveTaskRateWithSource`, behind `resolveTaskRate`).
final _now = DateTime.utc(2026, 6, 1, 12);

TimeEntry _worked(int hours, {bool billable = true}) => TimeEntry(
  start: DateTime.utc(2026, 5, 1, 9),
  stop: DateTime.utc(2026, 5, 1, 9 + hours),
  billable: billable,
);

Task _task({List<TimeEntry> log = const [], int estimate = 0}) =>
    emptyTask().copyWith(id: 't1', timeLog: log, estimatedSeconds: estimate);

void main() {
  group('TaskTimeSummary', () {
    test('worked, billable and booked come from the booking-aware getters', () {
      // A future block on the due date is a booking: never worked time.
      final task = emptyTask().copyWith(
        id: 't1',
        dueDate: null,
        timeLog: [
          _worked(2),
          _worked(1, billable: false).copyWith(
            start: DateTime.utc(2026, 5, 2, 9),
            stop: DateTime.utc(2026, 5, 2, 10),
          ),
          TimeEntry(
            start: DateTime.utc(2026, 6, 3, 9),
            stop: DateTime.utc(2026, 6, 3, 11),
          ),
        ],
      );
      final s = TaskTimeSummary.of(task, _now);
      expect(s.worked, task.workedTime(_now));
      expect(s.billable, task.billableDuration(_now));
      expect(s.booked, task.bookedTime(_now));
      expect(s.worked, const Duration(hours: 3));
      expect(s.billable, const Duration(hours: 2));
      expect(s.booked, const Duration(hours: 2));
    });

    test('no estimate: nothing to show, no progress', () {
      final s = TaskTimeSummary.of(_task(log: [_worked(2)]), _now);
      expect(s.hasEstimate, isFalse);
      expect(s.showRemaining, isFalse);
      expect(s.isOver, isFalse);
      expect(s.estimateProgress, 0);
    });

    test('nothing worked yet: Remaining would only restate the estimate', () {
      final s = TaskTimeSummary.of(_task(estimate: 3600), _now);
      expect(s.hasEstimate, isTrue);
      expect(s.showRemaining, isFalse);
      expect(s.estimateProgress, 0);
    });

    test('under the estimate: what is left, and the share used', () {
      final s = TaskTimeSummary.of(
        _task(log: [_worked(1)], estimate: 4 * 3600),
        _now,
      );
      expect(s.showRemaining, isTrue);
      expect(s.isOver, isFalse);
      expect(s.remaining, const Duration(hours: 3));
      expect(s.estimateProgress, 0.25);
    });

    test('an overrun is negative, and the bar is full', () {
      final s = TaskTimeSummary.of(
        _task(log: [_worked(3)], estimate: 2 * 3600),
        _now,
      );
      expect(s.isOver, isTrue);
      expect(s.remaining, const Duration(hours: -1));
      expect(s.estimateProgress, 1.0);
    });
  });

  group('resolveTaskRateWithSource', () {
    final zero = emptyTask().copyWith(id: 't1');
    final project = emptyProject().copyWith(
      id: 'p1',
      taskRate: Decimal.fromInt(90),
    );
    final client = emptyClient().copyWith(
      id: 'c1',
      settings: {'default_task_rate': 80},
    );
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final group = GroupSetting(
      id: 'g1',
      name: 'Wholesale',
      customValue1: '',
      customValue2: '',
      customValue3: '',
      customValue4: '',
      updatedAt: epoch,
      createdAt: epoch,
      archivedAt: null,
      isDeleted: false,
      settings: {'default_task_rate': '70'},
    );
    const company = Company(
      id: 'co',
      settings: CompanySettingsApi(defaultTaskRate: 60),
    );

    void expectLevel(
      ({Decimal rate, TaskRateSource source}) r,
      int rate,
      TaskRateSource source,
    ) {
      expect(r.rate, Decimal.fromInt(rate));
      expect(r.source, source);
    }

    test('each level answers in cascade order', () {
      expectLevel(
        resolveTaskRateWithSource(
          task: zero.copyWith(rate: Decimal.fromInt(100)),
          project: project,
          client: client,
          group: group,
          company: company,
        ),
        100,
        TaskRateSource.task,
      );
      expectLevel(
        resolveTaskRateWithSource(
          task: zero,
          project: project,
          client: client,
          group: group,
          company: company,
        ),
        90,
        TaskRateSource.project,
      );
      expectLevel(
        resolveTaskRateWithSource(
          task: zero,
          client: client,
          group: group,
          company: company,
        ),
        80,
        TaskRateSource.client,
      );
      expectLevel(
        resolveTaskRateWithSource(task: zero, group: group, company: company),
        70,
        TaskRateSource.group,
      );
      expectLevel(
        resolveTaskRateWithSource(task: zero, company: company),
        60,
        TaskRateSource.company,
      );
      expectLevel(
        resolveTaskRateWithSource(task: zero),
        0,
        TaskRateSource.none,
      );
    });

    test('resolveTaskRate is the same walk', () {
      expect(
        resolveTaskRate(task: zero, client: client, company: company),
        resolveTaskRateWithSource(
          task: zero,
          client: client,
          company: company,
        ).rate,
      );
    });
  });
}
