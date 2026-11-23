import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/create_form_documents.dart';
import 'package:admin/ui/core/widgets/attachments_plan_gate.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/expenses/view_models/expense_edit_view_model.dart';

/// The expense form's Documents card. On New Expense: the shared create-form panel
/// ([CreateFormDocumentsPanel], docs/attaching-documents.md) plus a Read
/// receipt button on each file (docs/receipt-ocr.md) — offered while the form
/// can read one, the file hasn't been read, and nothing else is being read; a
/// spinner while this one is.
///
/// Where this device can read a receipt ([ExpenseEditViewModel.canReadReceipt])
/// one line under the title says so — otherwise nothing tells a user that the
/// photo they attach fills the form. Not over the plan-gate banner, which has
/// no files to read.
class ExpenseEditDocumentsSection extends StatelessWidget {
  const ExpenseEditDocumentsSection({super.key, required this.vm});

  final ExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    // A saved expense's own documents (invoiceninja/app#205): no receipt
    // reading there — its fields were filled when it was made.
    if (!vm.offersDocuments) return FormDocumentsCard(vm: vm);
    final panel = CreateFormDocumentsPanel(
      vm: vm,
      receipt: (
        reading: vm.readingReceipt,
        onReadFor: (source) =>
            vm.canReadReceipt &&
                !vm.isReadingReceipt &&
                !vm.receiptWasRead(source)
            ? () => vm.readReceipt(source)
            : null,
      ),
    );
    final hint = vm.canReadReceipt && attachmentsAllowed(context);
    return DashboardCardShell(
      title: context.tr('documents'),
      // Always the same Column, the hint coming and going above the panel:
      // the hint drops out while a save runs, and swapping the panel in and
      // out of a Column would rebuild every file row under it.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint)
            Padding(
              padding: const EdgeInsets.only(bottom: InSpacing.sm),
              child: Text(
                context.tr('receipt_fill_hint'),
                style: TextStyle(color: context.inTheme.ink3, fontSize: 13),
              ),
            ),
          panel,
        ],
      ),
    );
  }
}
