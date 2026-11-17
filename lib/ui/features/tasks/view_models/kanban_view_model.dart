import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/task_status.dart';
import 'package:admin/data/repositories/client_repository.dart';
import 'package:admin/data/repositories/project_repository.dart';
import 'package:admin/data/repositories/task_repository.dart';
import 'package:admin/data/repositories/task_status_repository.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;
import 'package:admin/ui/features/tasks/view_models/task_filters_mixin.dart';

/// State for the Kanban board view. Subscribes to:
///   * Every TaskStatus row → the column set (sorted by `status_order`).
///   * Every active Task grouped by `status_id` → the cards in each column.
///
/// Owns optimistic drag state: when the user drops a card the in-memory
/// `Map<String, List<Task>>` is mutated before the repo writes hit Drift,
/// so the board re-renders instantly. The repo write's watch-stream
/// emission then replaces the optimistic frame seamlessly.
class KanbanViewModel extends ChangeNotifier with TaskFiltersMixin {
  KanbanViewModel({
    required this.repo,
    required this.statusRepo,
    required this.companyId,
    this.projectRepo,
    this.clientRepo,
  }) {
    // Every cached name, archived included: a task on an archived client is
    // still on the board, and still found by that client's name.
    _clientNamesSub = clientRepo
        ?.watchAllNames(companyId: companyId)
        .listen((rows) => _onNames(clients: rows));
    _projectNamesSub = projectRepo
        ?.watchAllNames(companyId: companyId)
        .listen((rows) => _onNames(projects: rows));
    _statusesSub = statusRepo
        .watchAll(companyId: companyId)
        .listen(_onStatuses);
    _tasksSub = repo
        .watchAllByStatus(
          companyId: companyId,
          states: const {EntityState.active},
        )
        .listen(_onTasks);
    unawaited(_syncAll());
  }

  /// The id of the leading column that holds tasks on no status — a blank
  /// `status_id` (a task created offline before the server assigns one) or the
  /// id of a status that has since been deleted. Not a status: nothing can be
  /// dropped INTO it, only dragged out.
  static const String noStatusId = '';

  final TaskRepository repo;
  final TaskStatusRepository statusRepo;
  final String companyId;

  /// [quickAdd] reads it, to give a task created under a project filter that
  /// project's client and rate (null leaves such a task on no project), and
  /// the search matches a task by its project's name through it.
  final ProjectRepository? projectRepo;

  /// The search matches a task by its client's name through it. Null (a test
  /// that does not search) matches description and number only.
  final ClientRepository? clientRepo;

  StreamSubscription<List<({String id, String name})>>? _clientNamesSub;
  StreamSubscription<List<({String id, String name})>>? _projectNamesSub;
  Map<String, String> _clientNames = const {};
  Map<String, String> _projectNames = const {};

  void _onNames({
    List<({String id, String name})>? clients,
    List<({String id, String name})>? projects,
  }) {
    if (clients != null) _clientNames = {for (final r in clients) r.id: r.name};
    if (projects != null) {
      _projectNames = {for (final r in projects) r.id: r.name};
    }
    // A rename only matters to a search that is running.
    if (searchActive && !_disposed) notifyListeners();
  }

  /// The board is the one task view with a search field: it has no list to
  /// search instead, and a status board of a few hundred cards is exactly
  /// where "the one for the Smith job" gets lost.
  @override
  bool get supportsSearch => true;

  /// Tasks [quickAdd] created while a search was running. They stay on the
  /// board until the search changes — a card typed into a column that then
  /// vanished because its title does not match the search would read as a
  /// failed create, the reason a quick-add takes the other filters too.
  final Set<String> _addedUnderSearch = {};
  String _searchAddedUnder = '';

  StreamSubscription<List<TaskStatus>>? _statusesSub;
  StreamSubscription<Map<String, List<Task>>>? _tasksSub;

  List<TaskStatus> _statuses = const [];
  List<TaskStatus> get statuses => _statuses;

  Map<String, List<Task>> _tasksByStatus = const {};
  Map<String, List<Task>> get tasksByStatus => _tasksByStatus;

