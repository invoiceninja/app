import 'package:flutter/widgets.dart';

import 'package:admin/data/models/domain/expense.dart';
import 'package:admin/domain/expenses/receipt_fill.dart';
import 'package:admin/ui/features/expenses/view_models/expense_edit_view_model.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_edit_identity_section.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_tax_section.dart';
import 'package:admin/ui/features/expenses/widgets/edit/receipt_read_banner.dart';

/// Amount + tax entry for the Expense edit screen. Thin wrapper that feeds the
/// shared [ExpenseTaxSection] from the ViewModel (the Recurring Expense edit
/// screen feeds the same widget from its own VM).
class ExpenseEditAmountTaxSection extends StatelessWidget {
  const ExpenseEditAmountTaxSection({super.key, required this.vm});
  final ExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final d = vm.draft;
    // The amount and its taxes count as one field for a receipt read: a tax
    // half-typed while the read runs keeps the read off the amount too, and
    // every marker on them stays until the user leaves them. The currency and
    // the date beside the amount keep scopes of their own, so typing a date
    // never holds the read off the amount, nor the amount off the date.
    return ExpenseTaxSection(
      companyId: vm.companyId,
      useCommaAsDecimalPlace: vm.useCommaAsDecimalPlace,
      amount: d.amount,
      amountBeside: ExpenseCurrencyPicker(vm: vm),
      amountTrailing: ExpenseDateField(vm: vm),
      wrapAmountFields: (child) => ReceiptFieldFocus(
        vm: vm,
        fields: const [
          ReceiptFillField.amount,
          ReceiptFillField.tax1,
          ReceiptFillField.tax2,
          ReceiptFillField.tax3,
        ],
        child: child,
      ),
      amountError: vm.fieldErrorFor('amount'),
      taxNames: [d.taxName1, d.taxName2, d.taxName3],
      taxRates: [d.taxRate1, d.taxRate2, d.taxRate3],
      taxAmounts: [d.taxAmount1, d.taxAmount2, d.taxAmount3],
      usesInclusiveTaxes: d.usesInclusiveTaxes,
      calculateTaxByAmount: d.calculateTaxByAmount,
      currencyId: d.currencyId,
      taxTotal: d.taxAmountSum,
      total: d.grossAmount,
      onAmountChanged: vm.setAmount,
      onTaxNameChanged: (slot, v) =>
          _apply(slot, vm.setTaxName1, vm.setTaxName2, vm.setTaxName3, v),
      onTaxRateChanged: (slot, v) =>
          _apply(slot, vm.setTaxRate1, vm.setTaxRate2, vm.setTaxRate3, v),
      onTaxAmountChanged: (slot, v) =>
          _apply(slot, vm.setTaxAmount1, vm.setTaxAmount2, vm.setTaxAmount3, v),
      onUsesInclusiveTaxesChanged: vm.setUsesInclusiveTaxes,
      onCalculateByAmountChanged: vm.setCalculateTaxByAmount,
      amountHelper: ReceiptFieldMarker.of(vm, ReceiptFillField.amount),
      taxHelpers: [
        ReceiptFieldMarker.of(vm, ReceiptFillField.tax1),
        ReceiptFieldMarker.of(vm, ReceiptFillField.tax2),
        ReceiptFieldMarker.of(vm, ReceiptFillField.tax3),
      ],
    );
  }
}

void _apply(
  int slot,
  ValueChanged<String> s1,
  ValueChanged<String> s2,
  ValueChanged<String> s3,
  String v,
) {
  if (slot == 1) {
    s1(v);
  } else if (slot == 2) {
    s2(v);
  } else {
    s3(v);
  }
}
