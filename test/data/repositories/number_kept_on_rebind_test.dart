import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/repositories/client_repository.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/data/repositories/settings_repository.dart';
import 'package:admin/data/services/clients_api.dart';
import 'package:admin/data/services/invoices_api.dart';

/// A form opened on a record before its create landed holds the blank number
/// the create was sent with. Saved after the create landed, that blank made
/// the server store nothing and then take the NEXT number from the counter
/// (`ApplyNumber::run`, `counter_number_applied` = `when_saved`), skipping the
/// one the create got. A save rebound from the `tmp_` id now keeps the stored
/// number (docs/after-saving.md).
class _FakeInvoicesApi implements InvoicesApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeClientsApi implements ClientsApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, dynamic>> lastPayload() async {
    final rows = await db.outboxDao.nextReady(companyId: 'co', now: 1 << 60);
    return jsonDecode(rows.last.payload) as Map<String, dynamic>;
  }

  group('an invoice', () {
    late InvoiceRepository repo;

    setUp(() {
      repo = InvoiceRepository(
        db: db,
        api: _FakeInvoicesApi(),
        settings: SettingsRepository(db: db),
      );
    });

    test('saved under its tmp_ id after the create landed keeps the number '
        'the create got', () async {
      final created = await repo.create(
        companyId: 'co',
        draft: Invoice.fromApi(const InvoiceApi(id: '', number: '')),
      );
      final tmpId = created.entity.id;
      await repo.applyCreateResponse(
        companyId: 'co',
        tempId: tmpId,
        serverResponse: const InvoiceApi(id: 'inv_1', number: '0042'),
      );

      // The form still holds the draft it opened with.
      final saved = await repo.save(
        companyId: 'co',
        invoice: created.entity.copyWith(poNumber: 'PO-7'),
      );

      expect(saved.entity.id, 'inv_1');
      expect(saved.entity.number, '0042');
      final payload = await lastPayload();
      expect(payload['id'], 'inv_1');
      expect(payload['number'], '0042');
    });

    test('an update queued before the create landed drops its blank number '
        'when the create lands, so the server keeps the one it gave', () async {
      final created = await repo.create(
        companyId: 'co',
        draft: Invoice.fromApi(const InvoiceApi(id: '', number: '')),
      );
      final tmpId = created.entity.id;
      // Offline, the form stays open on the tmp_ record and saves again.
      await repo.save(
        companyId: 'co',
        invoice: created.entity.copyWith(poNumber: 'PO-8'),
      );

      await repo.applyCreateResponse(
        companyId: 'co',
        tempId: tmpId,
        serverResponse: const InvoiceApi(id: 'inv_9', number: '0044'),
      );

      final rows = await db.outboxDao.nextReady(companyId: 'co', now: 1 << 60);
      final update = rows.singleWhere((r) => r.mutationKind == 'update');
      expect(update.entityId, 'inv_9');
      final payload = jsonDecode(update.payload) as Map<String, dynamic>;
      expect(payload['id'], 'inv_9');
      expect(payload['po_number'], 'PO-8');
      expect(payload.containsKey('number'), isFalse);
    });

    test('a number the user cleared on a saved invoice is sent blank — the '
        'server gives it a new one', () async {
      await repo.applyCreateResponse(
        companyId: 'co',
        tempId: 'inv_2',
        serverResponse: const InvoiceApi(id: 'inv_2', number: '0043'),
      );
      final loaded = await repo.watch(companyId: 'co', id: 'inv_2').first;

      final saved = await repo.save(
        companyId: 'co',
        invoice: loaded!.copyWith(number: ''),
      );

      expect(saved.entity.number, '');
      expect((await lastPayload())['number'], '');
    });
  });

  test('a client keeps its number the same way', () async {
    final repo = ClientRepository(db: db, api: _FakeClientsApi());
    final created = await repo.create(
      companyId: 'co',
      draft: Client.fromApi(const ClientApi(id: '', name: 'Acme')),
    );
    await repo.applyCreateResponse(
      companyId: 'co',
      tempId: created.entity.id,
      serverResponse: const ClientApi(id: 'cl_1', name: 'Acme', number: '7'),
    );

    final saved = await repo.save(companyId: 'co', client: created.entity);

    expect(saved.entity.id, 'cl_1');
    expect(saved.entity.number, '7');
  });
}
