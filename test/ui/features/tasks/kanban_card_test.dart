import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/ui/core/widgets/user_avatar.dart';
import 'package:admin/ui/features/projects/widgets/project_name_label.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_card.dart';

import '../shell/_shell_test_helpers.dart';

/// The kanban card's inline timer toggle: present for an eligible task,
/// absent on the drag-feedback ghost (showTimerButton:false) and for an
/// invoiced task.
final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Task _task({
  String invoiceId = '',
  String projectId = '',
  String assignedUserId = '',
  List<TimeEntry> log = const [],
}) => Task(
  id: 't1',
  number: '1',
  description: 'Task',
  rate: Decimal.zero,
  invoiceId: invoiceId,
  clientId: '',
  projectId: projectId,
  statusId: '',
  statusOrder: 0,
  assignedUserId: assignedUserId,
  timeLog: log,
  customValue1: '',
  customValue2: '',
  customValue3: '',
  customValue4: '',
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

final _stopped = [
  TimeEntry(
    start: DateTime.utc(2026, 1, 1, 9),
    stop: DateTime.utc(2026, 1, 1, 10),
  ),
];

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Task task,
    bool showTimerButton = true,
    Set<KanbanCardField>? fields,
    List<TaskStatus> moveTargets = const [],
    ValueChanged<TaskStatus>? onMoveTo,
  }) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
      // The project line watches Drift; without this `db.close()` waits on
      // the stream's cache timer, which fake async never fires.
      closeStreamsSynchronously: true,
    );
    addTearDown(fixture.dispose);
    // Cached, so the label resolves from Drift and its lazy hydrate (a request
    // whose timeout timer would outlive the test) never fires.
    await fixture.db.projectDao.upsert(
      ProjectsCompanion.insert(
        id: 'p1',
        companyId: 'co1',
        updatedAt: 1,
        payload: jsonEncode({'id': 'p1', 'name': 'Apollo Redesign'}),
        name: const Value('Apollo Redesign'),
      ),
    );
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Center(
          child: SizedBox(
            width: 304,
            child: KanbanCard(
              task: task,
              companyId: 'co1',
              showTimerButton: showTimerButton,
              fields: fields,
              moveTargets: moveTargets,
              onMoveTo: onMoveTo,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('eligible task renders the toggle', (tester) async {
    await pumpCard(tester, task: _task(log: _stopped));
    expect(find.byIcon(Icons.play_circle_outlined), findsOneWidget);
  });

  // docs/touch-targets.md: the corner's Start/Stop is a finger's target on
  // touch, like the card's ⋮ — it was 36 (and `VisualDensity.compact` on a
  // 44 constraint draws 36 too).
  testWidgets('the timer toggle is a 44 px target on touch', (tester) async {
    await pumpCard(tester, task: _task(), moveTargets: const []);
    final button = find.ancestor(
      of: find.byIcon(Icons.play_circle_outlined),
      matching: find.byType(IconButton),
    );
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('on touch the timer and the ⋮ do not share a pixel', (
    tester,
  ) async {
    // Both are 44 under a finger and both sit on the card's end edge; an
    // overlap hands the lower part of the ⋮ to the timer (it is hit first).
    await pumpCard(tester, task: _task(), moveTargets: const []);
    final timer = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.play_circle_outlined),
        matching: find.byType(IconButton),
      ),
    );
    final menu = tester.getRect(find.byTooltip('Actions'));
    expect(timer.overlaps(menu), isFalse, reason: '$timer vs $menu');
  });

  testWidgets('...and stays compact with a pointer', (tester) async {
    await pumpCard(tester, task: _task());
    final button = find.ancestor(
      of: find.byIcon(Icons.play_circle_outlined),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(button).height, lessThan(44));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('drag-feedback ghost (showTimerButton:false) has no toggle', (
    tester,
  ) async {
    await pumpCard(tester, task: _task(log: _stopped), showTimerButton: false);
    expect(find.byIcon(Icons.play_circle_outlined), findsNothing);
  });

  testWidgets('invoiced task hides the toggle', (tester) async {
    await pumpCard(
      tester,
      task: _task(invoiceId: 'inv1', log: _stopped),
    );
    expect(find.byIcon(Icons.play_circle_outlined), findsNothing);
  });

  // invoiceninja/app#195
  testWidgets('a task on a project names the project', (tester) async {
    await pumpCard(
      tester,
      task: _task(projectId: 'p1', log: _stopped),
    );
    final label = tester.widget<ProjectNameLabel>(
      find.byType(ProjectNameLabel),
    );
    expect(label.projectId, 'p1');
    expect(find.text('Apollo Redesign'), findsOneWidget);
    // The card owns the tap; a link here would steal it.
    expect(label.link, isFalse);
  });

  testWidgets('a task with no project draws no project line', (tester) async {
    await pumpCard(tester, task: _task(log: _stopped));
    expect(find.byType(ProjectNameLabel), findsNothing);
  });

  testWidgets('time worked shows', (tester) async {
    await pumpCard(tester, task: _task(log: _stopped));
    expect(find.text('1:00'), findsOneWidget);
  });

  testWidgets('an untouched task shows no 0:00', (tester) async {
    await pumpCard(tester, task: _task());
    expect(find.text('0:00'), findsNothing);
  });

  testWidgets('an assigned task carries its assignee', (tester) async {
    await pumpCard(tester, task: _task(assignedUserId: 'u1'));
    expect(find.byType(UserAvatar), findsOneWidget);
  });

  testWidgets('an unassigned task carries no avatar', (tester) async {
    await pumpCard(tester, task: _task());
    expect(find.byType(UserAvatar), findsNothing);
  });

  testWidgets('a field switched off is not drawn', (tester) async {
    await pumpCard(
      tester,
      task: _task(projectId: 'p1', assignedUserId: 'u1', log: _stopped),
      fields: const {KanbanCardField.assignee},
    );
    expect(find.byType(ProjectNameLabel), findsNothing);
    expect(find.text('1:00'), findsNothing);
    expect(find.byType(UserAvatar), findsOneWidget);
  });

  testWidgets('the number is opt-in, above the title', (tester) async {
    await pumpCard(tester, task: _task());
    expect(find.text('#1'), findsNothing);
  });

  testWidgets('...and drawn once asked for', (tester) async {
    await pumpCard(
      tester,
      task: _task(),
      fields: {...KanbanCardField.defaults, KanbanCardField.number},
    );
    expect(find.text('#1'), findsOneWidget);
  });

  group('moving without a drag', () {
    final done = TaskStatus(
      id: 's9',
      name: 'Done',
      color: '',
      statusOrder: 0,
      updatedAt: _epoch,
      createdAt: _epoch,
      archivedAt: null,
      isDeleted: false,
    );

    testWidgets('the ⋮ menu moves the card to another status', (tester) async {
      final moved = <String>[];
      await pumpCard(
        tester,
        task: _task(),
        moveTargets: [done],
        onMoveTo: (s) => moved.add(s.id),
      );
      await tester.tap(find.byTooltip('Actions'));
      await tester.pump();
      await tester.tap(find.text('Move to'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(moved, ['s9']);
    });

    testWidgets('a screen reader gets each move as an action', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        task: _task(),
        moveTargets: [done],
        onMoveTo: (_) {},
      );
      expect(find.bySemanticsLabel('Task'), findsWidgets);
      final actions = tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.text('Task'),
              matching: find.byType(Semantics),
            ),
          )
          .expand(
            (s) =>
                s.properties.customSemanticsActions?.keys ??
                const <CustomSemanticsAction>[],
          )
          .map((a) => a.label);
      expect(actions, ['Move to Done']);
      handle.dispose();
    });

    testWidgets('a card that cannot be moved offers no Move to', (
      tester,
    ) async {
      await pumpCard(tester, task: _task(), moveTargets: [done]);
      await tester.tap(find.byTooltip('Actions'));
      await tester.pump();
      expect(find.text('Move to'), findsNothing);
    });
  });
}
