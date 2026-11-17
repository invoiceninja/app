// The expense list's Change Category bulk action (`bulk_categorize`): the
// local write shows the new category at once (offline too), each selected
// expense queues one outbox row carrying exactly what the server reads, the
// echo clears the dirty flag, and a rejection surfaces to the sync engine.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/app/services_entity_wiring.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/expense_api_model.dart';
import 'package:admin/data/models/domain/expense.dart';
import 'package:admin/data/repositories/expense_repository.dart';
import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/expenses_api.dart';
import 'package:admin/data/services/password_cache.dart';
import 'package:admin/domain/sync/base_entity_sync_dispatcher.dart';
import 'package:admin/domain/sync/mutation.dart';

/// An [ExpensesApi] over a fake HTTP client that records each request body
/// and answers with [status] / [body].
({ExpensesApi api, List<Map<String, dynamic>> bodies, List<Uri> urls}) _api({
  int status = 200,
  Object? body,
}) {
  final bodies = <Map<String, dynamic>>[];
  final urls = <Uri>[];
  final client = MockClient((req) async {
    urls.add(req.url);
    bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
    return http.Response(
      jsonEncode(body ?? const {'data': <Object>[]}),
      status,
      headers: const {'content-type': 'application/json'},
    );
  });
  return (
    api: ExpensesApi(
      ApiClient(
        credentials: ValueNotifier<ApiCredentials?>(
          const ApiCredentials(baseUrl: 'https://test', token: 't'),
        ),
        passwordCache: PasswordCache(),
        onUnauthorized: () async {},
        httpClient: client,
      ),
    ),
    bodies: bodies,
    urls: urls,
  );
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<Expense> seed(ExpenseRepository repo, String id) async {
    await repo.applyUpdateResponse(
      companyId: 'co',
      serverResponse: ExpenseApi(id: id, categoryId: 'old'),
    );
    return (await repo.watch(companyId: 'co', id: id).first)!;
  }

  Future<OutboxRow> onlyRowFor(String id) async {
    final rows = await db.outboxDao.pendingRowsForCompany('co');
    return rows.singleWhere((r) => r.entityId == id);
  }

  test('writes the category locally (dirty) and queues one row per expense '
      'with the payload the server reads', () async {
    final repo = ExpenseRepository(db: db, api: _api().api);
    final e1 = await seed(repo, 'e1');
    final e2 = await seed(repo, 'e2');

    // No network involved: this is what an offline user sees immediately.
    await repo.bulkCategorize(companyId: 'co', expense: e1, categoryId: 'c9');
    await repo.bulkCategorize(companyId: 'co', expense: e2, categoryId: 'c9');

    for (final id in ['e1', 'e2']) {
      final local = await repo.watch(companyId: 'co', id: id).first;
      expect(local!.categoryId, 'c9');
      expect(local.isDirty, isTrue);
    }

    final rows = await db.outboxDao.pendingRowsForCompany('co');
    expect(rows, hasLength(2));
    for (final r in rows) {
      expect(r.mutationKind, MutationKind.bulkCategorize.wireName);
      expect(r.entityType, 'expense');
      expect(jsonDecode(r.payload), {'id': r.entityId, 'category_id': 'c9'});
      expect(r.idempotencyKey, isNotEmpty);
    }
    // Each row owns its key, minted once at enqueue time.
    expect(rows.map((r) => r.idempotencyKey).toSet(), hasLength(2));
  });

  test('an empty category is refused and queues nothing — the server '
      'categorize() takes an int and would 500', () async {
    final repo = ExpenseRepository(db: db, api: _api().api);
    final e1 = await seed(repo, 'e1');

    await expectLater(
      repo.bulkCategorize(companyId: 'co', expense: e1, categoryId: ''),
      throwsArgumentError,
    );

    expect(await db.outboxDao.pendingRowsForCompany('co'), isEmpty);
    final local = await repo.watch(companyId: 'co', id: 'e1').first;
    expect(local!.categoryId, 'old');
    expect(local.isDirty, isFalse);
  });

  test('the wire kind round-trips and a replay is safe', () {
    expect(MutationKind.bulkCategorize.wireName, 'bulk_categorize');
    expect(
      MutationKind.tryParse('bulk_categorize'),
      MutationKind.bulkCategorize,
    );
    expect(
      MutationKind.bulkCategorize.deliverySafety,
      DeliverySafety.idempotent,
    );
  });

  group('drain', () {
    Future<
      ({
        BaseEntitySyncDispatcher<ExpenseItemApi, ExpenseApi> dispatcher,
        ExpenseRepository repo,
        List<Map<String, dynamic>> bodies,
        List<Uri> urls,
      })
    >
    wired({int status = 200, Object? body}) async {
      final fake = _api(status: status, body: body);
      final repo = ExpenseRepository(db: db, api: fake.api);
      final dispatcher = BaseEntitySyncDispatcher<ExpenseItemApi, ExpenseApi>(
        api: fake.api,
        repo: repo,
        dataOf: (item) => item.data,
        customActions: {
          MutationKind.bulkCategorize:
              bulkActionHandler<ExpenseItemApi, ExpenseApi>(
                fake.api,
                (item) => item.data,
                repo.clearLocalDirty,
                action: 'bulk_categorize',
                extraKeys: const ['category_id'],
              ),
        },
      );
      return (
        dispatcher: dispatcher,
        repo: repo,
        bodies: fake.bodies,
        urls: fake.urls,
      );
    }

    test('posts {action: bulk_categorize, ids, category_id} to '
        '/expenses/bulk and the echo clears the dirty flag', () async {
      final w = await wired(
        body: {
          'data': [
            {'id': 'e1', 'category_id': 'c9'},
          ],
        },
      );
      final e1 = await seed(w.repo, 'e1');
      await w.repo.bulkCategorize(
        companyId: 'co',
        expense: e1,
        categoryId: 'c9',
      );
      final row = await onlyRowFor('e1');

      await w.dispatcher.dispatch(row: row, kind: MutationKind.bulkCategorize);

      expect(w.urls.single.path, endsWith('/api/v1/expenses/bulk'));
      expect(w.bodies.single, {
        'action': 'bulk_categorize',
        'ids': ['e1'],
        'category_id': 'c9',
      });
      final local = await w.repo.watch(companyId: 'co', id: 'e1').first;
      expect(local!.categoryId, 'c9');
      expect(local.isDirty, isFalse);
    });

    test('a null echo (row gone server-side) still clears the dirty flag, so '
        'the next refresh can correct it', () async {
      final w = await wired(body: const {'data': <Object>[]});
      final e1 = await seed(w.repo, 'e1');
      await w.repo.bulkCategorize(
        companyId: 'co',
        expense: e1,
        categoryId: 'c9',
      );

      await w.dispatcher.dispatch(
        row: await onlyRowFor('e1'),
        kind: MutationKind.bulkCategorize,
      );

      final local = await w.repo.watch(companyId: 'co', id: 'e1').first;
      expect(local!.isDirty, isFalse);
    });

    test('a 422 (category gone) reaches the sync engine as a validation '
        'error and leaves the row for it to dead-letter', () async {
      final w = await wired(
        status: 422,
        body: const {
          'message': 'The given data was invalid.',
          'errors': {
            'category_id': ['The selected category id is invalid.'],
          },
        },
      );
      final e1 = await seed(w.repo, 'e1');
      await w.repo.bulkCategorize(
        companyId: 'co',
        expense: e1,
        categoryId: 'c9',
      );

      await expectLater(
        w.dispatcher.dispatch(
          row: await onlyRowFor('e1'),
          kind: MutationKind.bulkCategorize,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
