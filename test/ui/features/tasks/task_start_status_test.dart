import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/task_api_model.dart';
import 'package:admin/data/models/api/task_status_api_model.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/ui/features/tasks/widgets/task_actions.dart';

import '../shell/_shell_test_helpers.dart';

/// Every non-bulk Start moves a task that has not been started onto the
/// company's In-progress status, with an Undo that puts the log and the status
/// back (`docs/task-scheduling.md`). It used to happen only when a booking was
/// claimed, so a plain Start left a ticking card in Backlog.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(ShellFixture, Task)> setUpTask(
    WidgetTester tester, {
    required String statusId,
  }) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    final services = fixture.services;
    await tester.runAsync(
      () => services.taskStatuses.applyBundle(
        companyId: 'co1',
        bundle: const [
          TaskStatusApi(id: 'st1', name: 'Backlog', statusOrder: 1),
          TaskStatusApi(id: 'st2', name: 'Ready to do', statusOrder: 2),
          TaskStatusApi(id: 'st3', name: 'In progress', statusOrder: 3),
          TaskStatusApi(id: 'st4', name: 'Done', statusOrder: 4),
        ],
      ),
    );
    // A real id: the toggle refuses an unsynced `tmp_` row.
    await tester.runAsync(
      () => services.tasks.applyUpdateResponse(
        companyId: 'co1',
        serverResponse: TaskApi(
          id: 't1',
          description: 'Fix the gate',
          statusId: statusId,
        ),
      ),
    );
    final task = await tester.runAsync(
      () => services.tasks.getByIds(companyId: 'co1', ids: const ['t1']),
    );
    return (fixture, task!.single);
  }

  Future<void> pumpStart(
    WidgetTester tester,
    ShellFixture fixture,
    Task task,
  ) async {
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => TaskActions.toggleTimer(
                context,
                fixture.services,
                'co1',
                task,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
  }

  Future<Task> stored(WidgetTester tester, ShellFixture fixture) async =>
      (await tester.runAsync(
        () => fixture.services.tasks.getByIds(
          companyId: 'co1',
          ids: const ['t1'],
        ),
      ))!.single;

  testWidgets('a plain Start moves a Backlog task to In progress, and Undo '
      'puts both the log and the status back', (tester) async {
    final (fixture, task) = await setUpTask(tester, statusId: 'st1');
    addTearDown(fixture.dispose);
    await pumpStart(tester, fixture, task);

    var now = await stored(tester, fixture);
    expect(now.isRunning, isTrue);
    expect(now.statusId, 'st3');

    final toast = fixture.services.toasts.toasts.last;
    expect(toast.detail, 'Moved to In progress');
    expect(toast.action, isNotNull, reason: 'the same Undo a claim offers');
    toast.action!.onPressed();
    await settle(tester);

    now = await stored(tester, fixture);
    expect(now.isRunning, isFalse);
    expect(now.timeLog, isEmpty);
    expect(now.statusId, 'st1');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a task past "not started" keeps its status and gets no Undo', (
    tester,
  ) async {
    final (fixture, task) = await setUpTask(tester, statusId: 'st4');
    addTearDown(fixture.dispose);
    await pumpStart(tester, fixture, task);

    final now = await stored(tester, fixture);
    expect(now.isRunning, isTrue);
    expect(now.statusId, 'st4');
    final toast = fixture.services.toasts.toasts.last;
    expect(toast.detail, isNull);
    expect(toast.action, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
