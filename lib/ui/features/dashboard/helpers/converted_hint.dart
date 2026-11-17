import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/dashboard/helpers/totals_math.dart';
import 'package:admin/utils/formatting.dart';

/// The "Converted to :currency" caption for a money figure the server
/// exchange-rate-converted into the company base currency — or null when there
/// is nothing to flag.
///
/// Three conditions, all required:
///   * "All currencies" is selected. Only the `999` bucket is converted
///     (`SUM(amount / exchange_rate)` server-side); a specific currency renders
///     native amounts, untouched.
///   * The company actually trades in a second currency
///     ([hasForeignCurrency]). A GBP-only company was being told its untouched
///     GBP totals were "Converted to GBP", which reads as a caveat about
///     numbers nothing ever happened to (flutter#22).
///   * The base currency code resolves out of statics (cold-start guard).
///
/// Takes plain values rather than the `DashboardViewModel` so it stays
/// unit-testable and serves both the wide and mobile layouts. This is the only
/// place in `lib/` allowed to reference the `converted_to_currency` key — the
/// guard living in four copies is how it drifted in the first place
/// (`test/lint/converted_hint_single_source_test.dart` enforces that).
String? convertedToBaseCaption(
  BuildContext context, {
  required int selectedCurrencyId,
  required DashboardTotals? totals,
  required Formatter formatter,
}) {
  if (selectedCurrencyId != kDashboardCurrencyAll) return null;
  final baseId = formatter.settings.currencyId;
  if (!hasForeignCurrency(totals, baseId)) return null;
  final baseCode = formatter.currencies[baseId]?.code ?? '';
  if (baseCode.isEmpty) return null;
  return context.tr('converted_to_currency', {'currency': baseCode});
}

/// "≈ $1,231.00" — a foreign-currency document's [amount] in the company's
/// currency, for the muted line under a table row's amount. Null when there is
/// nothing honest to say.
///
/// Uses the document's **stored** `exchange_rate`, the rate the server's own
/// "All currencies" totals divide by (`SUM(balance / exchange_rate)`,
/// `ChartQueries`), so the row and the figures above it agree. Not today's
/// rate: that would be a third number matching neither.
///
/// Null when:
///   * the document is in the company currency ([documentCurrencyId] empty or
///     unresolved means it is — `PartyCurrencyBuilder` answers null until the
///     client's currency is known, and the amount itself is then formatted in
///     the company currency);
///   * [exchangeRate] is missing (zero or negative), or exactly 1 between two
///     different currencies — the server's default for a rate that was never
///     set, so dividing by it would print the foreign figure under a base
///     symbol: a wrong number, which is worse than none;
///   * [amount] is zero, where the line would say nothing.
String? approxInBaseCurrency({
  required Formatter formatter,
  required Decimal amount,
  required String? documentCurrencyId,
  required Decimal exchangeRate,
}) {
  final baseId = formatter.settings.currencyId;
  final docId = documentCurrencyId ?? '';
  if (docId.isEmpty || docId == baseId) return null;
  if (exchangeRate <= Decimal.zero || exchangeRate == Decimal.one) return null;
  if (amount == Decimal.zero) return null;
  final base = (amount / exchangeRate).toDecimal(scaleOnInfinitePrecision: 10);
  final text = formatter.money(base, currencyId: baseId);
  if (text.isEmpty) return null;
  return '≈ $text';
}
