import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';

/// One currency's share of what is unpaid today.
typedef OutstandingAmount = ({String currencyId, Decimal amount});

/// What the Clients and Invoices lists print as "Outstanding $X · £Y" — the
/// server's per-currency outstanding totals (`POST /charts/totals_v2` over all
/// time, the same row the dashboard's Outstanding figure reads), one entry per
/// currency that has anything unpaid.
///
/// * **null — unknown.** Nothing cached yet. The line is hidden, never drawn
///   as zero (`docs/entity-lists.md` § A list's title row).
/// * **empty — nothing outstanding.** Also hidden.
///
/// The server's `999` bucket is the exchange-rate-converted aggregate of the
/// others, so it is left out: printing it beside them would count every amount
/// twice. The company's own currency leads; the rest keep the server's order.
List<OutstandingAmount>? outstandingByCurrency(
  DashboardTotals? totals, {
  required String baseCurrencyId,
}) {
  if (totals == null) return null;
  final aggregate = kDashboardCurrencyAll.toString();
  final out = <OutstandingAmount>[
    for (final entry in totals.byCurrency.entries)
      if (entry.key != aggregate &&
          entry.value.outstandingAmount != Decimal.zero)
        (currencyId: entry.key, amount: entry.value.outstandingAmount),
  ];
  final base = out.indexWhere((e) => e.currencyId == baseCurrencyId);
  if (base > 0) out.insert(0, out.removeAt(base));
  return out;
}
