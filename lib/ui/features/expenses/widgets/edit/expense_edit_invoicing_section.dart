import 'package:flutter/widgets.dart';

import 'package:admin/ui/features/expenses/view_models/expense_edit_view_model.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_edit_identity_section.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_invoicing_card.dart';

/// The expense's Invoicing card: the shared [ExpenseInvoicingCard] fed from
/// the view model (Recurring Expense feeds the same card from its own).
class ExpenseEditInvoicingSection extends StatelessWidget {
  const ExpenseEditInvoicingSection({super.key, required this.vm});
  final ExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final d = vm.draft;
    return ExpenseInvoicingCard(
      billTo: ExpenseBillToFields(vm: vm),
      shouldBeInvoiced: d.shouldBeInvoiced,
      onShouldBeInvoicedChanged: vm.setShouldBeInvoiced,
      invoiceDocuments: d.invoiceDocuments,
      onInvoiceDocumentsChanged: vm.setInvoiceDocuments,
      conversion: ExpenseCurrencyConversionFields(
        expenseCurrencyId: d.currencyId,
        invoiceCurrencyId: d.invoiceCurrencyId,
        exchangeRate: d.exchangeRate,
        convertedAmount: d.foreignAmount,
        useCommaAsDecimalPlace: vm.useCommaAsDecimalPlace,
        onInvoiceCurrencyChanged: vm.setInvoiceCurrencyId,
        onExchangeRateChanged: vm.setExchangeRate,
        onConvertedAmountChanged: vm.setForeignAmount,
        errorFor: vm.fieldErrorFor,
      ),
    );
  }
}
