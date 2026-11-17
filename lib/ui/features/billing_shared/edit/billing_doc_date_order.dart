import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/data/models/domain/billing/billing_doc_fields.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';

/// What a date breaking the order is told: it is earlier than the document
/// date, or not earlier than the due date.
enum BillingDateOrderError { beforeDate, notBeforeDueDate }

/// The two messages [BillingDateOrderError] reads as, worded for [type]'s
/// own labels ("Can't be earlier than the Quote Date"). Built where a
/// `BuildContext` is — the edit screen hands them to its view model, which
/// has none — and by the layout for the live inline error.
typedef BillingDateOrderMessages = ({String beforeDate, String notBeforeDue});

BillingDateOrderMessages billingDateOrderMessages(
  BuildContext context,
  BillingDocType type,
) => (
  beforeDate: context.tr('date_cannot_be_earlier_than', {
    'field': context.tr(type.dateLabelKey ?? 'date'),
  }),
  notBeforeDue: context.tr('date_must_be_earlier_than', {
    'field': context.tr(type.dueDateLabelKey ?? 'due_date'),
  }),
);

String billingDateOrderMessage(
  BillingDateOrderMessages messages,
  BillingDateOrderError error,
) => switch (error) {
  BillingDateOrderError.beforeDate => messages.beforeDate,
  BillingDateOrderError.notBeforeDueDate => messages.notBeforeDue,
};

/// The dates on [draft] the server's update rules would refuse, keyed by
/// their API field — empty unless [BillingDocType.validatesDateOrder].
///
/// `Update{Invoice,Quote}Request`: `due_date` is `after_or_equal:date`;
/// `partial_due_date` is `after_or_equal:date` and `before:due_date` — a
/// strict before, so a partial due ON the due date is refused too. The
/// partial due date is only checked while a partial is set: the server
/// excludes it at a zero partial (`exclude_if:partial,0`) and nulls it. A
/// blank date checks nothing — the server fills a blank due date from the
/// payment terms.
Map<String, BillingDateOrderError> billingDocDateOrderErrors(
  BillingDocType type,
  BillingDocFields draft,
) {
  if (!type.validatesDateOrder) return const {};
  final date = draft.date;
  final due = draft.dueDate;
  bool before(Date a, Date b) => a.compareTo(b) < 0;
  final errors = <String, BillingDateOrderError>{};
  if (date != null && due != null && before(due, date)) {
    errors['due_date'] = BillingDateOrderError.beforeDate;
  }
  if (draft is BillingDocPartialFields && draft.partial != Decimal.zero) {
    final partialDue = draft.partialDueDate;
    if (partialDue != null) {
      if (date != null && before(partialDue, date)) {
        errors['partial_due_date'] = BillingDateOrderError.beforeDate;
      } else if (due != null && !before(partialDue, due)) {
        errors['partial_due_date'] = BillingDateOrderError.notBeforeDueDate;
      }
    }
  }
  return errors;
}

/// [billingDocDateOrderErrors] as `validate()` reports it — the view model's
/// save-time block, the same rule the fields show live.
Map<String, List<String>> billingDocDateOrderValidation(
  BillingDocType type,
  BillingDocFields draft,
  BillingDateOrderMessages? messages,
) {
  if (messages == null) return const {};
  return {
    for (final MapEntry(:key, :value) in billingDocDateOrderErrors(
      type,
      draft,
    ).entries)
      key: [billingDateOrderMessage(messages, value)],
  };
}
