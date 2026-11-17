import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_aging.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';

/// Pick the `DashboardCurrencyTotals` to display from a `DashboardTotals`
/// response. When [key] is null ("All currencies") we render the server's
/// `999` bucket — amounts already exchange-rate-converted to the company base
/// currency. Single-currency companies may omit `999`, so fall back to the
/// sole currency in the map.
DashboardCurrencyTotals? selectCurrencyTotals(
  DashboardTotals? totals,
  String? key,
) {
  if (totals == null || totals.isEmpty) return null;
  if (key != null) return totals.byCurrency[key];
  return totals.byCurrency[kDashboardCurrencyAll.toString()] ??
      totals.byCurrency.values.first;
}

/// Pick the aging buckets for the currency the figures show — the same key
/// [selectCurrencyTotals] takes, so the bar under Outstanding is always in the
/// figure's currency: under "All currencies" (null) the server's converted
/// `999` aggregate.
///
/// Null whenever there is nothing honest to draw: not loaded, a server
/// without the endpoint ([DashboardAging.unsupported]), or no bucket for the
/// selected currency. The bar is then left out, never drawn as zero.
DashboardAgingBuckets? selectAgingBuckets(DashboardAging? aging, String? key) {
  if (aging == null || aging.unsupported || aging.byCurrency.isEmpty) {
    return null;
  }
  if (key != null) return aging.byCurrency[key];
  final all = aging.byCurrency[kDashboardCurrencyAll.toString()];
  if (all != null) return all;
  return aging.byCurrency.length == 1 ? aging.byCurrency.values.first : null;
}

/// Bucket key for the selected currency: null under "All currencies"
/// ([kDashboardCurrencyAll]), whose bucket the server has already
/// exchange-rate-converted to the company base currency. Doubles as the
/// `currencyId` to format that bucket's money with — under "All" the figures
/// really are in the base currency, which is what a null `currencyId` resolves
/// to.
String? selectedCurrencyKey(int selectedCurrencyId) =>
    selectedCurrencyId == kDashboardCurrencyAll ? null : '$selectedCurrencyId';

/// Whether the company transacts in any currency other than its base one.
///
/// The server's `currencies` map (`ChartService::getCurrencyCodes`) is the
/// distinct set of client + expense currencies with the company currency
/// always pushed on, so it holds at least the base currency and a single entry
/// provably means nothing can be exchange-rate-converted. The `999` aggregate
/// bucket never lands in that map, but is filtered defensively so a stray one
/// can't fake a foreign currency.
///
/// Null / empty totals (cold start, decode failure, a server that omits the
/// map) → false: suppress currency-conversion chrome until we know better.
bool hasForeignCurrency(DashboardTotals? totals, String baseCurrencyId) {
  final ids = totals?.currencies.keys;
  if (ids == null) return false;
  return ids.any(
    (id) => id != baseCurrencyId && id != kDashboardCurrencyAll.toString(),
  );
}

/// Period-over-period delta as a percentage. Returns null when either side
/// is null or when the previous period is zero (division would be
/// undefined / infinite, not a real "delta").
double? percentDelta(Decimal? current, Decimal? previous) {
  if (current == null || previous == null) return null;
  if (previous == Decimal.zero) return null;
  final c = current.toDouble();
  final p = previous.toDouble();
  if (p == 0) return null;
  return ((c - p) / p) * 100;
}
