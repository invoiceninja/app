import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';

// The figures maths lives in the domain so the home-screen widget snapshot
// can share it without importing `lib/ui`.
export 'package:admin/domain/dashboard/totals_math.dart';

/// The Cash flow card's "Net received": the period's payments less its
/// expenses, read off the very bucket the Payments and Expenses figure cards
/// show ([bucket], picked by `selectCurrencyTotals` for the selected currency),
/// so the headline can never disagree with the two cards above it. Without the
/// expenses module there is nothing to take off: it is the payments.
///
/// A missing bucket is a real zero, as on the figure cards — the totals did
/// load. The caller hides the line while they have not (unknown is not zero).
Decimal netReceived(
  DashboardCurrencyTotals? bucket, {
  required bool expensesOn,
}) {
  final paid = bucket?.revenuePaidToDate ?? Decimal.zero;
  if (!expensesOn) return paid;
  return paid - (bucket?.expensesAmount ?? Decimal.zero);
}
