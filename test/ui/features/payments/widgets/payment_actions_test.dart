import 'package:material_ui/material_ui.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/api/payment_api_model.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/domain/payment_status.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/features/payments/widgets/payment_actions.dart';

import '../../shell/_shell_test_helpers.dart';

/// Gating coverage for `PaymentActions.itemsFor`, mirroring the harness in
/// `purchase_order_actions_test.dart`.
///
/// The invariant worth locking down is **Refund**: it needs BOTH
/// `canRefund` (something left to refund, and a Completed / Partially-refunded
/// status) AND `hasInvoiceAllocations`. The refund screen is
/// invoice-allocation-only by design (React parity — there is no
/// client-account-refund path), so offering Refund on an unapplied payment
/// dead-ends the user on an empty screen.
///
/// Payment is the one action class that reads no permissions — gating is
/// purely entity state.
Payment _payment({
  String id = 'pay1',
  String statusId = kPaymentStatusCompleted,
  String amount = '100',
  String refunded = '0',
  List<PaymentableApi> paymentables = const [],
  List<PaymentInvoiceRefApi>? invoices,
  bool isDeleted = false,
  int archivedAt = 0,
}) => Payment.fromApi(
  PaymentApi(
    id: id,
    statusId: statusId,
    amount: amount,
    refunded: refunded,
    paymentables: paymentables,
    invoices: invoices,
    isDeleted: isDeleted,
    archivedAt: archivedAt,
  ),
);

const _invoiceAllocation = PaymentableApi(invoiceId: 'inv1', amount: '100');
const _creditAllocation = PaymentableApi(creditId: 'cr1', amount: '100');

