import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/value/money.dart';

/// How a list's per-currency totals line is summed from the rows Drift holds
/// — the fallback for a server without `POST /charts/entity_totals`
/// (docs/entity-lists.md § A money list's totals line). Returned by a DAO's
/// `listTotalsQuery`; `BaseEntityDao.watchListTotals` runs it on top of the
/// active-rows base filter (company, not deleted, not archived).
class ListTotalsQuery {
  const ListTotalsQuery({
    required this.where,
    required this.amount,
    this.less = const [],
    this.figure,
    this.positiveOnly = false,
    this.currency,
    this.clientId,
    this.vendorId,
  });

  /// Which records count, beyond the base filter.
  final Expression<bool> where;

  /// The money column summed.
  final GeneratedColumn<String> amount;

  /// Columns subtracted from [amount] row by row (a payment's `applied` and
  /// `refunded`).
  final List<GeneratedColumn<String>> less;

  /// Each row's figure worked out in Dart, in place of [amount] less [less]
  /// — a payment's unapplied money, which needs its `paymentables` JSON.
  final ListTotalsFigure? figure;

  /// Leave out a row whose figure is zero or below (a payment applied in full).
  final bool positiveOnly;

  /// The record's own `currency_id`, read first.
  final GeneratedColumn<String>? currency;

  /// The client whose currency the record is in when it names none — its own
  /// setting, else its group's.
  final GeneratedColumn<String>? clientId;

  /// The vendor whose currency the record is in when it names none. Read
  /// before [clientId].
  final GeneratedColumn<String>? vendorId;
}

/// [ListTotalsQuery.figure]: the row's figure, from the [reads] columns
/// (selected alongside [ListTotalsQuery.amount]).
typedef ListTotalsFigure = ({
  List<GeneratedColumn<String>> reads,
  Decimal Function(TypedResult row) of,
});

/// The currency a row of [table] is in, as SQL: its own [ListTotalsQuery.currency],
/// else its vendor's, else its client's (the client's own setting, else its
/// group's), else `''` — the company's.
///
/// Correlated subqueries rather than joins, so the query stays a plain
/// `selectOnly` and the predicates the DAOs share with their status tabs keep
/// their unqualified column names. `watchedTables` puts the party tables in
/// the watch, so a client's currency arriving after its documents re-sums.
Expression<String> listTotalsCurrencyExpression(
  AppDatabase db,
  TableInfo<Table, dynamic> table,
  ListTotalsQuery query,
) {
  final t = table.actualTableName;
  final parts = <String>[];
  final watched = <TableInfo<Table, dynamic>>[];
  if (query.currency case final c?) {
    parts.add("NULLIF($t.${c.name}, '')");
  }
  if (query.vendorId case final v?) {
    final vendors = db.vendors.actualTableName;
    parts.add(
      'NULLIF((SELECT lt_v.currency_id FROM $vendors lt_v '
      'WHERE lt_v.company_id = $t.company_id AND lt_v.id = $t.${v.name}), '
      "'')",
    );
    watched.add(db.vendors);
  }
  if (query.clientId case final c?) {
    final clients = db.clients.actualTableName;
    final groups = db.groupSettings.actualTableName;
    parts.add(
      'NULLIF((SELECT COALESCE('
      "NULLIF(CAST(json_extract(lt_c.payload, '\$.settings.currency_id') AS TEXT), ''), "
      "NULLIF(CAST(json_extract(lt_c.payload, '\$.currency_id') AS TEXT), ''), "
      "(SELECT CAST(json_extract(lt_g.payload, '\$.settings.currency_id') AS TEXT) "
      'FROM $groups lt_g WHERE lt_g.company_id = lt_c.company_id '
      'AND lt_g.id = lt_c.group_settings_id)) '
      'FROM $clients lt_c WHERE lt_c.company_id = $t.company_id '
      "AND lt_c.id = $t.${c.name}), '')",
    );
    watched.addAll([db.clients, db.groupSettings]);
  }
  final sql = parts.isEmpty ? "''" : "COALESCE(${parts.join(', ')}, '')";
  return CustomExpression<String>(sql, watchedTables: watched);
}

/// Sums [rows] by currency: each row's amount less its [ListTotalsQuery.less]
/// columns — or its [ListTotalsQuery.figure] — in `Decimal`, skipping
/// non-positive figures when [ListTotalsQuery.positiveOnly]. Currencies keep
/// their first-seen order.
Map<String, Decimal> sumListTotalsRows(
  Iterable<TypedResult> rows,
  ListTotalsQuery query,
  Expression<String> currency,
) {
  final out = <String, Decimal>{};
  for (final row in rows) {
    final amount = switch (query.figure) {
      final figure? => figure.of(row),
      null => query.less.fold(
        parseMoney(row.read(query.amount)),
        (sum, column) => sum - parseMoney(row.read(column)),
      ),
    };
    if (query.positiveOnly && amount <= Decimal.zero) continue;
    final id = row.read(currency) ?? '';
    out[id] = (out[id] ?? Decimal.zero) + amount;
  }
  return out;
}
