import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/payment_api_model.dart';
import 'package:admin/data/models/domain/payment.dart';

/// [PaymentStatusExt.unapplied] leaves out what was refunded of the unapplied
/// money, and only that: `refunded` also holds the refunds of applied money,
/// which the server records on the paymentables (invoiceninja/invoiceninja
/// #13465, `getPaymentTotalsQuery`). The Apply action offers this figure, so
/// an overstated one applies money the client was already paid back.
void main() {
  Payment payment({
    required String amount,
    String applied = '0',
    String refunded = '0',
    List<PaymentableApi> paymentables = const [],
  }) => Payment.fromApi(
    PaymentApi(
      id: 'p1',
      amount: amount,
      applied: applied,
      refunded: refunded,
      paymentables: paymentables,
      updatedAt: 1,
    ),
  );

  Decimal d(String v) => Decimal.parse(v);

  test('a refund of the unapplied money comes off it', () {
    final p = payment(amount: '100', refunded: '50');
    expect(p.unapplied, d('50'));
    expect(p.hasUnappliedFunds, isTrue);
  });

  test('a refund on an invoice leaves the unapplied money alone', () {
    final p = payment(
      amount: '150',
      applied: '100',
      refunded: '40',
      paymentables: const [
        PaymentableApi(invoiceId: 'i1', amount: 100, refunded: 40),
      ],
    );
    expect(p.unapplied, d('50'));
  });

  test('an invoice refund that returned a credit first counts only its cash '
      'part', () {
    // 90 cash + a 30 credit on a 100 invoice; refunding 50 of it returns the
    // 30 credit, so the payment's `refunded` is the 20 cash.
    final p = payment(
      amount: '90',
      applied: '70',
      refunded: '20',
      paymentables: const [
        PaymentableApi(invoiceId: 'i1', amount: 100, refunded: 50),
        PaymentableApi(creditId: 'c1', amount: 30, refunded: 30),
      ],
    );
    expect(p.unapplied, d('20'));
  });

  test('a deleted reversal credit refunds applied money', () {
    // `CreditService::deleteCredit` writes a credit paymentable with no
    // amount and the refund on it.
    final p = payment(
      amount: '150',
      applied: '100',
      refunded: '100',
      paymentables: const [
        PaymentableApi(invoiceId: 'i1', amount: 100),
        PaymentableApi(creditId: 'c1', amount: 0, refunded: 100),
      ],
    );
    expect(p.unapplied, d('50'));
  });

  test('never more than amount less applied, the most Apply may allocate', () {
    // The API omits a credit paymentable deleted with its invoice, and the
    // 30 credit it returned with it: the refunds of applied money read 40
    // against a `refunded` of 10.
    final p = payment(
      amount: '150',
      applied: '100',
      refunded: '10',
      paymentables: const [
        PaymentableApi(invoiceId: 'i1', amount: 100, refunded: 40),
      ],
    );
    expect(p.unapplied, d('50'));
  });

  test('never below zero once a refunded invoice is deleted', () {
    // 200 paid two 100 invoices, 40 was refunded of the first, which was then
    // deleted: amount and applied both fell by 60, the refund stayed on the
    // payment, and its paymentable is gone from the API.
    final p = payment(
      amount: '140',
      applied: '140',
      refunded: '40',
      paymentables: const [PaymentableApi(invoiceId: 'i2', amount: 100)],
    );
    expect(p.unapplied, Decimal.zero);
    expect(p.hasUnappliedFunds, isFalse);

    final partly = payment(amount: '150', applied: '100', refunded: '80');
    expect(partly.unapplied, Decimal.zero);
  });

  test('a payment applied past its amount has nothing unapplied', () {
    final p = payment(amount: '100', applied: '120');
    expect(p.unapplied, Decimal.zero);
  });

  test('every unapplied dollar refunded leaves nothing to apply', () {
    final p = payment(
      amount: '50',
      applied: '20',
      refunded: '30',
      paymentables: const [PaymentableApi(invoiceId: 'i1', amount: 20)],
    );
    expect(p.unapplied, Decimal.zero);
    expect(p.hasUnappliedFunds, isFalse);
  });
}
