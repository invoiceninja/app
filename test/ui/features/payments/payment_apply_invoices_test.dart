import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/data/repositories/payment_repository.dart';
import 'package:admin/data/services/payments_api.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/ui/features/payments/view_models/payment_edit_view_model.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_allocations_section.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_apply_invoices.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_invoice_checklist.dart';
import '../../../_localization_helper.dart';

// The new payment's Apply to invoices table: the client's open invoices as
// ticked rows (it replaced a picker row per invoice and a Select Invoices
// dialog). Beta feedback: an agency billed one invoice per end client and
// paid them in a batch.

AllocationTarget _target(
  String id,
  num balance, {
  num partial = 0,
  bool draft = false,
}) => AllocationTarget(
  id: id,
  number: id.toUpperCase(),
  balance: Decimal.parse('$balance'),
  partial: Decimal.parse('$partial'),
  isDraft: draft,
);

Paymentable _inv(String id, num amount) => Paymentable(
  invoiceId: id,
  amount: Decimal.parse('$amount'),
  refunded: Decimal.zero,
);

Paymentable _cre(String id, num amount) => Paymentable(
  creditId: id,
  amount: Decimal.parse('$amount'),
  refunded: Decimal.zero,
);

Invoice _invoice(
  String id,
  num balance, {
  String date = '2026-01-01',
  String dueDate = '',
  int archivedAt = 0,
  String statusId = '2',
}) => Invoice.fromApi(
  InvoiceApi(
    id: id,
    number: id.toUpperCase(),
    clientId: 'c1',
    statusId: statusId,
    date: date,
    dueDate: dueDate,
    amount: balance.toDouble(),
    balance: balance.toDouble(),
    archivedAt: archivedAt,
  ),
);

class _FakeInvoices implements InvoiceRepository {
  _FakeInvoices(this.open, {this.fetch = UnpaidInvoicesFetch.complete});
  final List<Invoice> open;
  final UnpaidInvoicesFetch fetch;
  final List<Map<String, Set<String>>> pageFetches = [];

  @override
  Stream<List<Invoice>> watchForClient({
    required String companyId,
    required String clientId,
  }) => Stream.value(open);

  @override
  Stream<List<Invoice>> watchUnpaidForClient({
    required String companyId,
    required String clientId,
  }) => Stream.value(const []);

  @override
  Stream<Invoice?> watchByRealId({
    required String companyId,
    required String id,
  }) => Stream.value(null);

  @override
  Future<UnpaidInvoicesFetch> ensureUnpaidForClientLoaded({
    required String companyId,
    required String clientId,
  }) async => fetch;

