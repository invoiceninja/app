import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/billing/billing_doc_fields.dart';
import 'package:admin/ui/features/billing_shared/view_models/billing_doc_edit_view_model.dart';

/// A billing document's status beside its edit title — title · status ·
/// Unsaved (`EntityEditScaffold.titleTrailing`, wide headers only).
///
/// The SAVED record's calculated status (past due, expired and viewed
/// included), read from the view model's original rather than the draft: a
/// due date typed into the form does not make the document past due until
/// it is saved. Nothing on a create, which has no status yet. [pillFor] is
/// the document's own rounded `StatusPill` wrapper, fed its
/// `calculatedStatusId`.
Widget? billingDocEditStatus<T extends BillingDocFields>(
  BillingDocEditViewModel<T> vm,
  Widget Function(T saved) pillFor,
) {
  final saved = vm.original;
  if (saved == null) return null;
  return Padding(
    padding: const EdgeInsetsDirectional.only(start: InSpacing.sm),
    child: pillFor(saved),
  );
}
