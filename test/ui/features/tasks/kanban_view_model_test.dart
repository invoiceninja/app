import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/data/repositories/task_repository.dart';
import 'package:admin/data/repositories/task_status_repository.dart';
import 'package:admin/ui/features/tasks/view_models/kanban_view_model.dart';

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Task _t(
  String id, {
  String projectId = '',
  String clientId = '',
  String assignedUserId = '',
  String statusId = 's1',
}) => Task(
  id: id,
  number: id,
  description: id,
  rate: Decimal.zero,
  invoiceId: '',
  clientId: clientId,
  projectId: projectId,
  statusId: statusId,
  statusOrder: 0,
  assignedUserId: assignedUserId,
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
  name: id,
  color: '',
  statusOrder: 0,
  updatedAt: _epoch,
  createdAt: _epoch,
  archivedAt: null,
  isDeleted: false,
);

class _FakeTaskRepo implements TaskRepository {
  _FakeTaskRepo(this._byStatus);
  final Map<String, List<Task>> _byStatus;
  bool reorderCalled = false;
  Map<String, List<String>>? reordered;
  int refreshed = 0;
  final created = <Task>[];

  @override
  Future<SaveResult<Task>> create({
    required String companyId,
    required Task draft,
    String? existingTempId,
  }) async {
    created.add(draft);
    return SaveResult(entity: draft, outboxRowId: 1);
  }

  @override
  Future<void> refreshAll({
    required String companyId,
    bool full = false,
  }) async {
    refreshed++;
  }

  @override
  Stream<Map<String, List<Task>>> watchAllByStatus({
    required String companyId,
    states = const {},
  }) => Stream.value(_byStatus);