  @override
  Future<bool> ensurePageLoaded({
    required String companyId,
    required int page,
    String? search,
    Set<EntityState> states = const {EntityState.active},
    Map<String, Set<String>> extraFilters = const {},
    bool ignoreCursor = false,
  }) async {
    pageFetches.add(extraFilters);
    return false;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeServices implements Services {
  _FakeServices(this.invoices);
  @override
  final InvoiceRepository invoices;
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakePaymentsApi implements PaymentsApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('applyInvoiceSelection', () {
    final targets = [_target('i1', 100), _target('i2', 250), _target('i3', 40)];

    test('appends the ticked invoices in full while the amount is open', () {
      final next = applyInvoiceSelection(
        paymentables: const [],
        targets: targets,
        selected: {'i1', 'i3'},
        paymentAmount: Decimal.zero,
      );
      expect(next.map((p) => (p.invoiceId, p.amount.toString())), [
        ('i1', '100'),
        ('i3', '40'),
      ]);
    });

    test('a kept row keeps its amount and place; an unticked one goes', () {
      final next = applyInvoiceSelection(
        paymentables: [_inv('i2', 60), _inv('i1', 100)],
        targets: targets,
        selected: {'i2', 'i3'},
        paymentAmount: Decimal.zero,
      );
      expect(next.map((p) => (p.invoiceId, p.amount.toString())), [
        ('i2', '60'),
        ('i3', '40'),
      ]);
    });

    test('credits, and invoices the list does not offer, are untouched', () {
      final next = applyInvoiceSelection(
        paymentables: [_cre('c1', 20), _inv('paid_off', 75), _inv('i1', 100)],
        targets: targets,
        selected: const {},
        paymentAmount: Decimal.zero,
      );
      expect(next.map((p) => p.creditId.isEmpty ? p.invoiceId : p.creditId), [
        'c1',
        'paid_off',
      ]);
    });

    test('a fixed amount caps the new rows like the row picker does', () {
      final next = applyInvoiceSelection(
        paymentables: const [],
        targets: targets,
        selected: {'i1', 'i2', 'i3'},
        paymentAmount: Decimal.parse('300'),
      );
      // i3 would get nothing, and the server refuses a zero allocation on a
      // sent invoice ("Amount cannot be less than or equal to zero").
      expect(next.map((p) => (p.invoiceId, p.amount.toString())), [
        ('i1', '100'),
        ('i2', '200'),
      ]);
    });

    test('a partial is what a new row starts at', () {
      final next = applyInvoiceSelection(
        paymentables: const [],
        targets: [_target('i1', 100, partial: 30)],
        selected: {'i1'},
        paymentAmount: Decimal.zero,
      );
      expect(next.single.amount, Decimal.parse('30'));
    });
  });

  group('autoApplyOldestFirst', () {
    test('pays the oldest first and stops when the amount runs out', () {
      final rows = autoApplyOldestFirst(
        targets: [_target('old', 100), _target('mid', 80), _target('new', 50)],
        amount: Decimal.parse('150'),
      );
      expect(rows.map((p) => (p.invoiceId, p.amount.toString())), [
        ('old', '100'),
        ('mid', '50'),
      ]);
    });

    test('skips drafts — nothing is owed on an unsent invoice', () {
      final rows = autoApplyOldestFirst(
        targets: [_target('d', 100, draft: true), _target('s', 60)],
        amount: Decimal.parse('100'),
      );
      expect(rows.map((p) => p.invoiceId), ['s']);
    });

    test('covers every partial before any full balance', () {
      final rows = autoApplyOldestFirst(
        targets: [_target('old', 100), _target('new', 200, partial: 50)],
        amount: Decimal.parse('120'),
      );
      // The newer invoice's deposit is paid first, the rest goes oldest
      // first.
      expect(rows.map((p) => (p.invoiceId, p.amount.toString())), [
        ('old', '70'),
        ('new', '50'),
      ]);
    });

    test('credits pay invoices too', () {
      final rows = autoApplyOldestFirst(
        targets: [_target('a', 100), _target('b', 100)],
        amount: Decimal.parse('100'),
        credits: Decimal.parse('50'),
      );
      expect(rows.map((p) => (p.invoiceId, p.amount.toString())), [
        ('a', '100'),
        ('b', '50'),
      ]);
    });
  });

  group('payableInvoicesForApply', () {
    test('open invoices oldest first; paid and archived ones left out', () {
      final rows = payableInvoicesForApply([
        _invoice('new', 10, date: '2026-03-01'),
        _invoice('paid', 0, date: '2026-01-01'),
        _invoice('archived', 10, date: '2026-01-02', archivedAt: 1),
        _invoice('old', 10, date: '2026-02-01'),
      ], allocated: const {});
      expect(rows.map((i) => i.id), ['old', 'new']);
    });

    test('an allocated invoice always has its row, archived or not', () {
      final rows = payableInvoicesForApply(
        [_invoice('archived', 10, archivedAt: 1)],
        allocated: {'archived'},
      );
      expect(rows.map((i) => i.id), ['archived']);
    });
  });

  group('the table', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    PaymentEditViewModel newVm({Payment? staged}) => PaymentEditViewModel(
      repo: PaymentRepository(db: db, api: _FakePaymentsApi()),
      companyId: 'co',
      cloneFrom:
          staged ?? emptyPayment().copyWith(clientId: 'c1', paymentables: []),
    );

    Future<void> pump(
      WidgetTester tester,
      PaymentEditViewModel vm,
      _FakeInvoices invoices, {
      Size size = const Size(520, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Provider<Services>.value(
          value: _FakeServices(invoices),
          child: MaterialApp(
            theme: buildInTheme(InTheme.light),
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: kTestSupportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ListenableBuilder(
                  listenable: vm,
                  builder: (context, _) => PaymentApplyInvoicesSection(
                    vm: vm,
                    formatter: null,
                    currencyId: '',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final open = [
      _invoice('i1', 100, date: '2026-01-01'),
      _invoice('i2', 250, date: '2026-02-01'),
      _invoice('i3', 40, date: '2026-03-01'),
    ];

    testWidgets('ticking rows allocates them; the amount follows', (
      tester,
    ) async {
      final vm = newVm();
      await pump(tester, vm, _FakeInvoices(open));
      await tester.tap(find.text('#I1'));
      await tester.tap(find.text('#I3'));
      await tester.pumpAndSettle();
      expect(
        vm.draft.paymentables.map((p) => (p.invoiceId, p.amount.toString())),
        [('i1', '100'), ('i3', '40')],
      );
      expect(vm.draft.amount, Decimal.parse('140'));

      await tester.tap(find.text('#I1'));
      await tester.pumpAndSettle();
      expect(vm.draft.paymentables.map((p) => p.invoiceId), ['i3']);
    });

    testWidgets('an invoice\'s Enter Payment opens with that row ticked', (
      tester,
    ) async {
      final vm = newVm(
        staged: emptyPayment().copyWith(
          clientId: 'c1',
          paymentables: [_inv('i2', 250)],
        ),
      );
      await pump(tester, vm, _FakeInvoices(open));
      final ticked = tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(const ValueKey('payment_apply_i2')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(ticked.value, isTrue);
      // Its applied amount is editable.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('payment_apply_i2')),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Select All ticks every row, then clears them', (tester) async {
      final vm = newVm();
      await pump(tester, vm, _FakeInvoices(open));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(vm.draft.paymentables.length, 3);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(vm.draft.paymentables, isEmpty);
    });

    testWidgets('Auto-apply fills the typed amount, oldest first', (
      tester,
    ) async {
      final vm = newVm()..setAmount('300');
      await pump(tester, vm, _FakeInvoices(open));
      await tester.tap(find.text('Auto-apply oldest'));
      await tester.pumpAndSettle();
      expect(
        vm.draft.paymentables.map((p) => (p.invoiceId, p.amount.toString())),
        [('i1', '100'), ('i2', '200')],
      );
    });

    testWidgets('Auto-apply is disabled at a zero amount', (tester) async {
      final vm = newVm();
      await pump(tester, vm, _FakeInvoices(open));
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Auto-apply oldest'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an incomplete list says so, offers a filter, and fetches '
        'the oldest before offering Auto-apply', (tester) async {
      final invoices = _FakeInvoices(
        open,
        fetch: UnpaidInvoicesFetch.incomplete,
      );
      final vm = newVm()..setAmount('100');
      await pump(tester, vm, invoices);
      expect(
        find.text(
          'Not every open invoice is shown. Filter by number to find one.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Filter'), findsOneWidget);
      expect(
        invoices.pageFetches.any(
          (f) => f['sort']?.contains('date|asc') ?? false,
        ),
        isTrue,
      );
      expect(find.text('Auto-apply oldest'), findsOneWidget);
    });

    testWidgets('fits the 440 px slide-over panel without overflow', (
      tester,
    ) async {
      final vm = newVm(
        staged: emptyPayment().copyWith(
          clientId: 'c1',
          paymentables: [_inv('i1', 100)],
        ),
      );
      await pump(tester, vm, _FakeInvoices(open), size: const Size(440, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('#I1'), findsOneWidget);
    });
  });
}
