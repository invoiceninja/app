import 'package:flutter/widgets.dart';

import 'package:admin/ui/features/expenses/widgets/edit/expense_invoicing_card.dart';
import 'package:admin/ui/features/recurring_expenses/view_models/recurring_expense_edit_view_model.dart';
import 'package:admin/ui/features/recurring_expenses/widgets/edit/recurring_expense_edit_identity_section.dart';

/// The recurring expense's Invoicing card: the expense form's shared
/// [ExpenseInvoicingCard], fed from this view model.
class RecurringExpenseEditInvoicingSection extends StatelessWidget {
  const RecurringExpenseEditInvoicingSection({super.key, required this.vm});
  final RecurringExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final d = vm.draft;
    return ExpenseInvoicingCard(
      billTo: RecurringExpenseBillToFields(vm: vm),
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
