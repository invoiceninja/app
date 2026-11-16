import 'dart:ui' show PointerDeviceKind;

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_board.dart'
    show kKanbanColumnWidth;
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_column.dart';

import '../shell/_shell_test_helpers.dart';

/// [KanbanColumn]'s two independent gates (invoiceninja/flutter#135).
///
/// `canEdit` is "may rearrange the board" — the board folds `!filtersActive`
/// into it, so it goes false the moment a Client / Project / Assignee filter is
/// applied. `canCreate` is "may start a new task" (`create_task`), and it is
/// filter-independent. They were one field until the kanban screen dropped its
/// FAB, which made the `+ New Task` footer the board's ONLY create path: with
/// the two conflated, filtering the board — or holding `create_task` without
/// `edit_task` — left no way to add a task at all.
///
/// Nothing about that is visible at the call site, and neither half fails
/// loudly: the wrong gate simply renders one widget fewer.
final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

final _status = TaskStatus(
  id: 's1',
  name: 'Backlog',
  color: '',
  statusOrder: 0,
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

/// A card with no client, project or assignee, so nothing in it reaches Drift.
Task _task(String id, {int minutes = 0}) => Task(
  id: id,
  number: id,
  description: 'Task $id',
  rate: Decimal.zero,
  invoiceId: '',
  clientId: '',
  projectId: '',
  statusId: 's1',
  statusOrder: 0,
  assignedUserId: '',
  timeLog: [
    if (minutes > 0)
      TimeEntry(
        start: DateTime.utc(2026, 1, 1, 9),
        stop: DateTime.utc(2026, 1, 1, 9).add(Duration(minutes: minutes)),
      ),
  ],
  customValue1: '',
  customValue2: '',
  customValue3: '',
  customValue4: '',
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

void main() {
  /// Pumps a column — by default with NO tasks, which keeps the body's
  /// `ListView.builder` at `itemCount: 0`, so no `KanbanCard` is built and
  /// nothing in the subtree reaches Drift. No `GoRouter` is needed either; the
  /// footer is only ever found, never tapped.
  Future<void> pumpColumn(
    WidgetTester tester, {
    required bool canEdit,
    required bool canCreate,
    List<Task> tasks = const <Task>[],
    TaskStatus? status,
    void Function(Task task, String? beforeTaskId)? onAcceptTask,
    Future<void> Function(String description)? onQuickAdd,
  }) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Center(
          child: SizedBox(
            width: kKanbanColumnWidth,
            height: 600,
            child: KanbanColumn(
              status: status ?? _status,
              tasks: tasks,
              companyId: 'co1',
              canEdit: canEdit,
              canCreate: canCreate,
              onQuickAdd: onQuickAdd,
              onAcceptTask: onAcceptTask ?? (_, _) {},
              // The header drag handle needs BOTH `canEdit` and a non-null
              // `onAcceptStatus`, so a test asserting the handle's absence
              // proves nothing unless this is supplied. Always non-null: the
              // board derives both from one expression, so `canEdit: true`
              // alongside a null callback is unreachable in production.
              onAcceptStatus: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // `en.json`: new_task => 'New Task'. `find.text` is an exact match, so the
  // column's other strings (the status name, and 'New Task Status' elsewhere in
  // the app) cannot satisfy it.
  final footer = find.text('New Task');
  // With an empty column this is the header's handle — the only one left once
  // the per-card handles have nothing to attach to.
  final dragHandle = find.byIcon(Icons.drag_indicator);

  testWidgets('canCreate renders the + New Task footer', (tester) async {
    await pumpColumn(tester, canEdit: true, canCreate: true);
    expect(footer, findsOneWidget);
  });

  testWidgets('without canCreate there is no footer', (tester) async {
    await pumpColumn(tester, canEdit: true, canCreate: false);
    expect(footer, findsNothing);
    // ...and the reorder affordance is untouched, so a reader can see that the
    // absence above is the create gate and not a collapsed column.
    expect(dragHandle, findsOneWidget);
  });

  testWidgets('a filtered board keeps the footer but loses the drag handle', (
    tester,
  ) async {
    // What the board passes once any filter is active — and what a create-only
    // user (`create_task`, no `edit_task`) gets at every moment. This is the
    // case the split exists for.
    await pumpColumn(tester, canEdit: false, canCreate: true);
    expect(footer, findsOneWidget);
    expect(dragHandle, findsNothing);
  });

  testWidgets('neither gate leaves both affordances off', (tester) async {
    await pumpColumn(tester, canEdit: false, canCreate: false);
    expect(footer, findsNothing);
    expect(dragHandle, findsNothing);
  });

  group('header', () {
    testWidgets('totals the time worked on its cards beside the count', (
      tester,
    ) async {
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        tasks: [_task('a', minutes: 60), _task('b', minutes: 30), _task('c')],
      );
      expect(find.text('3'), findsOneWidget);
      // The cards read 1:00 and 0:30; only the header can read 1:30.
      expect(find.text('1:30'), findsOneWidget);
      expect(find.byTooltip('Total duration'), findsOneWidget);
    });

    testWidgets('a column with no time on it shows no total', (tester) async {
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        tasks: [_task('a')],
      );
      expect(find.byTooltip('Total duration'), findsNothing);
      // ...and an untouched card says nothing rather than `0:00`.
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('a status with no name never shows its id', (tester) async {
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        status: _status.copyWith(name: ''),
      );
      expect(find.text('s1'), findsNothing);
      expect(find.text('(no name)'), findsOneWidget);
    });
  });

  group('card drag', () {
    testWidgets('a mouse drags the card itself, from anywhere on it', (
      tester,
    ) async {
      final drops = <(String, String?)>[];
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        tasks: [_task('a'), _task('b')],
        onAcceptTask: (task, before) => drops.add((task.id, before)),
      );
      // Only the header keeps a handle.
      expect(dragHandle, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Task b')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final target = tester.getCenter(find.text('Task a'));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(drops, [('b', 'a')]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('a finger has to long-press: a plain drag is the scroll', (
      tester,
    ) async {
      final drops = <(String, String?)>[];
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        tasks: [_task('a'), _task('b')],
        onAcceptTask: (task, before) => drops.add((task.id, before)),
      );
      await tester.dragFrom(
        tester.getCenter(find.text('Task b')),
        tester.getCenter(find.text('Task a')) -
            tester.getCenter(find.text('Task b')),
      );
      await tester.pump();
      expect(drops, isEmpty);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Task b')),
      );
      await tester.pump(const Duration(milliseconds: 550));
      await gesture.moveTo(tester.getCenter(find.text('Task a')));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(drops, [('b', 'a')]);
    });

    testWidgets('a read-only column drags nothing', (tester) async {
      await pumpColumn(
        tester,
        canEdit: false,
        canCreate: true,
        tasks: [_task('a'), _task('b')],
      );
      expect(find.byType(LongPressDraggable<Task>), findsNothing);
      expect(find.byType(Draggable<Task>), findsNothing);
    });
  });

  group('inline add', () {
    testWidgets('the footer becomes a field; Enter adds and keeps it open', (
      tester,
    ) async {
      final added = <String>[];
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        onQuickAdd: (text) async => added.add(text),
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(footer);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Call the bank');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(added, ['Call the bank']);

      // Cleared and still there, for the next one.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      await tester.enterText(find.byType(TextField), 'Send the quote');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(added, ['Call the bank', 'Send the quote']);

      // The full form is one tap away.
      expect(find.byTooltip('More Fields'), findsOneWidget);
    });

    testWidgets('Enter on nothing adds nothing', (tester) async {
      final added = <String>[];
      await pumpColumn(
        tester,
        canEdit: true,
        canCreate: true,
        onQuickAdd: (text) async => added.add(text),
      );
      await tester.tap(footer);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(added, isEmpty);
    });

    testWidgets('a create-only user still gets it', (tester) async {
      await pumpColumn(
        tester,
        canEdit: false,
        canCreate: true,
        onQuickAdd: (_) async {},
      );
      await tester.tap(footer);
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
