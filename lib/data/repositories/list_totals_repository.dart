import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Table;
import 'package:logging/logging.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/db/dao/base_entity_dao.dart';
import 'package:admin/data/repositories/base_entity_repository.dart'
    show CompanySwitchedException;
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/entity_totals_api.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/list_totals.dart';

final _log = Logger('ListTotalsRepository');

/// `dashboard_cache.kind` of a list's server totals row; the row's
/// `filter_hash` is the [ListTotalsSpec.wireEntity]. A cache kind like the
/// dashboard's own, so no table and no migration: the store's retention and
/// every sign-out wipe already cover it.
const String kListTotalsCacheKind = 'entity_totals';

/// What a list's totals line reads. An interface so the line can be pumped in
/// a widget test without the `Services` graph.
abstract interface class ListTotalsSource {
  /// The per-currency totals behind [type]'s line for [companyId]: null while
  /// unknown (the line hides), empty or all-zero when there is nothing.
  /// Always null for a list with no line ([kListTotals]).
  Stream<CurrencyTotals?> watch(EntityType type, String companyId);

  /// Asks the server again — not at all while the cached answer is younger
  /// than [maxAge], and never where the server has proved it lacks the route.
  Future<void> refresh(EntityType type, String companyId, {Duration? maxAge});

  /// Changes queued or in flight; a drop means one left the outbox, which is
  /// when the server's figure is refetched.
  Stream<int> watchOutboxActive(String companyId);
}

