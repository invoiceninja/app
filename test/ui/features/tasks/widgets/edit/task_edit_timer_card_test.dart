import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/data/repositories/task_repository.dart';
import 'package:admin/data/services/tasks_api.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/edit/task_edit_timer_card.dart';
import 'package:admin/ui/features/tasks/widgets/edit/time_entry_row.dart';
import 'package:admin/ui/features/tasks/widgets/edit/time_entry_table.dart';
import 'package:admin/ui/features/tasks/widgets/running_duration_label.dart';

import '../../../../../_responsive_helper.dart';

class _FakeTasksApi implements TasksApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The task form's timer card (the running clock, Start / Resume / Stop and
/// the Logged / Billable / Booked / Estimate strip) and the time log's empty
/// state and remove buttons.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  // Noon UTC: the same calendar day from UTC−11 to UTC+10 (CLAUDE.md § Strict
  // rules).
  final now = DateTime.utc(2026, 6, 5, 12);

  TimeEntry worked(int hours, {bool billable = true}) => TimeEntry(
    start: DateTime.utc(2026, 6, 4, 9),
    stop: DateTime.utc(2026, 6, 4, 9 + hours),
    billable: billable,
  );

  TaskEditViewModel vmWith(List<TimeEntry> log, {int estimate = 0}) =>
      TaskEditViewModel(
        repo: TaskRepository(db: db, api: _FakeTasksApi()),
        companyId: 'co',
        now: () => now,
        existing: emptyTask().copyWith(
          id: 't1',
          timeLog: log,
          estimatedSeconds: estimate,
        ),
      );

  Future<void> pumpCard(
    WidgetTester tester,
    TaskEditViewModel vm, {
    bool locked = false,
    bool allowBillable = true,
    double width = 700,
  }) => pumpAt(
    tester,
    width,
    TaskEditTimerCard(vm: vm, locked: locked, allowBillable: allowBillable),
  );

  // invoiceninja/app#220: the form's Start / Resume inside the rounding tail
  // of the entry just stopped continues that entry, keeping its note.
  group('the rounding tail', () {
    final rounded = TimeEntry(
      start: now.subtract(const Duration(minutes: 7)),
      stop: now.add(const Duration(minutes: 8)),
      description: 'Boiler',
    );

    test('with the client\'s interval, Resume continues the entry', () async {
      final vm = TaskEditViewModel(
        repo: TaskRepository(db: db, api: _FakeTasksApi()),
        companyId: 'co',
        now: () => now,
        existing: emptyTask().copyWith(id: 't1', timeLog: [rounded]),
        roundUpLookup: (_) async => 15 * 60,
      );
      addTearDown(vm.dispose);
      await Future<void>.delayed(Duration.zero);
      vm.resumeTimer();
      expect(vm.draft.timeLog, hasLength(1));
      final entry = vm.draft.timeLog.single;
      expect(entry.isRunning, isTrue);
      expect(entry.start, rounded.start);
      expect(entry.description, 'Boiler', reason: 'not the blank seed');
    });

    test('without one, the overlap still refuses the start', () {
      final vm = vmWith([rounded]);
      addTearDown(vm.dispose);
      vm.resumeTimer();
      expect(vm.draft.timeLog, [rounded]);
    });
  });

  group('the clock', () {
    testWidgets('collapses when nothing runs — no 0:00:00', (tester) async {
      await pumpCard(tester, vmWith([worked(2)]));
      expect(find.byType(RunningDurationLabel), findsNothing);
      expect(find.text('0:00:00'), findsNothing);
      // Worked time and no booking: Resume, not Start.
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Logged'), findsOneWidget);
      expect(find.text('2:00:00'), findsNWidgets(2)); // Logged and Billable
    });

    testWidgets('shows the running entry, with Stop', (tester) async {
      final vm = vmWith([
        worked(1),
        TimeEntry(start: DateTime.now().toUtc(), stop: null),
      ]);
      await pumpCard(tester, vm);
      expect(find.byType(RunningDurationLabel), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an empty task offers Start', (tester) async {
      await pumpCard(tester, vmWith(const []));
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('0:00:00'), findsNWidgets(2)); // Logged and Billable
    });

    testWidgets('an invoiced task has no button', (tester) async {
      await pumpCard(tester, vmWith([worked(1)]), locked: true);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Logged'), findsOneWidget);
    });

    testWidgets('a phone keeps the button, without its label', (tester) async {
      await pumpCard(tester, vmWith([worked(1)]), width: 360);
      expect(find.text('Resume'), findsNothing);
      expect(find.byTooltip('Resume'), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('the strip', () {
    testWidgets('Billable is left out where the company bills no task items', (
      tester,
    ) async {
      await pumpCard(tester, vmWith([worked(2)]), allowBillable: false);
      expect(find.text('Billable'), findsNothing);
    });

    testWidgets('Billable counts only billable entries', (tester) async {
      await pumpCard(
        tester,
        vmWith([
          worked(2),
          worked(1, billable: false).copyWith(
            start: DateTime.utc(2026, 6, 4, 13),
            stop: DateTime.utc(2026, 6, 4, 14),
          ),
        ]),
      );
      expect(find.text('3:00:00'), findsOneWidget); // Logged
      expect(find.text('2:00:00'), findsOneWidget); // Billable
    });

    testWidgets('Booked and the estimate appear only when there is one', (
      tester,
    ) async {
      await pumpCard(tester, vmWith([worked(1)]));
      expect(find.text('Booked'), findsNothing);
      expect(find.text('Estimated Duration'), findsNothing);

      await pumpCard(
        tester,
        vmWith([
          worked(1),
          // Tomorrow: a booking, not worked time.
          TimeEntry(
            start: DateTime.utc(2026, 6, 6, 9),
            stop: DateTime.utc(2026, 6, 6, 11),
          ),
        ], estimate: 4 * 3600),
      );
      expect(find.text('Booked'), findsOneWidget);
      expect(find.text('2:00'), findsOneWidget);
      expect(find.text('Estimated Duration'), findsOneWidget);
      expect(find.text('4:00'), findsOneWidget);
      expect(find.text('Remaining: 3:00'), findsOneWidget);
    });

    testWidgets('an overrun is a negative Remaining in the overdue ink', (
      tester,
    ) async {
      await pumpCard(tester, vmWith([worked(3)], estimate: 2 * 3600));
      final remaining = tester.widget<Text>(find.text('Remaining: -1:00'));
      expect(remaining.style?.color, InTheme.light.overdue);
    });
  });

  group('the time log', () {
    testWidgets('no entries: no column headers, the empty state', (
      tester,
    ) async {
      await pumpAt(tester, 900, TimeEntryTable(vm: vmWith([]), locked: false));
      expect(find.text('DATE'), findsNothing);
      expect(find.text('No time logged yet'), findsOneWidget);
      expect(
        find.text(
          "Start the timer, or add time if you've already done the work.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('an invoiced task is not invited to log time', (tester) async {
      await pumpAt(tester, 900, TimeEntryTable(vm: vmWith([]), locked: true));
      expect(find.text('No time logged yet'), findsOneWidget);
      expect(
        find.text(
          "Start the timer, or add time if you've already done the work.",
        ),
        findsNothing,
      );
    });

    testWidgets('the headers come back with the first entry', (tester) async {
      await pumpAt(
        tester,
        900,
        TimeEntryTable(vm: vmWith([worked(1)]), locked: false),
      );
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('No time logged yet'), findsNothing);
    });
  });

  group('the remove button (docs/touch-targets.md traps 2, 3 and 5)', () {
    testWidgets('44 px under a finger, 32 px with a pointer', (tester) async {
      for (final (touch, size) in const [(true, 44.0), (false, 32.0)]) {
        await pumpAt(
          tester,
          400,
          Center(
            child: TimeEntryRemoveButton(onPressed: () {}, touch: touch),
          ),
        );
        expect(
          tester.getSize(find.byType(IconButton)),
          Size(size, size),
          reason: 'touch: $touch',
        );
      }
    });

    testWidgets('the table gives a touch device the full target', (
      tester,
    ) async {
      // flutter_test's default platform is Android: touch-primary, `padded`.
      expect(defaultTargetPlatform, TargetPlatform.android);
      await pumpAt(
        tester,
        900,
        TimeEntryTable(vm: vmWith([worked(1)]), locked: false),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: find.byType(TimeEntryRemoveButton),
            matching: find.byType(IconButton),
          ),
        ),
        const Size(44, 44),
      );
      expectNoOverflow(tester);
    });

    testWidgets('and so does a phone row', (tester) async {
      await pumpAt(
        tester,
        360,
        TimeEntryRow(entry: worked(1), onTap: () {}, onRemove: () {}),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: find.byType(TimeEntryRemoveButton),
            matching: find.byType(IconButton),
          ),
        ),
        const Size(44, 44),
      );
      expectNoOverflow(tester);
    });
  });
}
