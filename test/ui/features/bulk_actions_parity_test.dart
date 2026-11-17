// The list bulk actions added in the bulk-action parity review
// (docs/bulk-actions.md): each one's eligibility mirrors its single-record
// twin, each queues one outbox row per selected record carrying what the
// server reads, the field-setting ones show the new value locally at once
// (no network: this is what an offline user sees), and the risky ones are
// `confirm: true` with no prep dialog in front (CLAUDE.md § Action
// confirmations). Permission: every list bulk item is gated on
// `edit_<entity>` by `EntityListScreenScaffold`, which only holds for an
// entity in `kPermissionEntities` — asserted here for each one.

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/credit_api_model.dart';
import 'package:admin/data/models/api/expense_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/api/product_api_model.dart';
import 'package:admin/data/models/api/quote_api_model.dart';
import 'package:admin/data/models/domain/credit.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/quote.dart';
import 'package:admin/data/repositories/client_repository.dart';
import 'package:admin/data/repositories/credit_repository.dart';
import 'package:admin/data/repositories/expense_repository.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/data/repositories/payment_repository.dart';
import 'package:admin/data/repositories/product_repository.dart';
import 'package:admin/data/repositories/quote_repository.dart';
import 'package:admin/data/repositories/recurring_invoice_repository.dart';
import 'package:admin/data/repositories/settings_repository.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/data/services/clients_api.dart';
import 'package:admin/data/services/credits_api.dart';
import 'package:admin/data/services/expenses_api.dart';
import 'package:admin/data/services/invoices_api.dart';
import 'package:admin/data/services/payments_api.dart';
import 'package:admin/data/services/products_api.dart';
import 'package:admin/data/services/quotes_api.dart';
import 'package:admin/data/services/recurring_invoices_api.dart';
import 'package:admin/domain/permissions.dart';
import 'package:admin/domain/sync/mutation.dart';
import 'package:admin/ui/features/clients/view_models/client_list_view_model.dart';
import 'package:admin/ui/features/credits/view_models/credit_list_view_model.dart';
import 'package:admin/ui/features/expenses/view_models/expense_list_view_model.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_list_view_model.dart';
import 'package:admin/ui/features/payments/view_models/payment_list_view_model.dart';
import 'package:admin/ui/features/products/view_models/product_list_view_model.dart';
import 'package:admin/ui/features/quotes/view_models/quote_list_view_model.dart';
import 'package:admin/ui/features/recurring_invoices/view_models/recurring_invoice_list_view_model.dart';

/// Every API here throws: nothing in these tests may reach the network.
class _NoClientsApi implements ClientsApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoProductsApi implements ProductsApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoExpensesApi implements ExpensesApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoInvoicesApi implements InvoicesApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoQuotesApi implements QuotesApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoCreditsApi implements CreditsApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoPaymentsApi implements PaymentsApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _NoRecurringInvoicesApi implements RecurringInvoicesApi {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('network: ${i.memberName}');
}

class _UnusedSettings implements SettingsRepository {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}

