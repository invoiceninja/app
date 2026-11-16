import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/form_group_heading.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/expenses/view_models/expense_edit_view_model.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_edit_currency_conversion_section.dart';
import 'package:admin/ui/features/expenses/widgets/edit/expense_edit_identity_section.dart';

/// Everything about billing the expense on, in one card: who it is billed to
/// (Client, Project), whether it is (`should_be_invoiced`, `invoice_documents`),
/// and in what currency (Invoice currency, and the rate once it differs). These
/// were three cards in two columns.
class ExpenseEditInvoicingSection extends StatelessWidget {
  const ExpenseEditInvoicingSection({super.key, required this.vm});
  final ExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    return DashboardCardShell(
      title: context.tr('invoicing'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpenseBillToFields(vm: vm),
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
          ExpenseEditCurrencyConversionSection(vm: vm),
        ],
      ),
    );
  }
}
