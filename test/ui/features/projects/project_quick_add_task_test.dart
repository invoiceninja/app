import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/task_status_api_model.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/ui/features/projects/view_models/project_edit_view_model.dart'
    show emptyProject;
import 'package:admin/ui/features/projects/widgets/detail/project_quick_add_task.dart';

import '../shell/_shell_test_helpers.dart';

/// Quick task creation at the head of the project's Tasks tab
/// (invoiceninja/ui#3383). That the new task then shows in the list under the
/// field is covered where the list is — `project_detail_screen_test.dart`.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Enter creates a task on the project, seeded with the first '
      'status, and keeps the field focused for the next one', (tester) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);
    final services = fixture.services;
    await tester.runAsync(
      () => services.taskStatuses.applyBundle(
        companyId: 'co1',
        bundle: const [
          TaskStatusApi(id: 'st2', name: 'Doing', statusOrder: 2),
          TaskStatusApi(id: 'st1', name: 'Backlog', statusOrder: 1),
        ],
      ),
    );
    final project = emptyProject().copyWith(
      id: 'p1',
      name: 'Site',
      clientId: 'cl1',
      taskRate: Decimal.fromInt(80),
    );

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapWithShell(
        services,
        Scaffold(
          body: SingleChildScrollView(
            child: ProjectQuickAddTask(project: project, companyId: 'co1'),
          ),
        ),
      ),
    );
    await settle(tester);

    final field = find.byKey(const Key('project_quick_add_task'));
    await tester.tap(field);
    await tester.enterText(field, 'Design homepage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    final tasks = await tester.runAsync(
      () => services.tasks
          .watchForProject(companyId: 'co1', projectId: 'p1')
          .first,
    );
    final task = tasks!.single;
    expect(task.description, 'Design homepage');
    expect(task.clientId, 'cl1');
    expect(task.rate, Decimal.fromInt(80));
    // Board order, never blank — a blank status is in no kanban column.
    expect(task.statusId, 'st1');

    final input = tester.widget<TextField>(field);
    expect(input.controller!.text, isEmpty);
    expect(input.focusNode!.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  Future<void> pumpField(
    WidgetTester tester,
    ShellFixture fixture,
    Project project,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Scaffold(
          body: SingleChildScrollView(
            child: ProjectQuickAddTask(project: project, companyId: 'co1'),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<ShellFixture> fixtureWithStatuses(WidgetTester tester) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    await tester.runAsync(
      () => fixture.services.taskStatuses.applyBundle(
        companyId: 'co1',
        bundle: const [
          TaskStatusApi(id: 'st1', name: 'Backlog', statusOrder: 1),
          TaskStatusApi(id: 'st2', name: 'Ready to do', statusOrder: 2),
          TaskStatusApi(id: 'st3', name: 'In progress', statusOrder: 3),
        ],
      ),
    );
    return fixture;
  }

  testWidgets('Start creates the typed task already running, In progress, '
      'through the planner', (tester) async {
    final fixture = await fixtureWithStatuses(tester);
    addTearDown(fixture.dispose);
    final services = fixture.services;
    final project = emptyProject().copyWith(
      id: 'p1',
      name: 'Site',
      clientId: 'cl1',
      taskRate: Decimal.fromInt(80),
    );
    await pumpField(tester, fixture, project);

    final field = find.byKey(const Key('project_quick_add_task'));
    await tester.enterText(field, 'Call the client');
    final before = DateTime.now();
    await tester.tap(find.byKey(const Key('project_quick_add_start')));
    await settle(tester);

    final tasks = await tester.runAsync(
      () => services.tasks
          .watchForProject(companyId: 'co1', projectId: 'p1')
          .first,
    );
    final task = tasks!.single;
    expect(task.description, 'Call the client');
    expect(task.clientId, 'cl1');
    expect(task.rate, Decimal.fromInt(80));
    // The move a Start makes from a not-started status (`TaskActions`).
    expect(task.statusId, 'st3');
    // One open entry, from now: what `planTaskStart` appends to an empty log.
    expect(task.isRunning, isTrue);
    expect(task.timeLog, hasLength(1));
    final entry = task.timeLog.single;
    expect(entry.stop, isNull);
    expect(entry.billable, isTrue);
    expect(
      entry.start!.isBefore(before.subtract(const Duration(seconds: 5))),
      isFalse,
    );

    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Start works on an empty field — Enter does not', (tester) async {
    final fixture = await fixtureWithStatuses(tester);
    addTearDown(fixture.dispose);
    final services = fixture.services;
    final project = emptyProject().copyWith(id: 'p1', name: 'Site');
    await pumpField(tester, fixture, project);

    final field = find.byKey(const Key('project_quick_add_task'));
    await tester.tap(field);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    var tasks = await tester.runAsync(
      () => services.tasks
          .watchForProject(companyId: 'co1', projectId: 'p1')
          .first,
    );
    expect(tasks, isEmpty, reason: 'Enter on nothing creates nothing');

    await tester.tap(find.byKey(const Key('project_quick_add_start')));
    await settle(tester);
    tasks = await tester.runAsync(
      () => services.tasks
          .watchForProject(companyId: 'co1', projectId: 'p1')
          .first,
    );
    // The server takes a task with no description; name it later.
    expect(tasks!.single.description, isEmpty);
    expect(tasks.single.isRunning, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'the field is the app\'s standard field, as tall as the '
    'search field under it, and Start lines up with it',
    (tester) async {
      final fixture = await fixtureWithStatuses(tester);
      addTearDown(fixture.dispose);
      final project = emptyProject().copyWith(id: 'p1', name: 'Site');
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Theme(
            data: buildInTheme(InTheme.light),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ProjectQuickAddTask(project: project, companyId: 'co1'),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      final field = find.byKey(const Key('project_quick_add_task'));
      // Material's bare `OutlineInputBorder()` drew a dark radius-4 outline; the
      // app's field border rests on `borderStrong` at the edit fields' radius.
      final border = tester.widget<TextField>(field).decoration!.border!;
      expect(border, isA<WidgetStateInputBorder>());
      final resting =
          (border as WidgetStateInputBorder).resolve(const {})
              as OutlineInputBorder;
      expect(resting.borderSide.color, InTheme.light.borderStrong);
      expect(resting.borderSide.width, 1);
      expect(resting.borderRadius, BorderRadius.circular(InRadii.r1));

      final fieldBox = tester.getRect(
        find.descendant(of: field, matching: find.byType(InputDecorator)),
      );
      final start = tester.getRect(
        find.byKey(const Key('project_quick_add_start')),
      );
      expect(fieldBox.height, closeTo(InSizes.headerRow, 0.5));
      expect(start.top, closeTo(fieldBox.top, 0.5));
      expect(start.height, closeTo(fieldBox.height, 0.5));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );

  test('offered only where a task could be created on the project', () {
    final project = emptyProject().copyWith(id: 'p1', name: 'Site');
    bool applies(Project p, {bool can = true}) =>
        ProjectQuickAddTask.appliesTo(p, canCreateTask: can);
    expect(applies(project), isTrue);
    expect(applies(project, can: false), isFalse);
    expect(applies(project.copyWith(isDeleted: true)), isFalse);
    expect(
      applies(project.copyWith(archivedAt: DateTime.utc(2026, 5, 1))),
      isFalse,
    );
    // The server has never seen it: a task pointing at it could not sync.
    expect(applies(project.copyWith(id: 'tmp_1')), isFalse);
  });
}