  /// Snapshot of the post-drop layout, set synchronously in
  /// [commitReorder] before the Drift write begins. Cleared in
  /// [_onTasks] once the next stream emission lands (which carries the
  /// persisted ordering). The board reads `tasksFor()` which prefers
  /// this override — drops the snap-back flicker between drop and the
  /// stream re-emission.
  Map<String, List<Task>>? _optimisticByStatus;

  // Client-side Project / Client / Assignee filters live in [TaskFiltersMixin]
  // (shared with the calendar / daily / weekly views). Applied in [tasksFor]
  // before the board groups/renders, so column card-counts reflect the filter
  // too. A filter does NOT make the board read-only: [moveTask] works on the
  // unfiltered columns.

  bool _isResolving = true;
  bool get isResolving => _isResolving;

  /// True while the opening sync is in flight — see [_syncAll].
  bool get isSyncing => _isSyncing;
  bool _isSyncing = false;

  /// The board reads Drift and nothing else, and lists load a page at a time,
  /// so on its own it showed only the tasks some other screen had happened to
  /// fetch — a user whose remembered view is the board opened a partial one.
  /// `refreshAll` is the Sync pass's own sweep for this table: the first call
  /// pages everything, every later one is the delta behind the cursor.
  ///
  /// Offline (or any failure) it leaves the board on what Drift holds; the
  /// catch is bare because nothing awaits this and test doubles raise `Error`s.
  Future<void> _syncAll() async {
    _isSyncing = true;
    try {
      await repo.refreshAll(companyId: companyId);
    } catch (_) {
      // Whatever is cached is still the best board there is.
    } finally {
      _isSyncing = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool _isReordering = false;
  bool get isReordering => _isReordering;

  bool _disposed = false;

  void _onStatuses(List<TaskStatus> next) {
    _statuses = next;
    _isResolving = false;
    // Guard against a Drift emission landing after dispose() (company switch /
    // nav-away while the watch is in flight) — notifyListeners() on a disposed
    // ChangeNotifier asserts in debug/test. Matches commitReorder's finally and
    // the GenericDetailViewModel convention (L10).
    if (!_disposed) notifyListeners();
  }

  void _onTasks(Map<String, List<Task>> next) {
    _tasksByStatus = next;
    // The stream's emission is the persisted truth. Drop the optimistic
    // override; the board re-reads from `_tasksByStatus` on the next
    // build. If the persisted state differs from optimistic (e.g.
    // another device wrote concurrently), the user sees the truth.
    _optimisticByStatus = null;
    if (!_disposed) notifyListeners();
  }

  /// Every task on [statusId], filters ignored, in the order the user last
  /// saw them: the optimistic snapshot while a move is in flight, otherwise
  /// the persisted order. What a move is computed against — see [moveTask].
  List<Task> _allFor(String statusId) =>
      (_optimisticByStatus ?? _tasksByStatus)[statusId] ?? const <Task>[];

  /// Tasks for [statusId] as the board draws them — [_allFor] narrowed by the
  /// active filters. [noStatusId] answers with the tasks on no column.
  List<Task> tasksFor(String statusId) {
    final base = statusId == noStatusId ? _orphans() : _allFor(statusId);
    if (!filtersActive) return base;
    if (search != _searchAddedUnder) _addedUnderSearch.clear();
    return base
        .where(
          (t) =>
              matchesFilters(t) &&
              (!searchActive ||
                  _addedUnderSearch.contains(t.id) ||
                  matchesSearch(
                    t,
                    clientName: _clientNames[t.clientId] ?? '',
                    projectName: _projectNames[t.projectId] ?? '',
                  )),
        )
        .toList(growable: false);
  }

  /// Tasks whose `status_id` names no column. They used to be on the board's
  /// data and in none of its columns — invisible.
  List<Task> _orphans() {
    final known = {for (final s in _statuses) s.id};
    // An optimistic layout holds only real columns, so a task just dragged
    // out of here is already in one of them.
    final placed = {
      for (final list in (_optimisticByStatus ?? const {}).values)
        for (final t in list) t.id,
    };
    return [
      for (final entry in _tasksByStatus.entries)
        if (!known.contains(entry.key))
          for (final t in entry.value)
            if (!placed.contains(t.id)) t,
    ];
  }

  /// Every task the board is showing, column by column — the order `J` / `K`
  /// step through behind an open task pane.
  List<Task> get visibleTasks => [
    ...tasksFor(noStatusId),
    for (final s in _statuses) ...tasksFor(s.id),
  ];

  /// Move [task] to [toStatusId]: above [beforeTaskId], at the top
  /// ([toTop], what a menu move does — there is no position to point at), or
  /// at the bottom.
  ///
  /// Computed against the UNFILTERED columns. A reorder built from what a
  /// filter leaves visible would drop every hidden task from its status's
  /// persisted order, which is why a filter used to switch drag off
  /// altogether; placed relative to a card that is really there, the hidden
  /// ones simply keep their places.
  Future<void> moveTask(
    Task task, {
    required String toStatusId,
    String? beforeTaskId,
    bool toTop = false,
  }) {
    final next = <String, List<Task>>{
      for (final s in _statuses)
        s.id: List<Task>.of(_allFor(s.id))..removeWhere((t) => t.id == task.id),
    };
    final target = next[toStatusId];
    if (target == null) return Future<void>.value();
    final moved = task.copyWith(statusId: toStatusId);
    final at = toTop
        ? 0
        : beforeTaskId == null
        ? -1
        : target.indexWhere((t) => t.id == beforeTaskId);
    if (at < 0) {
      target.add(moved);
    } else {
      target.insert(at, moved);
    }
    return commitReorder(orderedByStatus: next);
  }

  /// Persist a card move. Paints [orderedByStatus] instantly, writes the new
  /// `(status_id, status_order)` for every task in it, and enqueues the bulk
  /// `reorder` outbox row.
  ///
  /// [orderedByStatus] is the *full*, unfiltered board layout — every status,
  /// every task — which is what [moveTask] builds. Call that instead.
  @visibleForTesting
  Future<void> commitReorder({
    required Map<String, List<Task>> orderedByStatus,
  }) async {
    if (_isReordering) return;
    _isReordering = true;
    // Paint the optimistic layout synchronously before the await so the
    // dropped card doesn't snap back to its source position for a frame.
    _optimisticByStatus = orderedByStatus;
    notifyListeners();
    try {
      final statusIds = _statuses.map((s) => s.id).toList(growable: false);
      final taskIds = <String, List<String>>{
        for (final sid in statusIds)
          sid: (orderedByStatus[sid] ?? const <Task>[])
              .map((t) => t.id)
              .toList(growable: false),
      };
      await repo.reorder(
        companyId: companyId,
        statusIds: statusIds,
        orderedByStatus: taskIds,
      );
    } finally {
      _isReordering = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Create a task titled [description] at the bottom of [statusId] — the
  /// column's inline add. It goes through `TaskRepository.create` like any
  /// other, so it works offline and syncs from the outbox.
  ///
  /// The active filters seed it. A card added to a board filtered to one
  /// client, project or assignee that then vanished behind that very filter
  /// would read as a failed create; and it is what the user meant.
  Future<void> quickAdd({
    required String statusId,
    required String description,
  }) async {
    final text = description.trim();
    if (text.isEmpty) return;
    var draft = emptyTask().copyWith(
      description: text,
      statusId: statusId,
      statusOrder: _allFor(statusId).length,
      clientId: clientId,
      assignedUserId: assignedUserId,
      // Orders this create among other unsynced ones.
      updatedAt: DateTime.now().toUtc(),
    );
    if (projectId.isNotEmpty) {
      // A task on a project carries the project's client and rate — the same
      // three fields the project screen's own quick-add sets.
      final project = await projectRepo
          ?.watch(companyId: companyId, id: projectId)
          .first;
      if (project != null) {
        draft = draft.copyWith(
          projectId: project.id,
          clientId: project.clientId,
          rate: project.taskRate,
        );
      }
    }
    final created = await repo.create(companyId: companyId, draft: draft);
    if (searchActive) {
      if (search != _searchAddedUnder) {
        _addedUnderSearch.clear();
        _searchAddedUnder = search;
      }
      _addedUnderSearch.add(created.entity.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// Persist a column-header drag (status reordering on kanban).
  Future<void> commitStatusReorder(List<String> orderedStatusIds) async {
    await statusRepo.reorder(
      companyId: companyId,
      orderedStatusIds: orderedStatusIds,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _statusesSub?.cancel();
    _tasksSub?.cancel();
    _clientNamesSub?.cancel();
    _projectNamesSub?.cancel();
    super.dispose();
  }
}