void main() {
  late AppDatabase db;
  late UserSettingsRepository userSettings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    userSettings = UserSettingsRepository(db: db);
  });
  tearDown(() async => db.close());

  /// `[kind, payload]` per pending row — lists, so `expect` compares deeply.
  Future<List<List<Object?>>> queued() async => [
    for (final r in await db.outboxDao.pendingRowsForCompany('co'))
      [r.mutationKind, jsonDecode(r.payload)],
  ];

  group('field-setting actions write locally, then queue one row each', () {
    test('expenses: Change Category', () async {
      final repo = ExpenseRepository(db: db, api: _NoExpensesApi());
      await repo.applyUpdateResponse(
        companyId: 'co',
        serverResponse: const ExpenseApi(id: 'e1', categoryId: 'old'),
      );
      final vm = ExpenseListViewModel(
        repo: repo,
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: userSettings,
      );
      addTearDown(vm.dispose);

      final r = await vm.applyBulkAction(
        vm.bulkActionById('bulk_categorize')!,
        ids: {'e1'},
        arg: 'c9',
      );

      expect(r.ok, 1);
      expect(await queued(), [
        [
          'bulk_categorize',
          {'id': 'e1', 'category_id': 'c9'},
        ],
      ]);
      final local = await repo.watch(companyId: 'co', id: 'e1').first;
      expect(local!.categoryId, 'c9');
      expect(local.isDirty, isTrue);
    });

    test('clients: Assign Group', () async {
      final repo = ClientRepository(db: db, api: _NoClientsApi());
      await repo.applyUpdateResponse(
        companyId: 'co',
        serverResponse: const ClientApi(id: 'c1', name: 'Acme'),
      );
      final vm = ClientListViewModel(
        repo: repo,
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: userSettings,
      );
      addTearDown(vm.dispose);

      final r = await vm.applyBulkAction(
        vm.bulkActionById('assign_group')!,
        ids: {'c1'},
        arg: 'g7',
      );

      expect(r.ok, 1);
      expect(await queued(), [
        [
          'assign_group',
          {'id': 'c1', 'group_settings_id': 'g7'},
        ],
      ]);
      final local = await repo.watch(companyId: 'co', id: 'c1').first;
      expect(local!.groupSettingsId, 'g7');
      expect(local.isDirty, isTrue);
      await expectLater(
        repo.assignGroup(companyId: 'co', client: local, groupId: ''),
        throwsArgumentError,
        reason: 'the server requires a group',
      );
    });

    test('products: Set Tax Category', () async {
      final repo = ProductRepository(db: db, api: _NoProductsApi());
      await repo.applyUpdateResponse(
        companyId: 'co',
        serverResponse: const ProductApi(id: 'p1', productKey: 'Widget'),
      );
      final vm = ProductListViewModel(
        repo: repo,
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: userSettings,
      );
      addTearDown(vm.dispose);

      final r = await vm.applyBulkAction(
        vm.bulkActionById('set_tax_category')!,
        ids: {'p1'},
        arg: '5',
      );

      expect(r.ok, 1);
      expect(await queued(), [
        [
          'set_tax_id',
          {'id': 'p1', 'tax_id': '5'},
        ],
      ]);
      final local = await repo.watch(companyId: 'co', id: 'p1').first;
      expect(local!.taxId, '5');
      expect(local.isDirty, isTrue);
    });

    test('the three new kinds are safe to replay (absolute values)', () {
      for (final k in [
        MutationKind.bulkCategorize,
        MutationKind.assignGroup,
        MutationKind.setTaxId,
      ]) {
        expect(MutationKind.tryParse(k.wireName), k);
        expect(k.deliverySafety, DeliverySafety.idempotent);
      }
    });
  });

  group('state actions mirror the single-record gate and queue the kind', () {
    test('invoices: Cancel — sent or partial, never paid or unsaved', () async {
      final vm = InvoiceListViewModel(
        repo: InvoiceRepository(
          db: db,
          api: _NoInvoicesApi(),
          settings: _UnusedSettings(),
        ),
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: userSettings,
      );
      addTearDown(vm.dispose);
      final cancel = vm.bulkActionById('cancel')!;
      Invoice inv(String status, {String id = 'i1'}) =>
          Invoice.fromApi(InvoiceApi(id: id, statusId: status));

      expect(cancel.confirm, isTrue);
      expect(cancel.eligible(inv('2')), isTrue, reason: 'sent');
      expect(cancel.eligible(inv('3')), isTrue, reason: 'partial');
      expect(cancel.eligible(inv('1')), isFalse, reason: 'draft');
      expect(cancel.eligible(inv('4')), isFalse, reason: 'paid');
      expect(cancel.eligible(inv('5')), isFalse, reason: 'cancelled');
      expect(cancel.eligible(inv('2', id: 'tmp_x')), isFalse, reason: 'tmp');

      await vm.applyBulkAction(cancel, ids: {'i1'});
      expect(await queued(), [
        [
          MutationKind.cancelEntity.wireName,
          {'id': 'i1'},
        ],
      ]);
    });

    test('quotes: Convert to Project — once, from a saved quote', () async {
      final vm = QuoteListViewModel(
        repo: QuoteRepository(db: db, api: _NoQuotesApi()),
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: userSettings,
      );
      addTearDown(vm.dispose);
      final convert = vm.bulkActionById('convert_to_project')!;
      Quote quote({String id = 'q1', String projectId = ''}) =>
          Quote.fromApi(QuoteApi(id: id, statusId: '2', projectId: projectId));

      expect(convert.confirm, isTrue);
      expect(convert.eligible(quote()), isTrue);
      expect(convert.eligible(quote(projectId: 'p1')), isFalse);
      expect(convert.eligible(quote(id: 'tmp_x')), isFalse);

      await vm.applyBulkAction(convert, ids: {'q1'});
      expect(await queued(), [
        [
          MutationKind.convertToProject.wireName,
          {'id': 'q1'},
        ],
      ]);
    });

    test('credits: Mark Paid — only a negative credit', () async {
      final vm = CreditListViewModel(
        repo: CreditRepository(db: db, api: _NoCreditsApi()),
        companyId: 'co',
        navStateDao: db.navStateDao,
        userSettings: userSettings,
      );
      addTearDown(vm.dispose);
      final markPaid = vm.bulkActionById('mark_paid')!;
      Credit credit(String amount, {String status = '2'}) => Credit.fromApi(
        CreditApi(id: 'cr1', statusId: status),
      ).copyWith(amount: Decimal.parse(amount));

      expect(markPaid.confirm, isTrue);
      expect(markPaid.eligible(credit('-10')), isTrue);
      expect(markPaid.eligible(credit('10')), isFalse);
      expect(markPaid.eligible(credit('-10', status: '4')), isFalse);

      await vm.applyBulkAction(markPaid, ids: {'cr1'});
      expect(await queued(), [
        [
          MutationKind.markPaid.wireName,
          {'id': 'cr1'},
        ],
      ]);
    });

    test(
      'payments: Send Email — the receipt, through the bulk route',
      () async {
        final vm = PaymentListViewModel(
          repo: PaymentRepository(db: db, api: _NoPaymentsApi()),
          companyId: 'co',
          navStateDao: db.navStateDao,
          userSettings: userSettings,
        );
        addTearDown(vm.dispose);
        final email = vm.bulkActionById('email')!;

        expect(email.confirm, isTrue);
        await vm.applyBulkAction(email, ids: {'pay1'});
        expect(await queued(), [
          [
            MutationKind.emailEntity.wireName,
            {'id': 'pay1'},
          ],
        ]);
      },
    );
  });

  test('recurring invoices offer no Run Template — the server has no '
      'template action there, so every row dead-lettered', () {
    final vm = RecurringInvoiceListViewModel(
      repo: RecurringInvoiceRepository(db: db, api: _NoRecurringInvoicesApi()),
      companyId: 'co',
      navStateDao: db.navStateDao,
      userSettings: userSettings,
    );
    addTearDown(vm.dispose);
    expect(vm.bulkActionById('run_template'), isNull);
  });

  test('every entity that gained a bulk action is permission-gated', () {
    for (final e in const [
      'client',
      'product',
      'expense',
      'invoice',
      'quote',
      'credit',
      'payment',
    ]) {
      expect(kPermissionEntities, contains(e));
    }
  });
}
