import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/form_group_heading.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/recurring_expenses/view_models/recurring_expense_edit_view_model.dart';
import 'package:admin/ui/features/recurring_expenses/widgets/edit/recurring_expense_edit_currency_conversion_section.dart';
import 'package:admin/ui/features/recurring_expenses/widgets/edit/recurring_expense_edit_identity_section.dart';

/// Client and Project, the billing switches and currency conversion, in one
/// card. Mirrors `ExpenseEditInvoicingSection`.
class RecurringExpenseEditInvoicingSection extends StatelessWidget {
  const RecurringExpenseEditInvoicingSection({super.key, required this.vm});
  final RecurringExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    return DashboardCardShell(
      title: context.tr('invoicing'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          RecurringExpenseBillToFields(vm: vm),
          const SizedBox(height: InSpacing.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('should_be_invoiced')),
            value: vm.draft.shouldBeInvoiced,
            onChanged: vm.setShouldBeInvoiced,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('invoice_documents')),
            value: vm.draft.invoiceDocuments,
            onChanged: vm.setInvoiceDocuments,
          ),
          FormGroupHeading(context.tr('currency_conversion')),
          RecurringExpenseEditCurrencyConversionSection(vm: vm),
        ],
      ),
    );
  }
}
