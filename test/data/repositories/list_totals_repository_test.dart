import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/data/repositories/list_totals_repository.dart';
import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/dashboard_api.dart';
import 'package:admin/data/services/entity_totals_api.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/domain/entity_type.dart';

/// The server half of a money list's totals line (docs/entity-lists.md § A
/// money list's totals line): `charts/entity_totals` where the server has it,
/// cached in `dashboard_cache`; the Drift sum where it answers 404 / 400 /
/// 405 (remembered for the session) or a fetch fails with nothing cached.

final ApiClient _dummyClient = ApiClient(
  credentials: ValueNotifier<ApiCredentials?>(
    const ApiCredentials(baseUrl: 'https://test', token: 't'),
  ),
  passwordCache: PasswordCache(),
  onUnauthorized: () async {},
);

class _FakeTotalsApi extends EntityTotalsApi {
  _FakeTotalsApi() : super(_dummyClient);

  /// What the next fetch answers, or throws when it is an exception.
  Object? answer;
  final List<String> asked = [];

  @override
  Future<Object?> fetch(String entity) async {
    asked.add(entity);
    await Future<void>.delayed(Duration.zero);
    final a = answer;
    if (a is Exception) throw a;
    return a;
  }
}

class _FakeDashboardApi extends DashboardApi {
  _FakeDashboardApi() : super(_dummyClient);

  int outstandingCalls = 0;

  @override
  Future<Object?> fetchOutstandingTotals({required bool includeDrafts}) async {
    outstandingCalls++;
    return {
      '1': {
        'outstanding': {'amount': '12.50', 'code': 'USD'},
      },
      '999': {
        'outstanding': {'amount': '99', 'code': 'USD'},
      },
    };
  }
}