  @override
  Future<void> reorder({
    required String companyId,
    required List<String> statusIds,
    required Map<String, List<String>> orderedByStatus,
  }) async {
    reorderCalled = true;
    reordered = orderedByStatus;
  }

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeStatusRepo implements TaskStatusRepository {
  _FakeStatusRepo(this._statuses);
  final List<TaskStatus> _statuses;

  @override
  Stream<List<TaskStatus>> watchAll({required String companyId}) =>
      Stream.value(_statuses);

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  KanbanViewModel build(Map<String, List<Task>> byStatus, _FakeTaskRepo repo) =>
      KanbanViewModel(
        repo: repo,
        statusRepo: _FakeStatusRepo([_s('s1')]),
        companyId: 'co',
      );

  test('no filters → tasksFor returns the full status list', () async {
    final repo = _FakeTaskRepo({
      's1': [_t('a', projectId: 'p1'), _t('b', clientId: 'c1')],
    });
    final vm = build(const {}, repo);
    await Future<void>.delayed(Duration.zero);
    expect(vm.filtersActive, isFalse);
    expect(vm.tasksFor('s1').map((t) => t.id), ['a', 'b']);
  });

  test(
    'filters by project / client / assignee (AND) before grouping',
    () async {
      final repo = _FakeTaskRepo({
        's1': [
          _t('a', projectId: 'p1', clientId: 'c1'),
          _t('b', projectId: 'p1', clientId: 'c2'),
          _t('c', projectId: 'p2', clientId: 'c1'),
        ],
      });
      final vm = build(const {}, repo);
      await Future<void>.delayed(Duration.zero);

      vm.setProjectFilter('p1');
      expect(vm.filtersActive, isTrue);
      expect(vm.tasksFor('s1').map((t) => t.id), ['a', 'b']);

      vm.setClientFilter('c1'); // AND
      expect(vm.tasksFor('s1').map((t) => t.id), ['a']);

      vm.clearFilters();
      expect(vm.filtersActive, isFalse);
      expect(vm.tasksFor('s1').map((t) => t.id), ['a', 'b', 'c']);
    },
  );

  test('a move under a filter keeps every hidden task in the persisted '
      'order', () async {
    // A filter used to switch drag off, because a reorder built from the
    // visible cards dropped the hidden ones from their status's order.
    final repo = _FakeTaskRepo({
      's1': [_t('a', assignedUserId: 'u1'), _t('b'), _t('c')],
      's2': [_t('d', statusId: 's2'), _t('e', statusId: 's2')],
    });
    final vm = KanbanViewModel(
      repo: repo,
      statusRepo: _FakeStatusRepo([_s('s1'), _s('s2')]),
      companyId: 'co',
    );
    await Future<void>.delayed(Duration.zero);

    vm.setAssigneeFilter('u1');
    expect(vm.tasksFor('s1').map((t) => t.id), ['a']);
    await vm.moveTask(vm.tasksFor('s1').single, toStatusId: 's2', toTop: true);

    expect(repo.reordered, {
      's1': ['b', 'c'],
      's2': ['a', 'd', 'e'],
    });
  });

  test(
    'a drop lands above the card it was dropped on, else at the end',
    () async {
      final repo = _FakeTaskRepo({
        's1': [_t('a'), _t('b'), _t('c')],
      });
      final vm = build(const {}, repo);
      await Future<void>.delayed(Duration.zero);

      await vm.moveTask(_t('c'), toStatusId: 's1', beforeTaskId: 'a');
      expect(repo.reordered, {
        's1': ['c', 'a', 'b'],
      });
      await vm.moveTask(_t('a'), toStatusId: 's1');
      expect(repo.reordered?['s1']?.last, 'a');
    },
  );

  test('a task on no known status is offered on the no-status column, and '
      'leaves it once moved', () async {
    final repo = _FakeTaskRepo({
      's1': [_t('a')],
      '': [_t('blank', statusId: '')],
      'gone': [_t('stale', statusId: 'gone')],
    });
    final vm = build(const {}, repo);
    await Future<void>.delayed(Duration.zero);

    expect(vm.tasksFor(KanbanViewModel.noStatusId).map((t) => t.id), [
      'blank',
      'stale',
    ]);
    await vm.moveTask(_t('stale', statusId: 'gone'), toStatusId: 's1');
    expect(repo.reordered, {
      's1': ['a', 'stale'],
    });
  });

  test('opening the board syncs the task table once', () async {
    final repo = _FakeTaskRepo(const {});
    final vm = build(const {}, repo);
    expect(vm.isSyncing, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(repo.refreshed, 1);
    expect(vm.isSyncing, isFalse);
  });

  group('quickAdd', () {
    test(
      'creates the task at the bottom of the column it was typed into',
      () async {
        final repo = _FakeTaskRepo({
          's1': [_t('a'), _t('b')],
        });
        final vm = build(const {}, repo);
        await Future<void>.delayed(Duration.zero);

        await vm.quickAdd(statusId: 's1', description: '  Call the bank  ');
        final draft = repo.created.single;
        expect(draft.description, 'Call the bank');
        expect(draft.statusId, 's1');
        expect(draft.statusOrder, 2);
        expect(draft.clientId, isEmpty);
      },
    );

    test('nothing typed creates nothing', () async {
      final repo = _FakeTaskRepo(const {});
      final vm = build(const {}, repo);
      await vm.quickAdd(statusId: 's1', description: '   ');
      expect(repo.created, isEmpty);
    });

    test('takes the active filters, so the new card does not vanish behind '
        'them', () async {
      final repo = _FakeTaskRepo(const {});
      final vm = build(const {}, repo);
      await Future<void>.delayed(Duration.zero);
      vm
        ..setClientFilter('c1')
        ..setAssigneeFilter('u1');

      await vm.quickAdd(statusId: 's1', description: 'Draft the brief');
      final draft = repo.created.single;
      expect(draft.clientId, 'c1');
      expect(draft.assignedUserId, 'u1');
      expect(vm.matchesFilters(draft), isTrue);
    });
  });
}
