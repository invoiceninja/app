import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/data/repositories/task_repository.dart';
import 'package:admin/data/repositories/task_status_repository.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/ui/core/list/master_detail_nav_scope.dart';
import 'package:admin/ui/features/tasks/view_models/kanban_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_board.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_column.dart';

import '../shell/_shell_test_helpers.dart';

/// The board around the columns: how wide a column is, where a phone's scroll
/// comes to rest, and the edge scroll that lets a dragged card reach a column
/// that is not on screen. None of it fails loudly — a board that neither snaps
/// nor scrolls under a drag still draws every card.
final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Task _t(String id, String statusId, {String clientId = ''}) => Task(
  id: id,
  number: id,
  description: 'Task $id',
  rate: Decimal.zero,
  invoiceId: '',
  clientId: clientId,
  projectId: '',
  statusId: statusId,
  statusOrder: 0,
  assignedUserId: '',
  timeLog: const [],
  customValue1: '',
  customValue2: '',
  customValue3: '',
  customValue4: '',
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

TaskStatus _s(String id) => TaskStatus(
  id: id,
  name: 'Status $id',
  color: '',
  statusOrder: 0,
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

class _FakeTaskRepo implements TaskRepository {
  _FakeTaskRepo([Map<String, List<Task>>? byStatus])
    : _byStatus =
          byStatus ??
          {
            's1': [_t('a', 's1')],
          };

  final Map<String, List<Task>> _byStatus;

  @override
  Stream<Map<String, List<Task>>> watchAllByStatus({
    required String companyId,
    states = const {},
  }) => Stream.value(_byStatus);

  Map<String, List<String>>? reordered;

  @override
  Future<void> reorder({
    required String companyId,
    required List<String> statusIds,
    required Map<String, List<String>> orderedByStatus,
  }) async {
    reordered = orderedByStatus;
  }

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeStatusRepo implements TaskStatusRepository {
  @override
  Stream<List<TaskStatus>> watchAll({required String companyId}) =>
      Stream.value([for (var i = 1; i <= 6; i++) _s('s$i')]);

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  Future<_FakeTaskRepo> pumpBoard(
    WidgetTester tester,
    Size size, {
    Map<String, List<Task>>? tasks,
    KanbanPrefs prefs = const KanbanPrefs(),
    ValueChanged<KanbanPrefs>? onPrefsChanged,
    MasterDetailNavController? navController,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
      // The lane titles watch Drift; without this `db.close()` waits on the
      // stream cache's timer, which fake async never fires.
      closeStreamsSynchronously: true,
    );
    addTearDown(fixture.dispose);
    // Cached, so a lane title resolves from Drift and its lazy hydrate (a
    // request whose timeout timer would outlive the test) never fires.
    for (final id in const ['c1', 'c2']) {
      await fixture.db.clientDao.upsert(
        ClientsCompanion.insert(
          id: id,
          companyId: 'co1',
          name: 'Client $id',
          number: '',
          email: '',
          displayName: 'Client $id',
          balance: '0',
          updatedAt: 1,
          payload: jsonEncode({
            'id': id,
            'name': 'Client $id',
            'display_name': 'Client $id',
          }),
        ),
      );
    }
    final repo = _FakeTaskRepo(tasks);
    final vm = KanbanViewModel(
      repo: repo,
      statusRepo: _FakeStatusRepo(),
      companyId: 'co1',
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        ChangeNotifierProvider<KanbanViewModel>.value(
          value: vm,
          child: navController == null
              ? KanbanBoard(prefs: prefs, onPrefsChanged: onPrefsChanged)
              : MasterDetailNavScope(
                  controller: navController,
                  child: KanbanBoard(
                    prefs: prefs,
                    onPrefsChanged: onPrefsChanged,
                  ),
                ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return repo;
  }

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(KanbanBoard),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .pixels;

  testWidgets('a phone narrows the column so the next one shows, and '
      'comes to rest on a column', (tester) async {
    await pumpBoard(tester, const Size(340, 700));
    final column = tester.getSize(find.byType(KanbanColumn).first);
    // 340 − 12 side − 12 gap − 28 of the next column.
    expect(column.width, 288);
    expect(tester.getTopLeft(find.byType(KanbanColumn).at(1)).dx, 312);

    await tester.fling(find.byType(KanbanBoard), const Offset(-120, 0), 900);
    await tester.pumpAndSettle();
    expect(offset(tester) % 300, 0);
    expect(offset(tester), greaterThan(0));
  });

  testWidgets('a desktop column keeps its width and the board scrolls freely', (
    tester,
  ) async {
    await pumpBoard(tester, const Size(900, 700));
    expect(
      tester.getSize(find.byType(KanbanColumn).first).width,
      kKanbanColumnWidth,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a card held at the board\'s edge scrolls the board', (
    tester,
  ) async {
    final repo = await pumpBoard(tester, const Size(900, 700));
    expect(offset(tester), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Task a')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveTo(const Offset(890, 300));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrolled = offset(tester);
    expect(scrolled, greaterThan(100));

    // Letting go stops it, and the card lands in a column the board had to
    // scroll to — the first one no longer holds it.
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(offset(tester), scrolled);
    expect(repo.reordered?['s1'], isEmpty);
    expect(repo.reordered?.values.expand((ids) => ids), ['a']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A mouse drag of the card titled [from] onto whatever is at [to].
  Future<void> dragCard(WidgetTester tester, String from, Offset to) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(from)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(12, 12));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  group('tasks on no status', () {
    testWidgets('get a leading column of their own, with no create and no '
        'way in', (tester) async {
      final repo = await pumpBoard(
        tester,
        const Size(1100, 700),
        tasks: {
          's1': [_t('a', 's1')],
          '': [_t('lost', '')],
        },
      );
      expect(find.text('No status'), findsOneWidget);
      expect(find.text('Task lost'), findsOneWidget);
      final first = find.byType(KanbanColumn).first;
      expect(
        find.descendant(of: first, matching: find.text('New Task')),
        findsNothing,
      );

      // Out of it works...
      await dragCard(
        tester,
        'Task lost',
        tester.getCenter(find.text('Task a')),
      );
      expect(repo.reordered?['s1'], ['lost', 'a']);
    }, variant: mac);

    testWidgets('...and a card cannot be dropped into it', (tester) async {
      final repo = await pumpBoard(
        tester,
        const Size(1100, 700),
        tasks: {
          's1': [_t('a', 's1')],
          '': [_t('lost', '')],
        },
      );
      await dragCard(
        tester,
        'Task a',
        tester.getCenter(find.text('Task lost')),
      );
      expect(repo.reordered, isNull);
    }, variant: mac);

    testWidgets('no such task, no such column', (tester) async {
      await pumpBoard(tester, const Size(1100, 700));
      expect(find.text('No status'), findsNothing);
    }, variant: mac);
  });

  group('a collapsed column', () {
    testWidgets('is a strip that still takes a drop, and a tap opens it', (
      tester,
    ) async {
      final changes = <KanbanPrefs>[];
      const prefs = KanbanPrefs(collapsedStatusIds: {'s2'});
      final repo = await pumpBoard(
        tester,
        const Size(1100, 700),
        prefs: prefs,
        onPrefsChanged: changes.add,
      );
      final strip = find.byType(KanbanCollapsedColumn);
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).width, KanbanCollapsedColumn.width);
      // The second status is the strip, not a column: the first column is
      // followed directly by the strip.
      expect(
        tester.getTopLeft(strip).dx,
        tester.getTopRight(find.byType(KanbanColumn).first).dx + 12,
      );

      await dragCard(tester, 'Task a', tester.getCenter(strip));
      expect(repo.reordered?['s2'], ['a']);

      await tester.tap(strip);
      expect(changes.single.collapsedStatusIds, isEmpty);
    }, variant: mac);

    testWidgets('the header button folds a column', (tester) async {
      final changes = <KanbanPrefs>[];
      await pumpBoard(
        tester,
        const Size(1100, 700),
        onPrefsChanged: changes.add,
      );
      await tester.tap(find.byTooltip('Collapse column').first);
      expect(changes.single.collapsedStatusIds, {'s1'});
    }, variant: mac);
  });

  group('lanes', () {
    final tasks = {
      's1': [
        _t('a', 's1', clientId: 'c1'),
        _t('b', 's1', clientId: 'c2'),
        _t('n', 's1'),
      ],
      's2': [_t('c', 's2', clientId: 'c2')],
    };
    const prefs = KanbanPrefs(groupBy: KanbanGroupBy.client);

    testWidgets('one lane per client, the clientless one last', (tester) async {
      await pumpBoard(
        tester,
        const Size(1100, 900),
        tasks: tasks,
        prefs: prefs,
      );
      expect(find.text('No client'), findsOneWidget);
      final ys = [
        for (final title in ['Task a', 'Task b', 'Task n'])
          tester.getTopLeft(find.text(title)).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
      expect(ys[2], greaterThan(tester.getTopLeft(find.text('No client')).dy));
      // b and c share a lane: same row, different columns.
      expect(
        (tester.getTopLeft(find.text('Task c')).dy - ys[1]).abs(),
        lessThan(1),
      );
    }, variant: mac);

    testWidgets('a card changes status inside its own lane', (tester) async {
      final repo = await pumpBoard(
        tester,
        const Size(1100, 900),
        tasks: tasks,
        prefs: prefs,
      );
      await dragCard(tester, 'Task b', tester.getCenter(find.text('Task c')));
      expect(repo.reordered?['s2'], ['b', 'c']);
    }, variant: mac);

    testWidgets('...and is refused by another lane', (tester) async {
      final repo = await pumpBoard(
        tester,
        const Size(1100, 900),
        tasks: tasks,
        prefs: prefs,
      );
      await dragCard(tester, 'Task a', tester.getCenter(find.text('Task c')));
      expect(repo.reordered, isNull);
    }, variant: mac);

    testWidgets('a lane folds shut', (tester) async {
      await pumpBoard(
        tester,
        const Size(1100, 900),
        tasks: tasks,
        prefs: prefs,
      );
      await tester.tap(find.text('No client'));
      await tester.pump();
      expect(find.text('Task n'), findsNothing);
      expect(find.text('Task a'), findsOneWidget);
    }, variant: mac);
  });

  testWidgets('a phone still comes to rest on a column when one is folded', (
    tester,
  ) async {
    await pumpBoard(
      tester,
      const Size(340, 700),
      prefs: const KanbanPrefs(collapsedStatusIds: {'s2'}),
      onPrefsChanged: (_) {},
    );
    await tester.fling(find.byType(KanbanBoard), const Offset(-120, 0), 900);
    await tester.pumpAndSettle();
    // Column 1 is 288 + 12; the strip after it 44 + 12 — so the stops are 0,
    // 300, 356, 656…, not multiples of one stride.
    expect([300.0, 356.0, 656.0], contains(offset(tester)));
  });

  testWidgets('folding a lane is saved when there is somewhere to save it', (
    tester,
  ) async {
    final changes = <KanbanPrefs>[];
    await pumpBoard(
      tester,
      const Size(1100, 900),
      tasks: {
        's1': [_t('a', 's1', clientId: 'c1'), _t('n', 's1')],
      },
      prefs: const KanbanPrefs(groupBy: KanbanGroupBy.client),
      onPrefsChanged: changes.add,
    );
    await tester.tap(find.text('No client'));
    expect(changes.single.isLaneClosed(''), isTrue);
    expect(changes.single.isLaneClosed('c1'), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the board gives the pane in front of it what a list would: '
      'its cards in order, and the tasks themselves', (tester) async {
    // It stays mounted behind an open task (`resolveTasksViewMode`), so J / K
    // step through THIS order and the pane seeds its first frame from THESE
    // objects. Without the publish both go dead and nothing throws.
    final controller = MasterDetailNavController();
    await pumpBoard(
      tester,
      const Size(1100, 700),
      tasks: {
        's2': [_t('c', 's2')],
        's1': [_t('a', 's1'), _t('b', 's1')],
        '': [_t('lost', '')],
      },
      navController: controller,
    );
    // Board order: the no-status column, then each status left to right.
    expect(controller.itemIds, ['lost', 'a', 'b', 'c']);
    expect((controller.itemById('b') as Task?)?.statusId, 's1');
    controller.update(
      selectedId: 'b',
      itemIds: controller.itemIds,
      items: controller.items,
    );
    expect(controller.nextId(), 'c');
    expect(controller.prevId(), 'a');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
