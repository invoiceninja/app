import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/ui/core/dialogs/bulk_pick_dialog.dart';
import 'package:admin/ui/features/expense_categories/widgets/expense_category_picker_field.dart';

/// Prep dialog for the expense list's Change Category bulk action (React's
/// `ChangeCategory`, `POST /expenses/bulk action:bulk_categorize`): the
/// searchable category picker, inline create included. Returns the picked
/// category id, or null on cancel.
///
/// A category is required: the server's `categorize` takes an `int`, so a
/// blank `category_id` is a 500, not "no category".
Future<String?> showChangeCategoryDialog(BuildContext context) {
  final companyId = context.read<Services>().auth.currentCompanyId ?? '';
  return showBulkPickDialog(
    context,
    titleKey: 'change_category',
    pickerBuilder: (context, selectedId, onPicked) =>
        ExpenseCategoryPickerField(
          companyId: companyId,
          selectedId: selectedId,
          onChanged: (c) => onPicked(c?.id ?? ''),
        ),
  );
}
