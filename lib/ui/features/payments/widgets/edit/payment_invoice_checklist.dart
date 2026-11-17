import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_allocations_section.dart';

/// Above this many invoices the Apply table offers a filter field
/// (`payment_apply_invoices.dart`).
const int kInvoiceChecklistFilterThreshold = 6;

/// The allocations once the Apply table's ticks are [selected]:
///
/// - an invoice row whose target was unticked is removed — only rows for
///   [targets]; an allocation to an invoice the list doesn't offer (already
///   paid off, say, on an existing payment) is not the checklist's to drop;
/// - a kept row keeps its amount, and its place;
/// - each newly ticked invoice is appended in the order it was ticked
///   ([selected] is insertion-ordered), auto-filled the way a row picker
///   would fill it ([computeAutoFillAmount]) — in full while no amount is
///   fixed, else capped by what is left of [paymentAmount];
/// - an invoice that cap leaves nothing for is not added: the server refuses
///   a zero allocation on a sent invoice ("Amount cannot be less than or
///   equal to zero", `ValidInvoicesRules`), so the save would fail. The
///   table stops offering rows once the amount is used up, so this only
///   catches what it couldn't;
/// - credit rows are untouched.
List<Paymentable> applyInvoiceSelection({
  required List<Paymentable> paymentables,
  required List<AllocationTarget> targets,
  required Set<String> selected,
  required Decimal paymentAmount,
}) {
  final byId = {for (final t in targets) t.id: t};
  final next = [
    for (final p in paymentables)
      if (p.invoiceId.isEmpty ||
          !byId.containsKey(p.invoiceId) ||
          selected.contains(p.invoiceId))
        p,
  ];
  final present = {
    for (final p in next)
      if (p.invoiceId.isNotEmpty) p.invoiceId,
  };
  for (final id in selected) {
    final t = byId[id];
    if (t == null || present.contains(id)) continue;
    final allocated = next
        .where((p) => p.invoiceId.isNotEmpty)
        .fold<Decimal>(Decimal.zero, (sum, p) => sum + p.amount);
    final amount = computeAutoFillAmount(
      kind: AllocationKind.invoice,
      target: t,
      paymentAmount: paymentAmount,
      allocatedExcludingThisRow: allocated,
    );
    if (amount <= Decimal.zero) continue;
    next.add(
      Paymentable(invoiceId: id, amount: amount, refunded: Decimal.zero),
    );
  }
  return next;
}