void main() {
  late AppDatabase db;
  late _FakeTotalsApi api;
  late _FakeDashboardApi dashboardApi;
  late ListTotalsRepository repo;
  var now = 1000000;

  const co = 'co';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = _FakeTotalsApi();
    dashboardApi = _FakeDashboardApi();
    now = 1000000;
    repo = ListTotalsRepository(
      db: db,
      api: api,
      dashboard: DashboardRepository(db: db, api: dashboardApi),
      now: () => now,
    );
  });
  tearDown(() => db.close());

  Map<String, Decimal> dec(Map<String, String> m) => {
    for (final e in m.entries) e.key: Decimal.parse(e.value),
  };

  /// One approved quote worth 7 in the company's currency — what the local
  /// sum finds.
  Future<void> seedQuote() => db.quoteDao.upsert(
    QuotesCompanion.insert(
      id: 'q1',
      companyId: co,
      updatedAt: 1,
      payload: '{}',
      statusId: const Value('3'),
      amount: const Value('7'),
    ),
  );

  /// Every value [stream] emits, for as long as the test runs.
  List<Map<String, Decimal>?> record(Stream<Map<String, Decimal>?> stream) {
    final seen = <Map<String, Decimal>?>[];
    final sub = stream.listen(seen.add);
    addTearDown(sub.cancel);
    return seen;
  }

  test('a server with the route: its figure is cached and shown, never the '
      'local sum', () async {
    await seedQuote();
    api.answer = {
      '1': {'amount': '123.45', 'count': 3},
      '2': {'amount': 6, 'count': 1},
    };
    final seen = record(repo.watch(EntityType.quote, co));
    await pumpEventQueue();
    // Nothing cached and the first fetch not yet out: hidden, not local.
    expect(seen.whereType<Map<String, Decimal>>(), isEmpty);

    await repo.refresh(EntityType.quote, co);
    await pumpEventQueue();
    expect(api.asked, ['quotes']);
    expect(seen.last, dec({'1': '123.45', '2': '6'}));

    final row = await db.dashboardCacheDao.read(
      companyId: co,
      kind: kListTotalsCacheKind,
      filterHash: 'quotes',
    );
    expect(row, isNotNull);
  });

  test('a cached answer younger than maxAge is not asked again; an older one '
      'is', () async {
    api.answer = {
      '1': {'amount': '1', 'count': 1},
    };
    await repo.refresh(EntityType.credit, co);
    await repo.refresh(
      EntityType.credit,
      co,
      maxAge: const Duration(minutes: 5),
    );
    expect(api.asked, ['credits']);

    now += const Duration(minutes: 6).inMilliseconds;
    await repo.refresh(
      EntityType.credit,
      co,
      maxAge: const Duration(minutes: 5),
    );
    expect(api.asked, ['credits', 'credits']);
  });

  for (final status in [404, 400, 405]) {
    test('a $status is "no such route": remembered for the session, and the '
        'line sums Drift instead', () async {
      await seedQuote();
      api.answer = ServerException(status, 'Route does not exist');
      final seen = record(repo.watch(EntityType.quote, co));

      await repo.refresh(EntityType.quote, co);
      await pumpEventQueue();
      expect(repo.isUnsupported(co), isTrue);
      expect(seen.last, dec({'': '7'}));

      // Once per company per session: no list asks again.
      await repo.refresh(EntityType.payment, co);
      await repo.refresh(EntityType.quote, co);
      expect(api.asked, ['quotes']);

      // A line opened later answers locally at once.
      final later = record(repo.watch(EntityType.quote, co));
      await pumpEventQueue();
      expect(later.last, dec({'': '7'}));

      // A sign-out forgets it.
      repo.resetSessionState();
      await repo.refresh(EntityType.quote, co);
      expect(api.asked, ['quotes', 'quotes']);
    });
  }

  test('a failed fetch with nothing cached falls back to the local sum, '
      'and a later success replaces it', () async {
    await seedQuote();
    api.answer = const NetworkException('offline');
    final seen = record(repo.watch(EntityType.quote, co));

    await expectLater(
      repo.refresh(EntityType.quote, co),
      throwsA(isA<NetworkException>()),
    );
    await pumpEventQueue();
    expect(repo.isUnsupported(co), isFalse);
    expect(seen.last, dec({'': '7'}));

    api.answer = {
      '3': {'amount': '40', 'count': 2},
    };
    await repo.refresh(EntityType.quote, co);
    await pumpEventQueue();
    expect(seen.last, dec({'3': '40'}));
  });

  test('a 403 — a user whose figure is hidden — draws no line at all: not '
      'the server\'s, not a local sum, and it is not asked again', () async {
    await seedQuote();
    api.answer = const ServerException(403, 'This action is unauthorized.');
    final seen = record(repo.watch(EntityType.quote, co));
    await repo.refresh(EntityType.quote, co);
    await pumpEventQueue();
    expect(repo.isUnsupported(co), isFalse);
    expect(seen, isNotEmpty);
    expect(seen.whereType<Map<String, Decimal>>(), isEmpty);
    await repo.refresh(EntityType.quote, co);
    expect(api.asked, ['quotes']);

    // Another list of the same company still asks.
    api.answer = {
      '1': {'amount': '1', 'count': 1},
    };
    await repo.refresh(EntityType.credit, co);
    expect(api.asked, ['quotes', 'credits']);
  });

  test('a 422 — a server that does not know this entity — sums that list '
      'locally and leaves the others on the server', () async {
    await seedQuote();
    api.answer = const ValidationException('The selected entity is invalid.', {
      'entity': ['The selected entity is invalid.'],
    });
    final seen = record(repo.watch(EntityType.quote, co));
    await repo.refresh(EntityType.quote, co);
    await pumpEventQueue();
    expect(repo.isUnsupported(co), isFalse);
    expect(seen.last, dec({'': '7'}));
    await repo.refresh(EntityType.quote, co);
    expect(api.asked, ['quotes']);
    await repo.refresh(EntityType.credit, co);
    expect(api.asked, ['quotes', 'credits']);
  });

  test(
    'the server\'s empty answer `{"data": {}}` is nothing, not unknown',
    () async {
      api.answer = <String, Object?>{};
      final seen = record(repo.watch(EntityType.payment, co));
      await repo.refresh(EntityType.payment, co);
      await pumpEventQueue();
      expect(seen.last, isEmpty);
    },
  );

  test('a failed refresh keeps the cached server figure', () async {
    await seedQuote();
    api.answer = {
      '1': {'amount': '5', 'count': 1},
    };
    await repo.refresh(EntityType.quote, co);
    final seen = record(repo.watch(EntityType.quote, co));
    await pumpEventQueue();
    expect(seen.last, dec({'1': '5'}));

    api.answer = const NetworkException('offline');
    await expectLater(
      repo.refresh(EntityType.quote, co),
      throwsA(isA<NetworkException>()),
    );
    await pumpEventQueue();
    expect(seen.last, dec({'1': '5'}));
  });

  test('an empty answer is "nothing", not unknown', () async {
    api.answer = <Object?>[];
    final seen = record(repo.watch(EntityType.expense, co));
    await repo.refresh(EntityType.expense, co);
    await pumpEventQueue();
    expect(seen.last, isEmpty);
  });

  test('Clients and Invoices keep the dashboard\'s totals_v2 row and never '
      'ask entity_totals', () async {
    final seen = record(repo.watch(EntityType.invoice, co));
    await repo.refresh(EntityType.invoice, co);
    await repo.refresh(EntityType.client, co);
    await pumpEventQueue();
    expect(api.asked, isEmpty);
    expect(dashboardApi.outstandingCalls, greaterThanOrEqualTo(1));
    // The 999 aggregate is dropped here already.
    expect(seen.last, dec({'1': '12.50'}));
  });

  test('a list with no line is null and asks nothing', () async {
    expect(await repo.watch(EntityType.vendor, co).first, isNull);
    await repo.refresh(EntityType.product, co);
    expect(api.asked, isEmpty);
  });

  test('a company switch under the fetch writes nothing', () async {
    String? active = co;
    repo.activeCompanyId = () => active;
    api.answer = {
      '1': {'amount': '5', 'count': 1},
    };
    final run = repo.refresh(EntityType.quote, co);
    active = 'other';
    await expectLater(run, throwsA(anything));
    final row = await db.dashboardCacheDao.read(
      companyId: co,
      kind: kListTotalsCacheKind,
      filterHash: 'quotes',
    );
    expect(row, isNull);
  });
}
