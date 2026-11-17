// The billing edit form's date-order rule — what `Update{Invoice,Quote}Request`
// refuses: a due date before the document date (`after_or_equal:date`), and a
// partial due date before the document date or not strictly before the due
// date (`after_or_equal:date`, `before:due_date`). Shown live under the field
// and blocking Save, on the invoice and the quote only.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/value/date.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/ui/features/billing_shared/edit/billing_doc_date_order.dart';
import 'package:admin/ui/features/credits/view_models/credit_edit_view_model.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/purchase_orders/view_models/purchase_order_edit_view_model.dart';
import 'package:admin/ui/features/quotes/view_models/quote_edit_view_model.dart';

const _jan10 = Date(2026, 1, 10);
const _jan20 = Date(2026, 1, 20);
const _jan31 = Date(2026, 1, 31);

void main() {
  test('only the invoice and the quote check the order', () {
    expect(BillingDocType.values.where((t) => t.validatesDateOrder), [
      BillingDocType.invoice,
      BillingDocType.quote,
    ]);
  });

  group('due date', () {
    test('before the document date is refused', () {
      final draft = emptyInvoice().copyWith(date: _jan20, dueDate: _jan10);
      expect(billingDocDateOrderErrors(BillingDocType.invoice, draft), {
        'due_date': BillingDateOrderError.beforeDate,
      });
    });

    test('on the document date is fine (after_or_equal)', () {
      final draft = emptyQuote().copyWith(date: _jan20, dueDate: _jan20);
      expect(billingDocDateOrderErrors(BillingDocType.quote, draft), isEmpty);
    });

    test('a blank date checks nothing — the server fills it', () {
      final draft = emptyInvoice().copyWith(date: _jan20, dueDate: null);
      expect(billingDocDateOrderErrors(BillingDocType.invoice, draft), isEmpty);
    });

    test('a credit and a purchase order are not checked', () {
      expect(
        billingDocDateOrderErrors(
          BillingDocType.credit,
          emptyCredit().copyWith(date: _jan20, dueDate: _jan10),
        ),
        isEmpty,
      );
      expect(
        billingDocDateOrderErrors(
          BillingDocType.purchaseOrder,
          emptyPurchaseOrder().copyWith(date: _jan20, dueDate: _jan10),
        ),
        isEmpty,
      );
    });
  });

  group('partial due date', () {
    final withPartial = emptyInvoice().copyWith(
      date: _jan10,
      dueDate: _jan31,
      partial: Decimal.fromInt(50),
    );

    test('inside [date, due) is fine', () {
      expect(
        billingDocDateOrderErrors(
          BillingDocType.invoice,
          withPartial.copyWith(partialDueDate: _jan10),
        ),
        isEmpty,
      );
    });

    test('before the document date is refused', () {
      expect(
        billingDocDateOrderErrors(
          BillingDocType.invoice,
          withPartial.copyWith(partialDueDate: const Date(2026, 1, 9)),
        ),
        {'partial_due_date': BillingDateOrderError.beforeDate},
      );
    });

    test('ON the due date is refused — the server rule is a strict before', () {
      expect(
        billingDocDateOrderErrors(
          BillingDocType.invoice,
          withPartial.copyWith(partialDueDate: _jan31),
        ),
        {'partial_due_date': BillingDateOrderError.notBeforeDueDate},
      );
    });

    test('is ignored at a zero partial (exclude_if:partial,0)', () {
      expect(
        billingDocDateOrderErrors(
          BillingDocType.invoice,
          withPartial.copyWith(
            partial: Decimal.zero,
            partialDueDate: const Date(2026, 1, 1),
          ),
        ),
        isEmpty,
      );
    });
  });

  test('validate() blocks the save with the localized message', () {
    final vm = InvoiceEditViewModel(
      repo: _NoRepo(),
      companyId: 'co',
      clientRequiredMessage: 'client',
      crossClientLineItemsMessage: 'cross',
      partialInvalidMessage: 'partial',
      dateOrderMessages: (beforeDate: 'too early', notBeforeDue: 'too late'),
      cloneFrom: emptyInvoice().copyWith(
        clientId: 'c1',
        date: _jan20,
        dueDate: _jan10,
      ),
    );
    addTearDown(vm.dispose);
    expect(vm.validate()['due_date'], ['too early']);
  });
}

class _NoRepo implements InvoiceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