void main() {
  Future<List<EntityActionItem<PaymentAction>>> resolveItems(
    WidgetTester tester,
    Payment payment,
  ) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
    );
    addTearDown(fixture.dispose);

    late List<EntityActionItem<PaymentAction>> items;
    await tester.pumpWidget(
      wrapWithShell(
        fixture.services,
        Builder(
          builder: (context) {
            items = PaymentActions.itemsFor(context, payment, (_) {});
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return items;
  }

  bool enabled(
    List<EntityActionItem<PaymentAction>> items,
    PaymentAction kind,
  ) {
    final match = flattenActionItems(items).where((i) => i.kind == kind);
    return match.isNotEmpty && match.first.enabled;
  }

  bool present(
    List<EntityActionItem<PaymentAction>> items,
    PaymentAction kind,
  ) => flattenActionItems(items).any((i) => i.kind == kind);

  group('refund needs an invoice allocation AND a refundable balance', () {
    testWidgets('completed payment applied to an invoice → enabled', (
      tester,
    ) async {
      final items = await resolveItems(
        tester,
        _payment(paymentables: const [_invoiceAllocation]),
      );

      expect(enabled(items, PaymentAction.refund), isTrue);
    });

    testWidgets('unapplied payment (no allocations) → disabled', (
      tester,
    ) async {
      final items = await resolveItems(tester, _payment());

      expect(
        enabled(items, PaymentAction.refund),
        isFalse,
        reason:
            'the refund screen has no client-account-refund path, so an '
            'unapplied payment would dead-end',
      );
    });

    testWidgets('credit-only allocation → disabled', (tester) async {
      final items = await resolveItems(
        tester,
        _payment(paymentables: const [_creditAllocation]),
      );

      expect(
        enabled(items, PaymentAction.refund),
        isFalse,
        reason: 'hasInvoiceAllocations looks for a non-empty invoiceId',
      );
    });

    testWidgets('fully refunded payment → disabled even with an allocation', (
      tester,
    ) async {
      final items = await resolveItems(
        tester,
        _payment(
          amount: '100',
          refunded: '100',
          paymentables: const [_invoiceAllocation],
        ),
      );

      expect(enabled(items, PaymentAction.refund), isFalse);
    });

    testWidgets('partially refunded payment → still enabled', (tester) async {
      final items = await resolveItems(
        tester,
        _payment(
          statusId: kPaymentStatusPartiallyRefunded,
          amount: '100',
          refunded: '40',
          paymentables: const [_invoiceAllocation],
        ),
      );

      expect(enabled(items, PaymentAction.refund), isTrue);
    });

    testWidgets('a pending (non-completed) payment → disabled', (tester) async {
      final items = await resolveItems(
        tester,
        _payment(statusId: '1', paymentables: const [_invoiceAllocation]),
      );

      expect(enabled(items, PaymentAction.refund), isFalse);
    });

    testWidgets('a fully refunded status → disabled', (tester) async {
      final items = await resolveItems(
        tester,
        _payment(
          statusId: kPaymentStatusRefunded,
          paymentables: const [_invoiceAllocation],
        ),
      );

      expect(enabled(items, PaymentAction.refund), isFalse);
    });
  });

  group('send email', () {
    testWidgets('enabled on a live payment', (tester) async {
      final items = await resolveItems(tester, _payment());

      expect(enabled(items, PaymentAction.sendEmail), isTrue);
    });

    testWidgets('disabled once deleted', (tester) async {
      final items = await resolveItems(tester, _payment(isDeleted: true));

      expect(enabled(items, PaymentAction.sendEmail), isFalse);
    });
  });

  group('lifecycle actions reflect entity state', () {
    testWidgets('a live payment offers archive and delete, not restore', (
      tester,
    ) async {
      final items = await resolveItems(tester, _payment());

      expect(present(items, PaymentAction.archive), isTrue);
      expect(present(items, PaymentAction.delete), isTrue);
      expect(present(items, PaymentAction.restore), isFalse);
    });

    testWidgets('an archived payment offers restore, not archive', (
      tester,
    ) async {
      final items = await resolveItems(
        tester,
        _payment(archivedAt: 1700000000),
      );

      expect(present(items, PaymentAction.restore), isTrue);
      expect(present(items, PaymentAction.archive), isFalse);
    });

    testWidgets('a deleted payment offers restore but not delete', (
      tester,
    ) async {
      final items = await resolveItems(tester, _payment(isDeleted: true));

      expect(present(items, PaymentAction.restore), isTrue);
      expect(present(items, PaymentAction.delete), isFalse);
    });

    testWidgets(
      'applied to a deleted invoice → no delete (server: deleted_invoices_exist)',
      (tester) async {
        final items = await resolveItems(
          tester,
          _payment(
            paymentables: const [_invoiceAllocation],
            invoices: const [PaymentInvoiceRefApi(id: 'inv1', isDeleted: true)],
          ),
        );

        expect(present(items, PaymentAction.delete), isFalse);
        expect(present(items, PaymentAction.archive), isTrue);
      },
    );

    testWidgets('applied to a live invoice → delete still offered', (
      tester,
    ) async {
      final items = await resolveItems(
        tester,
        _payment(
          paymentables: const [_invoiceAllocation],
          invoices: const [PaymentInvoiceRefApi(id: 'inv1')],
        ),
      );

      expect(present(items, PaymentAction.delete), isTrue);
    });
  });

  testWidgets('edit and add-comment are always available', (tester) async {
    final items = await resolveItems(tester, _payment(isDeleted: true));

    expect(enabled(items, PaymentAction.edit), isTrue);
    expect(enabled(items, PaymentAction.addComment), isTrue);
    expect(enabled(items, PaymentAction.logCall), isTrue);
  });

  group('isLifecycle marks exactly the create-screen-hidden actions', () {
    test('archive, restore and delete are lifecycle; the rest are not', () {
      expect(PaymentActions.isLifecycle(PaymentAction.archive), isTrue);
      expect(PaymentActions.isLifecycle(PaymentAction.restore), isTrue);
      expect(PaymentActions.isLifecycle(PaymentAction.delete), isTrue);
      expect(PaymentActions.isLifecycle(PaymentAction.edit), isFalse);
      expect(PaymentActions.isLifecycle(PaymentAction.refund), isFalse);
      expect(PaymentActions.isLifecycle(PaymentAction.sendEmail), isFalse);
    });

    test(
      'refund and Enter Payment navigate unconditionally after a create',
      () {
        expect(PaymentActions.navigatesOnCreate(PaymentAction.refund), isTrue);
        expect(
          PaymentActions.navigatesOnCreate(PaymentAction.newPayment),
          isTrue,
        );
        expect(PaymentActions.navigatesOnCreate(PaymentAction.edit), isFalse);
        expect(
          PaymentActions.navigatesOnCreate(PaymentAction.sendEmail),
          isFalse,
        );
      },
    );
  });

  // Regression: on a new payment the action bar's Send Email saved the
  // create (with the Email receipt switch's receipt) and then sent another.
  // The switch is the new payment's only way to send one; an existing
  // payment keeps the action (and has no switch).
  group('the edit screen\'s action bar', () {
    Future<List<EntityActionItem<PaymentAction>>> editItems(
      WidgetTester tester, {
      required bool isCreate,
    }) async {
      final fixture = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Co')],
      );
      addTearDown(fixture.dispose);
      late List<EntityActionItem<PaymentAction>> items;
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Builder(
            builder: (context) {
              items = PaymentActions.editScreenItemsFor(
                context,
                _payment(id: isCreate ? '' : 'pay1'),
                (_) {},
                isCreate: isCreate,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return items;
    }

    testWidgets('a new payment offers no Send Email', (tester) async {
      final items = await editItems(tester, isCreate: true);
      expect(present(items, PaymentAction.sendEmail), isFalse);
    });

    testWidgets('an existing payment keeps it', (tester) async {
      final items = await editItems(tester, isCreate: false);
      expect(present(items, PaymentAction.sendEmail), isTrue);
    });

    // Regression: Enter Payment offered Add Comment and Log Call on a payment
    // that did not exist yet.
    testWidgets('a new payment offers no Add Comment or Log Call', (
      tester,
    ) async {
      final items = await editItems(tester, isCreate: true);
      expect(present(items, PaymentAction.addComment), isFalse);
      expect(present(items, PaymentAction.logCall), isFalse);
    });

    testWidgets('an existing payment keeps Add Comment and Log Call', (
      tester,
    ) async {
      final items = await editItems(tester, isCreate: false);
      expect(present(items, PaymentAction.addComment), isTrue);
      expect(present(items, PaymentAction.logCall), isTrue);
    });
  });

  // Beta feedback (Nov 2026): after recording a payment, a way to enter the
  // next one, or the rest of the same invoice paid another way, without going
  // back through the menu.
  group('Enter Payment from a payment', () {
    Future<List<EntityActionItem<PaymentAction>>> itemsAs(
      WidgetTester tester,
      FakeCompany company,
    ) async {
      final fixture = await buildFixture(companies: [company]);
      addTearDown(fixture.dispose);
      late List<EntityActionItem<PaymentAction>> items;
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Builder(
            builder: (context) {
              items = PaymentActions.itemsFor(context, _payment(), (_) {});
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return items;
    }

    testWidgets('is offered to a user who may create payments', (tester) async {
      final items = await itemsAs(
        tester,
        const FakeCompany(id: 'co1', name: 'Co'),
      );
      expect(enabled(items, PaymentAction.newPayment), isTrue);
    });

    testWidgets('is not offered without create_payment', (tester) async {
      final items = await itemsAs(
        tester,
        const FakeCompany(
          id: 'co1',
          name: 'Co',
          isOwner: false,
          isAdmin: false,
          permissions: 'view_payment,edit_payment',
        ),
      );
      expect(present(items, PaymentAction.newPayment), isFalse);
      expect(present(items, PaymentAction.edit), isTrue);
    });

    testWidgets('is on the edit screen too, where it saves first', (
      tester,
    ) async {
      final fixture = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Co')],
      );
      addTearDown(fixture.dispose);
      late List<EntityActionItem<PaymentAction>> items;
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          Builder(
            builder: (context) {
              items = PaymentActions.editScreenItemsFor(
                context,
                _payment(),
                (_) {},
                isCreate: true,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(present(items, PaymentAction.newPayment), isTrue);
    });
  });

  group('anotherPaymentDraft', () {
    Payment stored({
      String id = 'pay1',
      String clientId = 'cl1',
      bool isDirty = false,
      List<PaymentableApi> paymentables = const [
        PaymentableApi(invoiceId: 'inv1', amount: '60'),
      ],
    }) => Payment.fromApi(PaymentApi(id: id, clientId: clientId, amount: '60'))
        .copyWith(
          isDirty: isDirty,
          paymentables: [for (final p in paymentables) Paymentable.fromApi(p)],
        );

    Invoice invoice(
      String id, {
      String balance = '40',
      bool isDeleted = false,
      bool isDirty = false,
    }) => Invoice.fromApi(
      InvoiceApi(
        id: id,
        clientId: 'cl1',
        balance: balance,
        isDeleted: isDeleted,
      ),
    ).copyWith(isDirty: isDirty);

    Future<Payment> draftFor(
      Payment payment, {
      String? resolved,
      Payment? fromDrift,
      Map<String, Invoice> invoices = const {},
    }) => anotherPaymentDraft(
      payment,
      resolveId: (id) async => resolved ?? id,
      readPayment: (_) async => fromDrift,
      readInvoice: (id) async => invoices[id],
    );

    test('allocates what each invoice it paid still owes', () async {
      final payment = stored(
        paymentables: const [
          PaymentableApi(invoiceId: 'inv1', amount: '60'),
          PaymentableApi(invoiceId: 'inv2', amount: '10'),
          // A second row for the same invoice (a refund, a re-apply).
          PaymentableApi(invoiceId: 'inv1', amount: '5'),
          PaymentableApi(creditId: 'cr1', amount: '5'),
        ],
      );
      final draft = await draftFor(
        payment,
        fromDrift: payment,
        invoices: {
          'inv1': invoice('inv1'),
          'inv2': invoice('inv2', balance: '0'),
        },
      );

      expect(draft.id, isEmpty);
      expect(draft.clientId, 'cl1');
      expect(draft.paymentables, hasLength(1));
      expect(draft.paymentables.single.invoiceId, 'inv1');
      expect(draft.paymentables.single.amount, Decimal.parse('40'));
    });

    test('skips a deleted invoice and one with a queued change', () async {
      final payment = stored(
        paymentables: const [
          PaymentableApi(invoiceId: 'inv1', amount: '60'),
          PaymentableApi(invoiceId: 'inv2', amount: '60'),
          PaymentableApi(invoiceId: 'inv3', amount: '60'),
        ],
      );
      final draft = await draftFor(
        payment,
        fromDrift: payment,
        invoices: {
          'inv1': invoice('inv1', isDeleted: true),
          'inv2': invoice('inv2', isDirty: true),
        },
      );

      expect(draft.clientId, 'cl1');
      expect(draft.paymentables, isEmpty);
    });

    test('an unsynced payment carries only the client: its invoices still hold '
        'the balance from before it', () async {
      final offline = stored(id: 'tmp_abc');
      final draft = await draftFor(
        offline,
        fromDrift: stored(),
        invoices: {'inv1': invoice('inv1', balance: '100')},
      );
      expect(draft.clientId, 'cl1');
      expect(draft.paymentables, isEmpty);

      final queued = stored(isDirty: true);
      final queuedDraft = await draftFor(
        queued,
        fromDrift: queued,
        invoices: {'inv1': invoice('inv1', balance: '100')},
      );
      expect(queuedDraft.clientId, 'cl1');
      expect(queuedDraft.paymentables, isEmpty);
    });

    test('a new payment whose create landed reads the stored copy', () async {
      // The editor hands over the draft under its `tmp_` id; the create has
      // drained, so the id resolves and the server's copy is read.
      final draft = await draftFor(
        stored(id: 'tmp_abc', paymentables: const []),
        resolved: 'pay1',
        fromDrift: stored(),
        invoices: {'inv1': invoice('inv1', balance: '15')},
      );
      expect(draft.paymentables.single.amount, Decimal.parse('15'));
    });
  });
}
