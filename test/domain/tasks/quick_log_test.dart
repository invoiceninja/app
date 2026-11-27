import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/tasks/quick_log.dart';
import 'package:admin/domain/tasks/task_schedule.dart';

Task _t(
  String id, {
  List<TimeEntry> log = const [],
  String invoiceId = '',
  int updated = 0,
}) => Task(
  id: id,
  number: '',
  description: '',
  rate: Decimal.zero,
  invoiceId: invoiceId,
  clientId: '',
  projectId: '',
  statusId: 's1',
  statusOrder: 0,
  assignedUserId: '',
  timeLog: log,
  customValue1: '',
  customValue2: '',
  customValue3: '',
  customValue4: '',
  updatedAt: DateTime.fromMillisecondsSinceEpoch(updated * 1000, isUtc: true),
  createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  archivedAt: null,
  isDeleted: false,
);

// Local wall-clock times throughout: a task's day is the LOCAL date of an
// entry's start, so these hold in every time zone.
final _now = DateTime(2026, 11, 27, 14, 0);
const _today = Date(2026, 11, 27);
const _past = Date(2026, 11, 24);

void main() {
  group('appendQuickLogEntry', () {
    test('today: the block ends now', () {
      final r = appendQuickLogEntry(
        log: const [],
        day: _today,
        duration: const Duration(minutes: 90),
        now: _now,
      );
      expect(r.problem, isNull);
      expect(r.log!.single.start, DateTime(2026, 11, 27, 12, 30));
      expect(r.log!.single.stop, _now);
    });

    test('today: a block longer than the day so far starts at midnight', () {
      final r = appendQuickLogEntry(
        log: const [],
        day: _today,
        duration: const Duration(hours: 20),
        now: _now,
      );
      expect(r.log!.single.start, DateTime(2026, 11, 27));
    });

    test('another day: the block starts at 09:00', () {
      final r = appendQuickLogEntry(
        log: const [],
        day: _past,
        duration: const Duration(minutes: 30),
        now: _now,
        billable: false,
      );
      final e = r.log!.single;
      expect(e.start, DateTime(2026, 11, 24, 9));
      expect(e.stop, DateTime(2026, 11, 24, 9, 30));
      expect(e.billable, isFalse);
    });

    test('keeps the existing entries and adds one', () {
      final other = TimeEntry(
        start: DateTime(2026, 11, 20, 9),
        stop: DateTime(2026, 11, 20, 10),
      );
      final r = appendQuickLogEntry(
        log: [other],
        day: _past,
        duration: const Duration(hours: 1),
        now: _now,
      );
      expect(r.log, hasLength(2));
      expect(r.log!.first, other);
    });

    test('a colliding slot moves to where the day\'s last entry stopped', () {
      final morning = TimeEntry(
        start: DateTime(2026, 11, 24, 8),
        stop: DateTime(2026, 11, 24, 11),
      );
      final r = appendQuickLogEntry(
        log: [morning],
        day: _past,
        duration: const Duration(hours: 2),
        now: _now,
      );
      expect(r.problem, isNull);
      expect(r.log!.last.start, DateTime(2026, 11, 24, 11));
      expect(r.log!.last.stop, DateTime(2026, 11, 24, 13));
    });

    test('today, after a session that ran until now: placed after it', () {
      final session = TimeEntry(start: DateTime(2026, 11, 27, 13), stop: _now);
      final r = appendQuickLogEntry(
        log: [session],
        day: _today,
        duration: const Duration(minutes: 30),
        now: _now,
      );
      expect(r.problem, isNull);
      expect(timeLogProblem(r.log!), isNull);
      expect(r.log!.last.start, _now);
    });

    test('a running entry is refused, never reordered around', () {
      final running = TimeEntry(start: DateTime(2026, 11, 27, 13), stop: null);
      final r = appendQuickLogEntry(
        log: [running],
        day: _today,
        duration: const Duration(minutes: 30),
        now: _now,
      );
      expect(r.log, isNull);
      expect(r.problem, isNotNull);
    });
  });

  group('quickLogCandidates', () {
    test('leaves out invoiced tasks', () {
      final out = quickLogCandidates([
        _t('a'),
        _t('b', invoiceId: 'inv1'),
      ], day: _past);
      expect(out.map((t) => t.id), ['a']);
    });

    test('this day first, then this week, then most recently updated', () {
      TimeEntry on(int day) => TimeEntry(
        start: DateTime(2026, 11, day, 9),
        stop: DateTime(2026, 11, day, 10),
      );
      final out = quickLogCandidates([
        _t('old', updated: 10),
        _t('recent', updated: 99),
        _t('week', log: [on(21)], updated: 1),
        _t('day', log: [on(1), on(24)], updated: 0),
      ], day: _past);
      expect(out.map((t) => t.id), ['day', 'week', 'recent', 'old']);
    });
  });
}
