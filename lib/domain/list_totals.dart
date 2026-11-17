import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/data/models/value/money.dart';
import 'package:admin/domain/entity_type.dart';

/// One currency's share of a list's totals line.
typedef CurrencyAmount = ({String currencyId, Decimal amount});

/// Per-currency totals behind a list's totals line, keyed by currency id.
///
/// The key `''` means "the company's currency" — a local sum over records
/// whose party names none — and [orderedCurrencyTotals] folds it into the
/// company currency's own entry.
typedef CurrencyTotals = Map<String, Decimal>;

/// Where a list's figure comes from.
enum ListTotalsOrigin {
  /// The dashboard's own outstanding row (`POST /charts/totals_v2`, drafts
  /// left out), already exact — Clients and Invoices.
  dashboardOutstanding,

  /// `POST /charts/entity_totals` where the server has it, else a sum over the
  /// rows Drift holds — every other money list.
  entityTotals,
}

/// What one list's totals line says: its label and where the figure is read.
class ListTotalsSpec {
  const ListTotalsSpec({
    required this.labelKey,
    required this.wireEntity,
    this.origin = ListTotalsOrigin.entityTotals,
  });

  /// Localization key of the label in front of the amounts.
  final String labelKey;

  /// The `entity` the server's `charts/entity_totals` is asked for, and the
  /// cache row's key.
  final String wireEntity;

  final ListTotalsOrigin origin;
}

/// Every list that draws a totals line, and nothing else: Vendors, Products,
/// Projects, Tasks, Transactions and Documents carry no money figure that
/// reads unambiguously yet (docs/entity-lists.md § A money list's totals
/// line). The definitions — which records, which amount — live in each DAO's
/// `listTotalsQuery`, and the server's endpoint uses the same ones.
const Map<EntityType, ListTotalsSpec> kListTotals = {
  EntityType.client: ListTotalsSpec(
    labelKey: 'outstanding',
    wireEntity: 'clients',
    origin: ListTotalsOrigin.dashboardOutstanding,
  ),
  EntityType.invoice: ListTotalsSpec(
    labelKey: 'outstanding',
    wireEntity: 'invoices',
    origin: ListTotalsOrigin.dashboardOutstanding,
  ),
  EntityType.quote: ListTotalsSpec(labelKey: 'open', wireEntity: 'quotes'),
  EntityType.credit: ListTotalsSpec(
    labelKey: 'credit_balance',
    wireEntity: 'credits',
  ),
  EntityType.payment: ListTotalsSpec(
    labelKey: 'unapplied',
    wireEntity: 'payments',
  ),
  EntityType.recurringInvoice: ListTotalsSpec(
    labelKey: 'active',
    wireEntity: 'recurring_invoices',
  ),
  EntityType.purchaseOrder: ListTotalsSpec(
    labelKey: 'open',
    wireEntity: 'purchase_orders',
  ),
  EntityType.expense: ListTotalsSpec(
    labelKey: 'uninvoiced',
    wireEntity: 'expenses',
  ),
  EntityType.recurringExpense: ListTotalsSpec(
    labelKey: 'active',
    wireEntity: 'recurring_expenses',
  ),
};

/// The per-currency outstanding amounts in a `totals_v2` answer, or null while
/// nothing is cached. The server's `999` bucket is the exchange-rate-converted
/// aggregate of the others, so it is left out: printing it beside them would
/// count every amount twice.
CurrencyTotals? outstandingTotalsOf(DashboardTotals? totals) {
  if (totals == null) return null;
  final aggregate = kDashboardCurrencyAll.toString();
  return {
    for (final entry in totals.byCurrency.entries)
      if (entry.key != aggregate) entry.key: entry.value.outstandingAmount,
  };
}

/// The `data` of a `charts/entity_totals` answer —
/// `{"<currency_id>": {"amount": "123.45", "count": 3}, ...}` — or null when
/// it is not that shape (then the figure is unknown, never zero). An amount
/// may arrive as a number or a string.
CurrencyTotals? parseEntityTotals(Object? data) {
  // An empty JSON object can arrive as `[]` from PHP.
  if (data is List && data.isEmpty) return const {};
  if (data is! Map) return null;
  final out = <String, Decimal>{};
  for (final entry in data.entries) {
    final value = entry.value;
    if (value is! Map) return null;
    final amount = value['amount'];
    if (amount == null) return null;
    out[entry.key.toString()] = parseMoney(amount);
  }
  return out;
}

/// What the line prints, in order: one entry per currency whose total is not
/// zero, the company's own currency first, the rest in [totals]' order.
///
/// * **null — unknown.** The line is hidden, never drawn as zero.
/// * **empty — nothing to show.** Also hidden.
///
/// The `''` key (a local sum over records that name no currency) is the
/// company's currency and is added into [baseCurrencyId]'s entry; the server's
/// `999` aggregate is dropped wherever it appears.
List<CurrencyAmount>? orderedCurrencyTotals(
  CurrencyTotals? totals, {
  required String baseCurrencyId,
}) {
  if (totals == null) return null;
  final aggregate = kDashboardCurrencyAll.toString();
  final merged = <String, Decimal>{};
  for (final entry in totals.entries) {
    if (entry.key == aggregate) continue;
    final id = entry.key.isEmpty ? baseCurrencyId : entry.key;
    merged[id] = (merged[id] ?? Decimal.zero) + entry.value;
  }
  final out = <CurrencyAmount>[
    for (final entry in merged.entries)
      if (entry.value != Decimal.zero)
        (currencyId: entry.key, amount: entry.value),
  ];
  final base = out.indexWhere((e) => e.currencyId == baseCurrencyId);
  if (base > 0) out.insert(0, out.removeAt(base));
  return out;
}
