import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/payment_status.dart';
import 'package:admin/domain/recurring_expense_status.dart';

/// The local half of a money list's totals line (docs/entity-lists.md § A
/// money list's totals line): each DAO's `listTotalsQuery`, run by
/// `BaseEntityDao.watchListTotals` over a seeded store holding the rows that
/// count beside the ones that must not — archived, deleted, another company's,
/// the wrong status, a deleted client's — in several currencies.
///
/// `''` keys the company's currency: a record whose party names none.
/// An expense payload's taxes, each worth 100 on the amounts the tests use:
/// 80 at a named 25%, 90 plus 10 stored by amount, and 100 with its 10%
/// inside it.
const _exclusiveRate = <String, Object>{
  'uses_inclusive_taxes': false,
  'tax_name1': 'VAT',
  'tax_rate1': 25,
};
const _byAmount = <String, Object>{
  'uses_inclusive_taxes': false,
  'calculate_tax_by_amount': true,
  'tax_amount1': 10,
};
const _inclusiveRate = <String, Object>{
  'uses_inclusive_taxes': true,
  'tax_name1': 'VAT',
  'tax_rate1': 10,
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const co = 'co';
  const other = 'co-other';
  final past = Date.today().addDays(-2).toIso();
  final future = Date.today().addDays(2).toIso();

  Map<String, Decimal> dec(Map<String, String> m) => {
    for (final e in m.entries) e.key: Decimal.parse(e.value),
  };

  Future<Map<String, Decimal>> local(
    Stream<Map<String, Decimal>>? Function() watch,
  ) => watch()!.first;

  // Parties: a client in EUR ('3'), one inheriting GBP ('2') from its group,
  // one naming nothing (the company's), a deleted and an archived one in EUR
  // (whose records never count — the server's `without_deleted_clients`); a
  // vendor in GBP, one naming nothing, and a deleted and an archived one in GBP
  // (`without_deleted_vendors`).
  Future<void> client(
    String id, {
    Map<String, Object?> settings = const {},
    String? group,
    bool deleted = false,
    int? archivedAt,
    String company = co,
  }) => db.clientDao.upsert(
    ClientsCompanion.insert(
      id: id,
      companyId: company,
      updatedAt: 1,
      payload: jsonEncode({'id': id, 'settings': settings}),
      name: id,
      number: id,
      email: '',
      displayName: id,
      balance: '0',
      groupSettingsId: Value(group),
      isDeleted: Value(deleted),
      archivedAt: Value(archivedAt),
    ),
  );

  Future<void> vendor(
    String id,
    String currencyId, {
    bool deleted = false,
    int? archivedAt,
  }) => db.vendorDao.upsert(
    VendorsCompanion.insert(
      id: id,
      companyId: co,
      updatedAt: 1,
      payload: '{}',
      name: id,
      number: id,
      idNumber: '',
      vatNumber: '',
      city: '',
      countryId: '',
      currencyId: currencyId,
      phone: '',
      displayName: id,
      isDeleted: Value(deleted),
      archivedAt: Value(archivedAt),
    ),
  );

  Future<void> parties() async {
    await client('c-eur', settings: {'currency_id': '3'});
    await client('c-grp', group: 'g-gbp');
    await client('c-none');
    await client('c-gone', settings: {'currency_id': '3'}, deleted: true);
    await client('c-shelved', settings: {'currency_id': '3'}, archivedAt: 5);
    await db.groupSettingDao.upsert(
      GroupSettingsCompanion.insert(
        id: 'g-gbp',
        companyId: co,
        name: 'UK',
        updatedAt: 1,
        payload: jsonEncode({
          'id': 'g-gbp',
          'settings': {'currency_id': '2'},
        }),
      ),
    );
    await vendor('v-gbp', '2');
    await vendor('v-none', '');
    await vendor('v-gone', '2', deleted: true);
    await vendor('v-shelved', '2', archivedAt: 5);
  }

  test(
    'quotes: open = sent or approved, unexpired (approved ones expire '
    'too), never converted; summed by amount in the client\'s currency',
    () async {
      await parties();
      Future<void> quote(
        String id, {
        required String status,
        String amount = '1000',
        String client = 'c-eur',
        String dueDate = '',
        String invoiceId = '',
        int? archivedAt,
        bool deleted = false,
        String company = co,
      }) => db.quoteDao.upsert(
        QuotesCompanion.insert(
          id: id,
          companyId: company,
          updatedAt: 1,
          payload: '{}',
          statusId: Value(status),
          amount: Value(amount),
          clientId: Value(client),
          dueDate: Value(dueDate),
          invoiceId: Value(invoiceId),
          archivedAt: Value(archivedAt),
          isDeleted: Value(deleted),
        ),
      );
      await quote('q-sent', status: '2', amount: '100.10', dueDate: future);
      await quote('q-sent-2', status: '2', amount: '0.2', dueDate: future);
      await quote('q-sent-nodue', status: '2', amount: '10', client: 'c-none');
      await quote('q-approved', status: '3', amount: '50', client: 'c-grp');
      // Approved quotes expire too (the server's rule).
      await quote('q-approved-old', status: '3', amount: '1', dueDate: past);
      await quote('q-approved-due', status: '3', amount: '2', dueDate: future);
      await quote('q-expired', status: '2', dueDate: past);
      await quote('q-converted', status: '3', invoiceId: 'inv-1');
      await quote('q-status-4', status: '4');
      await quote('q-draft', status: '1');
      await quote('q-rejected', status: '5');
      await quote('q-archived', status: '2', archivedAt: 5);
      await quote('q-deleted', status: '2', deleted: true);
      await quote('q-gone-client', status: '2', client: 'c-gone');
      await quote('q-shelved-client', status: '2', client: 'c-shelved');
      await quote('q-other', status: '2', company: other);

      expect(
        await local(() => db.quoteDao.watchListTotals(companyId: co)),
        dec({'3': '102.3', '': '10', '2': '50'}),
      );
    },
  );

  test('credits: the balance of sent and partial credits', () async {
    await parties();
    Future<void> credit(
      String id, {
      required String status,
      String balance = '1000',
      String client = 'c-eur',
      int? archivedAt,
      bool deleted = false,
      String company = co,
    }) => db.creditDao.upsert(
      CreditsCompanion.insert(
        id: id,
        companyId: company,
        updatedAt: 1,
        payload: '{}',
        statusId: Value(status),
        amount: const Value('9999'),
        balance: Value(balance),
        clientId: Value(client),
        archivedAt: Value(archivedAt),
        isDeleted: Value(deleted),
      ),
    );
    await credit('c-sent', status: '2', balance: '25');
    await credit('c-partial', status: '3', balance: '5', client: 'c-none');
    await credit('c-applied', status: '4', balance: '0');
    await credit('c-draft', status: '1');
    await credit('c-archived', status: '2', archivedAt: 5);
    await credit('c-deleted', status: '3', deleted: true);
    await credit('c-gone-client', status: '2', client: 'c-gone');
    await credit('c-shelved-client', status: '2', client: 'c-shelved');
    await credit('c-other', status: '2', company: other);

    expect(
      await local(() => db.creditDao.watchListTotals(companyId: co)),
      dec({'3': '25', '': '5'}),
    );
  });

  test('payments: amount less applied and the refunds of unapplied money, of '
      'completed and partially refunded payments, only where above zero; the '
      'payment\'s own currency first, else its client\'s', () async {
    await parties();
    Future<void> payment(
      String id, {
      required String status,
      required String amount,
      String applied = '0',
      String refunded = '0',
      List<Map<String, Object>>? paymentables,
      String currency = '',
      String client = 'c-eur',
      int? archivedAt,
      bool deleted = false,
      String company = co,
    }) => db.paymentDao.upsert(
      PaymentsCompanion.insert(
        id: id,
        companyId: company,
        updatedAt: 1,
        payload: '{}',
        statusId: Value(status),
        amount: Value(amount),
        applied: Value(applied),
        refunded: Value(refunded),
        paymentables: Value(
          paymentables == null ? null : jsonEncode(paymentables),
        ),
        currencyId: Value(currency),
        clientId: Value(client),
        archivedAt: Value(archivedAt),
        isDeleted: Value(deleted),
      ),
    );
    // 10 refunded of the 40 on an invoice: a refund never lowers `applied`,
    // so 60 is still unapplied.
    await payment(
      'p-done',
      status: kPaymentStatusPartiallyRefunded,
      amount: '100',
      applied: '40',
      refunded: '10',
      paymentables: [
        {'invoice_id': 'i-1', 'amount': 40, 'refunded': 10},
      ],
      currency: '1',
    );
    await payment(
      'p-completed',
      status: kPaymentStatusCompleted,
      amount: '25',
      applied: '5',
      paymentables: [
        {'invoice_id': 'i-0', 'amount': 5, 'refunded': 0},
      ],
      currency: '1',
    );
    // 10 refunded of the unapplied 30, which no paymentable records.
    await payment(
      'p-refunded-part',
      status: kPaymentStatusPartiallyRefunded,
      amount: '30',
      refunded: '10',
      paymentables: [],
    );
    // 90 cash and a 30 credit on a 100 invoice; refunding 50 of the invoice
    // returned the credit first, so the payment's `refunded` is the 20 cash.
    await payment(
      'p-credit',
      status: kPaymentStatusPartiallyRefunded,
      amount: '90',
      applied: '70',
      refunded: '20',
      paymentables: [
        {'invoice_id': 'i-2', 'amount': 100, 'refunded': 50},
        {'credit_id': 'cr-1', 'amount': 30, 'refunded': 30},
      ],
    );
    // A reversal credit for the 100 on the invoice was deleted, which refunds
    // the applied 100 through a credit paymentable with no amount.
    await payment(
      'p-reversal',
      status: kPaymentStatusPartiallyRefunded,
      amount: '150',
      applied: '100',
      refunded: '100',
      paymentables: [
        {'invoice_id': 'i-3', 'amount': 100, 'refunded': 0},
        {'credit_id': 'cr-2', 'amount': 0, 'refunded': 100},
      ],
    );
    await payment(
      'p-applied-whole',
      status: kPaymentStatusCompleted,
      amount: '20',
      applied: '20',
    );
    // Refunded after being applied in full: `applied` stays 10, so nothing
    // is unapplied.
    await payment(
      'p-applied-refunded',
      status: kPaymentStatusPartiallyRefunded,
      amount: '10',
      applied: '10',
      refunded: '5',
      paymentables: [
        {'invoice_id': 'i-4', 'amount': 10, 'refunded': 5},
      ],
    );
    // A credit paymentable the API no longer sends (deleted with its
    // invoice) took its returned 30 with it: the refunds of applied money read
    // 40 against a `refunded` of 10. Never more than `amount − applied`.
    await payment(
      'p-lost-credit-row',
      status: kPaymentStatusPartiallyRefunded,
      amount: '150',
      applied: '100',
      refunded: '10',
      paymentables: [
        {'invoice_id': 'i-6', 'amount': 100, 'refunded': 40},
      ],
    );
    // A refunded invoice the API no longer sends (deleted): its 80 reads as
    // a refund of the unapplied 50. Never below zero, so it takes nothing off
    // the other payments.
    await payment(
      'p-lost-invoice-row',
      status: kPaymentStatusPartiallyRefunded,
      amount: '150',
      applied: '100',
      refunded: '80',
      paymentables: [],
    );
    // Every unapplied dollar refunded.
    await payment(
      'p-unapplied-refunded',
      status: kPaymentStatusPartiallyRefunded,
      amount: '50',
      applied: '20',
      refunded: '30',
      paymentables: [
        {'invoice_id': 'i-5', 'amount': 20, 'refunded': 0},
      ],
    );
    await payment('p-pending', status: kPaymentStatusPending, amount: '50');
    await payment('p-refunded', status: kPaymentStatusRefunded, amount: '50');
    await payment(
      'p-archived',
      status: kPaymentStatusCompleted,
      amount: '50',
      archivedAt: 5,
    );
    await payment(
      'p-deleted',
      status: kPaymentStatusCompleted,
      amount: '50',
      deleted: true,
    );
    await payment(
      'p-gone-client',
      status: kPaymentStatusCompleted,
      amount: '50',
      client: 'c-gone',
    );
    await payment(
      'p-shelved-client',
      status: kPaymentStatusCompleted,
      amount: '50',
      client: 'c-shelved',
    );
    await payment(
      'p-other',
      status: kPaymentStatusCompleted,
      amount: '50',
      company: other,
    );

    expect(
      await local(() => db.paymentDao.watchListTotals(companyId: co)),
      dec({'1': '80', '3': '140'}),
    );
  });

  test('recurring invoices: the amount of active ones', () async {
    await parties();
    Future<void> recurring(
      String id, {
      required String status,
      String amount = '1000',
      String client = 'c-grp',
      int? archivedAt,
      String company = co,
    }) => db.recurringInvoiceDao.upsert(
      RecurringInvoicesCompanion.insert(
        id: id,
        companyId: company,
        updatedAt: 1,
        payload: '{}',
        statusId: Value(status),
        amount: Value(amount),
        clientId: Value(client),
        archivedAt: Value(archivedAt),
      ),
    );
    await recurring('r-active', status: '2', amount: '12');
    await recurring('r-active-eur', status: '2', amount: '3', client: 'c-eur');
    await recurring('r-paused', status: '3');
    await recurring('r-draft', status: '1');
    await recurring('r-done', status: '4');
    await recurring('r-archived', status: '2', archivedAt: 5);
    await recurring('r-shelved-client', status: '2', client: 'c-shelved');
    await recurring('r-gone-client', status: '2', client: 'c-gone');
    await recurring('r-other', status: '2', company: other);

    expect(
      await local(() => db.recurringInvoiceDao.watchListTotals(companyId: co)),
      dec({'2': '12', '3': '3'}),
    );
  });

  test('purchase orders: the balance of sent and accepted orders, in the '
      'vendor\'s currency, never an archived or deleted vendor\'s', () async {
    await parties();
    Future<void> po(
      String id, {
      required String status,
      String balance = '1000',
      String vendor = 'v-gbp',
      int? archivedAt,
      bool deleted = false,
      String company = co,
    }) => db.purchaseOrderDao.upsert(
      PurchaseOrdersCompanion.insert(
        id: id,
        companyId: company,
        updatedAt: 1,
        payload: '{}',
        statusId: Value(status),
        balance: Value(balance),
        vendorId: Value(vendor),
        // A client on the order never decides its currency.
        clientId: const Value('c-eur'),
        archivedAt: Value(archivedAt),
        isDeleted: Value(deleted),
      ),
    );
    await po('po-sent', status: '2', balance: '40');
    await po('po-accepted', status: '3', balance: '5', vendor: 'v-none');
    await po('po-received', status: '4');
    await po('po-draft', status: '1');
    await po('po-cancelled', status: '5');
    await po('po-archived', status: '2', archivedAt: 5);
    await po('po-deleted', status: '2', deleted: true);
    await po('po-other', status: '2', company: other);
    await po('po-gone-vendor', status: '2', vendor: 'v-gone');
    await po('po-shelved-vendor', status: '2', vendor: 'v-shelved');

    expect(
      await local(() => db.purchaseOrderDao.watchListTotals(companyId: co)),
      dec({'2': '40', '': '5'}),
    );
  });

  test('expenses: marked to be invoiced and on no invoice yet, with their '
      'exclusive taxes, in the expense\'s own currency; one with no client '
      'counts, an archived or deleted client\'s does not', () async {
    await parties();
    Future<void> expense(
      String id, {
      bool shouldBeInvoiced = true,
      String invoiceId = '',
      String amount = '1000',
      String currency = '3',
      String client = '',
      Map<String, Object> taxes = const {},
      int? archivedAt,
      bool deleted = false,
      String company = co,
    }) => db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: id,
        companyId: company,
        updatedAt: 1,
        payload: jsonEncode(taxes),
        shouldBeInvoiced: Value(shouldBeInvoiced),
        invoiceId: Value(invoiceId),
        amount: Value(amount),
        currencyId: Value(currency),
        clientId: Value(client),
        archivedAt: Value(archivedAt),
        isDeleted: Value(deleted),
      ),
    );
    await expense('e-pending', amount: '9');
    await expense('e-pending-client', amount: '1', client: 'c-none');
    await expense('e-shelved-client', client: 'c-shelved');
    await expense('e-gone-client', client: 'c-gone');
    await expense('e-pending-co', amount: '1.5', currency: '');
    await expense('e-invoiced', invoiceId: 'inv-1');
    await expense('e-logged', shouldBeInvoiced: false);
    await expense('e-archived', archivedAt: 5);
    await expense('e-deleted', deleted: true);
    await expense('e-other', company: other);
    // As the list rows show it: exclusive taxes added — a named rate, or
    // the stored amounts when taxed by amount — and inclusive ones not.
    await expense('e-by-rate', amount: '80', taxes: _exclusiveRate);
    await expense('e-by-amount', amount: '90', taxes: _byAmount);
    await expense('e-inclusive', amount: '100', taxes: _inclusiveRate);

    expect(
      await local(() => db.expenseDao.watchListTotals(companyId: co)),
      dec({'3': '310', '': '1.5'}),
    );
  });

  test('recurring expenses: the amount of active ones with their exclusive '
      'taxes — never one whose cycles have run out, nor an archived or '
      'deleted client\'s', () async {
    Future<void> recurring(
      String id, {
      required String status,
      String amount = '1000',
      int remainingCycles = -1,
      String lastSentDate = '',
      String client = '',
      Map<String, Object> taxes = const {},
      int? archivedAt,
      String company = co,
    }) => db.recurringExpenseDao.upsert(
      RecurringExpensesCompanion.insert(
        id: id,
        companyId: company,
        updatedAt: 1,
        payload: jsonEncode(taxes),
        statusId: Value(status),
        amount: Value(amount),
        currencyId: const Value('2'),
        remainingCycles: Value(remainingCycles),
        lastSentDate: Value(lastSentDate),
        clientId: Value(client),
        archivedAt: Value(archivedAt),
      ),
    );
    await parties();
    await recurring(
      're-active',
      status: kRecurringExpenseStatusActive,
      amount: '4',
      lastSentDate: past,
    );
    // Active but never sent yet — the Pending tab — still an active schedule.
    await recurring(
      're-pending',
      status: kRecurringExpenseStatusActive,
      amount: '1',
      remainingCycles: 3,
    );
    await recurring(
      're-exhausted',
      status: kRecurringExpenseStatusActive,
      remainingCycles: 0,
    );
    await recurring('re-paused', status: kRecurringExpenseStatusPaused);
    await recurring('re-draft', status: kRecurringExpenseStatusDraft);
    await recurring(
      're-archived',
      status: kRecurringExpenseStatusActive,
      archivedAt: 5,
    );
    await recurring(
      're-other',
      status: kRecurringExpenseStatusActive,
      company: other,
    );
    await recurring(
      're-client',
      status: kRecurringExpenseStatusActive,
      amount: '2',
      client: 'c-eur',
    );
    await recurring(
      're-gone-client',
      status: kRecurringExpenseStatusActive,
      client: 'c-gone',
    );
    await recurring(
      're-shelved-client',
      status: kRecurringExpenseStatusActive,
      client: 'c-shelved',
    );

    await recurring(
      're-by-rate',
      status: kRecurringExpenseStatusActive,
      amount: '80',
      taxes: _exclusiveRate,
    );
    await recurring(
      're-by-amount',
      status: kRecurringExpenseStatusActive,
      amount: '90',
      taxes: _byAmount,
    );
    await recurring(
      're-inclusive',
      status: kRecurringExpenseStatusActive,
      amount: '100',
      taxes: _inclusiveRate,
    );

    expect(
      await local(() => db.recurringExpenseDao.watchListTotals(companyId: co)),
      dec({'2': '307'}),
    );
  });

  test('nothing to sum is an empty map, and a list with no line has no '
      'query', () async {
    expect(
      await local(() => db.quoteDao.watchListTotals(companyId: co)),
      isEmpty,
    );
    expect(db.clientDao.watchListTotals(companyId: co), isNull);
    expect(db.invoiceDao.watchListTotals(companyId: co), isNull);
    expect(db.vendorDao.watchListTotals(companyId: co), isNull);
  });

  test(
    'a client\'s currency landing after its quotes re-sums the line',
    () async {
      await db.quoteDao.upsert(
        QuotesCompanion.insert(
          id: 'q1',
          companyId: co,
          updatedAt: 1,
          payload: '{}',
          statusId: const Value('3'),
          amount: const Value('7'),
          clientId: const Value('c-late'),
        ),
      );
      final seen = <Map<String, Decimal>>[];
      final sub = db.quoteDao.watchListTotals(companyId: co)!.listen(seen.add);
      await pumpEventQueue();
      expect(seen.last, dec({'': '7'}));

      await client('c-late', settings: {'currency_id': '4'});
      await pumpEventQueue();
      expect(seen.last, dec({'4': '7'}));
      await sub.cancel();
    },
  );

  test('the overdue client ids are the Overdue tab\'s predicate', () async {
    Future<void> invoice(
      String id, {
      required String client,
      String status = '2',
      String dueDate = '',
      int? archivedAt,
    }) => db.invoiceDao.upsert(
      InvoicesCompanion.insert(
        id: id,
        companyId: co,
        updatedAt: 1,
        payload: '{}',
        statusId: Value(status),
        balance: const Value('10'),
        dueDate: Value(dueDate),
        clientId: Value(client),
        archivedAt: Value(archivedAt),
      ),
    );
    await invoice('i-late', client: 'c-late', dueDate: past);
    await invoice('i-due', client: 'c-due', dueDate: future);
    await invoice('i-paid', client: 'c-paid', dueDate: past, status: '4');
    await invoice('i-archived', client: 'c-arch', dueDate: past, archivedAt: 5);

    for (final id in ['c-late', 'c-due', 'c-paid', 'c-arch']) {
      await client(id);
    }

    final ids = await db.clientDao.watchOverdueClientIds(companyId: co).first;
    expect(ids, {'c-late'});
    // The same clients the Overdue tab counts.
    final tab = await db.clientDao
        .watchBadgeCount(companyId: co, modeId: 'overdue')
        .first;
    expect(tab, ids.length);
  });
}