/// Source of truth for the per-currency totals line on every money list
/// (docs/entity-lists.md § A money list's totals line).
///
/// * **Clients and Invoices** read the dashboard's outstanding row
///   (`totals_v2`) — exact, and shared with the dashboard's own figure.
/// * **Every other money list** reads `POST /charts/entity_totals`, cached in
///   `dashboard_cache` under [kListTotalsCacheKind]. A server without the
///   route (404 / 400 / 405) is remembered for the session, per company, and
///   the figure is summed from the rows Drift holds instead
///   (`BaseEntityDao.watchListTotals`) — exact on a small account,
///   under-reporting on a large one until a Sync, like the sidebar counters.
///   So does a fetch that failed with nothing cached (offline), and a 422 (a
///   server that does not know this entity). A 403 — a user whose figure is
///   hidden — draws no line at all.
class ListTotalsRepository implements ListTotalsSource {
  ListTotalsRepository({
    required this.db,
    required this.api,
    required this.dashboard,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final EntityTotalsApi api;
  final DashboardRepository dashboard;
  final int Function() _now;

  /// The company whose token requests go out under — bound by `Services.build`
  /// as the dashboard's is. Null (tests) disables the check; a bound hook
  /// answering null means signed out, and blocks.
  String? Function()? activeCompanyId;

  /// Companies whose server has answered that it has no `entity_totals`
  /// route, this session.
  final Set<String> _unsupported = {};

  /// `company|entity` keys whose last fetch failed with nothing cached: those
  /// lines fall back to the local sum until a fetch succeeds.
  final Set<String> _failed = {};

  /// `company|entity` keys the server refused with a 403 — a user whose
  /// figure is hidden (client balances, say). Their line is not drawn at all:
  /// neither the server's figure nor a local sum of what the user is not
  /// meant to see totalled. Asked again next session.
  final Set<String> _denied = {};

  /// `company|entity` keys the server answered 422 for: a server with the
  /// route that does not know this entity. Summed locally, like a server
  /// without the route, for this list only.
  final Set<String> _unknownEntity = {};

  /// Fetches in flight, by `company|entity`.
  final Map<String, Future<void>> _inFlight = {};

  /// Fires whenever [_unsupported], [_failed], [_denied] or [_unknownEntity]
  /// changes, so a watch re-decides between the server row, the local sum and
  /// nothing.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Forget what this session learned about the server — the next user may
  /// sign in to another one.
  void resetSessionState() {
    _unsupported.clear();
    _failed.clear();
    _denied.clear();
    _unknownEntity.clear();
    _changes.add(null);
  }

  /// Whether [companyId]'s server is known to lack `entity_totals`.
  bool isUnsupported(String companyId) => _unsupported.contains(companyId);

  /// Whether the `company|entity` [key] is summed from Drift for good this
  /// session: [companyId]'s server lacks the route, or this entity.
  bool _answersLocally(String companyId, String key) =>
      _unsupported.contains(companyId) || _unknownEntity.contains(key);

  @override
  Stream<int> watchOutboxActive(String companyId) =>
      db.outboxDao.watchActiveCount(companyId: companyId);

  @override
  Stream<CurrencyTotals?> watch(EntityType type, String companyId) {
    final spec = kListTotals[type];
    if (spec == null) return Stream.value(null);
    if (spec.origin == ListTotalsOrigin.dashboardOutstanding) {
      return dashboard
          .watchOutstanding(companyId, includeDrafts: false)
          .map(outstandingTotalsOf);
    }
    final local = localDaoFor(type)?.watchListTotals(companyId: companyId);
    if (local == null) return Stream.value(null);
    return _watchEntity(spec, companyId, local);
  }

  @override
  Future<void> refresh(
    EntityType type,
    String companyId, {
    Duration? maxAge,
  }) async {
    final spec = kListTotals[type];
    if (spec == null) return;
    if (spec.origin == ListTotalsOrigin.dashboardOutstanding) {
      return dashboard.refreshOutstanding(
        companyId,
        includeDrafts: false,
        maxAge: maxAge,
      );
    }
    final key = '$companyId|${spec.wireEntity}';
    if (_answersLocally(companyId, key) || _denied.contains(key)) return;
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final run = _fetch(spec, companyId, key, maxAge);
    _inFlight[key] = run;
    try {
      await run;
    } finally {
      _inFlight.removeWhere((k, v) => k == key && identical(v, run));
    }
  }

  Future<void> _fetch(
    ListTotalsSpec spec,
    String companyId,
    String key,
    Duration? maxAge,
  ) async {
    final dao = db.dashboardCacheDao;
    if (maxAge != null) {
      final row = await dao.read(
        companyId: companyId,
        kind: kListTotalsCacheKind,
        filterHash: spec.wireEntity,
      );
      if (row != null && _now() - row.fetchedAt < maxAge.inMilliseconds) {
        return;
      }
    }
    _ensureStillActive(companyId);
    final Object? data;
    try {
      data = await api.fetch(spec.wireEntity);
    } on ApiException catch (e) {
      if (isMissingRouteError(e)) {
        _log.info('No entity_totals on this server ($e); summing locally');
        _unsupported.add(companyId);
        _changes.add(null);
        return;
      }
      if (e is ValidationException) {
        _log.info('entity_totals does not know ${spec.wireEntity} ($e)');
        _unknownEntity.add(key);
        _changes.add(null);
        return;
      }
      if (_isDenied(e)) {
        _log.fine('entity_totals refused ${spec.wireEntity} ($e); no line');
        _denied.add(key);
        _changes.add(null);
        return;
      }
      _markFailed(key);
      rethrow;
    } catch (_) {
      _markFailed(key);
      rethrow;
    }
    final totals = parseEntityTotals(data);
    if (totals == null) {
      _markFailed(key);
      throw const FormatException('Unexpected entity_totals answer');
    }
    _ensureStillActive(companyId);
    await dao.upsert(
      companyId: companyId,
      kind: kListTotalsCacheKind,
      filterHash: spec.wireEntity,
      payload: jsonEncode({
        for (final e in totals.entries) e.key: {'amount': e.value.toString()},
      }),
      fetchedAt: _now(),
    );
    if (_failed.remove(key)) _changes.add(null);
  }

  /// A 403 — or a permission denial that arrives as a 401 — but not the
  /// password or plan gates, which carry their own types.
  static bool _isDenied(ApiException e) =>
      e is PermissionDeniedException ||
      (e is ServerException && e.statusCode == 403);

  void _markFailed(String key) {
    if (_failed.add(key)) _changes.add(null);
  }

  void _ensureStillActive(String companyId) {
    final live = activeCompanyId;
    if (live == null) return;
    final active = live();
    if (active == companyId) return;
    throw CompanySwitchedException(
      expected: companyId,
      active: active,
      entityType: 'list totals',
    );
  }

  /// The DAO whose `watchListTotals` sums [type] locally.
  BaseEntityDao<Table, dynamic>? localDaoFor(EntityType type) => switch (type) {
    EntityType.quote => db.quoteDao,
    EntityType.credit => db.creditDao,
    EntityType.payment => db.paymentDao,
    EntityType.recurringInvoice => db.recurringInvoiceDao,
    EntityType.purchaseOrder => db.purchaseOrderDao,
    EntityType.expense => db.expenseDao,
    EntityType.recurringExpense => db.recurringExpenseDao,
    _ => null,
  };

  /// The server row while it is the answer, the local sum while the server
  /// cannot give one, and null (hidden) while the first fetch is still out.
  ///
  /// The local query is subscribed only while it is the answer: it re-runs on
  /// every write to its table, which a Sync makes a page at a time.
  Stream<CurrencyTotals?> _watchEntity(
    ListTotalsSpec spec,
    String companyId,
    Stream<Map<String, Decimal>> local,
  ) {
    final key = '$companyId|${spec.wireEntity}';
    late final StreamController<CurrencyTotals?> out;
    StreamSubscription<Object?>? cacheSub;
    StreamSubscription<Object?>? changesSub;
    StreamSubscription<Object?>? localSub;
    CurrencyTotals? server;
    var serverSeen = false;

    void decide() {
      if (_denied.contains(key)) {
        if (localSub != null) {
          unawaited(localSub!.cancel());
          localSub = null;
        }
        out.add(null);
        return;
      }
      final useLocal =
          _answersLocally(companyId, key) ||
          (serverSeen && server == null && _failed.contains(key));
      if (useLocal) {
        localSub ??= local.listen(out.add, onError: out.addError);
        return;
      }
      if (localSub != null) {
        unawaited(localSub!.cancel());
        localSub = null;
      }
      if (serverSeen) out.add(server);
    }

    out = StreamController<CurrencyTotals?>(
      onListen: () {
        changesSub = _changes.stream.listen((_) => decide());
        cacheSub = db.dashboardCacheDao
            .watch(
              companyId: companyId,
              kind: kListTotalsCacheKind,
              filterHash: spec.wireEntity,
            )
            .distinct()
            .listen((row) {
              serverSeen = true;
              server = _decode(row?.payload);
              decide();
            }, onError: out.addError);
        // A company already known to lack the route answers locally at once,
        // and a refused line stays hidden.
        if (_answersLocally(companyId, key) || _denied.contains(key)) {
          decide();
        }
      },
      onCancel: () async {
        await cacheSub?.cancel();
        await changesSub?.cancel();
        await localSub?.cancel();
      },
    );
    return out.stream.distinct(
      (a, b) => const MapEquality<String, Decimal>().equals(a, b),
    );
  }

  static CurrencyTotals? _decode(String? payload) {
    if (payload == null) return null;
    try {
      return parseEntityTotals(jsonDecode(payload));
    } catch (e) {
      _log.warning('Failed to decode cached list totals', e);
      return null;
    }
  }
}
