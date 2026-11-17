import 'package:decimal/decimal.dart';

import 'package:admin/data/models/value/money.dart';

/// How what is unpaid today splits by how late it is — the `aging` object of
/// `POST /api/v1/charts/analytics_totals`, per currency and as the `999`
/// aggregate.
///
/// Server response shape (unwrapped — this endpoint has no `data` envelope):
/// ```
/// {
///   "currencies": { "1": "USD", "2": "GBP" },
///   "start_date": "...", "end_date": "...",
///   "1":   { "aging": { "total": "16870.000000", "current_amount": "…",
///                       "age_0_30": "…", "age_31_60": "…", "age_61_90": "…",
///                       "age_91_120": "…", "age_120_plus": "…",
///                       "outstanding_count": 7, "currency_id": "1" },
///            "mrr": {…}, "recurring_expenses": {…}, "payment_analytics": {…} },
///   "999": { "aging": { …the same, exchange-rate converted… }, … }
/// }
/// ```
///
/// The aging is a snapshot as of today (`AnalyticsQueries::
/// getAgingBucketTotals`): Sent and Partial invoices with a balance, never
/// drafts, bucketed by `due_date` against `CURDATE()`. The request's dates do
/// not enter it. Amounts are strings; a currency with nothing unpaid carries an
/// empty `aging` object (`{}`), and an aggregate over no rows carries nulls —
/// both read as zero.
///
/// [unsupported] is a server that has no such endpoint (an older self-hosted
/// install): the repository caches that answer rather than an error, so the
/// bar stays hidden without a failure to retry.
class DashboardAging {
  const DashboardAging({required this.byCurrency, this.unsupported = false});

  /// What the repository writes when the server has no `analytics_totals`
  /// route. The key cannot collide with a currency id.
  static const String unsupportedMarker = 'aging_unsupported';

  static const DashboardAging none = DashboardAging(
    byCurrency: {},
    unsupported: true,
  );

  /// Per-currency aging, keyed by currency id in string form (`"1"`), plus
  /// the converted aggregate under `"999"`.
  final Map<String, DashboardAgingBuckets> byCurrency;

  /// The server has no aging to give — see the class doc.
  final bool unsupported;

  static DashboardAging fromJson(Map<String, dynamic> json) {
    if (json[unsupportedMarker] == true) return none;
    final byCurrency = <String, DashboardAgingBuckets>{};
    for (final entry in json.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final aging = v['aging'];
      // `currencies` is a map too, but has no `aging` — skipped here.
      if (aging is! Map) continue;
      byCurrency[entry.key] = DashboardAgingBuckets.fromJson(
        aging.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return DashboardAging(byCurrency: byCurrency);
  }
}

/// One currency's aging, as the dashboard shows it: four buckets, the last of
/// which merges the server's three oldest.
class DashboardAgingBuckets {
  const DashboardAgingBuckets({
    required this.total,
    required this.current,
    required this.days1To30,
    required this.days31To60,
    required this.days61To90,
    required this.days91To120,
    required this.days120Plus,
    required this.count,
  });

  /// Everything unpaid in this currency.
  final Decimal total;

  /// Not yet due — no due date, or one today or later.
  final Decimal current;

  /// `age_0_30`: due one to thirty days ago.
  final Decimal days1To30;
  final Decimal days31To60;
  final Decimal days61To90;
  final Decimal days91To120;
  final Decimal days120Plus;

  /// `outstanding_count` — invoices with a balance, drafts never included.
  final int count;

  /// Due more than sixty days ago — the server's three oldest buckets.
  Decimal get days60Plus => days61To90 + days91To120 + days120Plus;

  /// Everything past its due date: every bucket but [current]. Summed from the
  /// buckets, not `total - current`, so the figure is exactly what the bar
  /// draws.
  Decimal get pastDue => days1To30 + days31To60 + days60Plus;

  /// The four buckets the bar draws, in age order.
  List<Decimal> get buckets => [current, days1To30, days31To60, days60Plus];

  static DashboardAgingBuckets fromJson(Map<String, dynamic> json) {
    final countRaw = json['outstanding_count'];
    return DashboardAgingBuckets(
      total: parseMoney(json['total']),
      current: parseMoney(json['current_amount']),
      days1To30: parseMoney(json['age_0_30']),
      days31To60: parseMoney(json['age_31_60']),
      days61To90: parseMoney(json['age_61_90']),
      days91To120: parseMoney(json['age_91_120']),
      days120Plus: parseMoney(json['age_120_plus']),
      count: countRaw is int ? countRaw : int.tryParse('$countRaw') ?? 0,
    );
  }
}
