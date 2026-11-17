import 'dart:math' as math;

import 'package:admin/data/models/domain/dashboard/dashboard_chart_series.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart'
    show ChartSeriesId, ChartGrouping;
import 'package:admin/utils/date_ranges.dart';

/// One bar slot of the Cash flow chart: an inclusive span of calendar days.
///
/// A slot is a *period*, not a boundary. The line chart this replaced plotted
/// the web client's boundary dates (`useGenerateWeekDateRange`), where the
/// first point is the window's first day on its own and every later one sums
/// the days since the previous boundary. Drawn as bars that made the first
/// bar one day wide beside bars a week wide — and an invoice dated on the 1st
/// a lone spike. Here each slot is a whole day, week or month, clipped to the
/// window at its two ends.
class ChartPeriod {
  const ChartPeriod(this.start, this.end);

  final Date start;
  final Date end;

  bool get isSingleDay => start == end;

  bool contains(Date d) => d.compareTo(start) >= 0 && d.compareTo(end) <= 0;

  @override
  bool operator ==(Object other) =>
      other is ChartPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ChartPeriod(${start.toIso()}..${end.toIso()})';
}

/// The chart's slots and one value per slot per series, zero-filled: a quiet
/// day keeps its slot, so the spacing of the bars is the spacing of time.
class ChartAxis {
  const ChartAxis({
    required this.buckets,
    required this.values,
    this.grouping = ChartGrouping.month,
  });

  /// The grouping the slots were actually built at — the one asked for, or a
  /// coarser / finer one when that could not draw the window (see
  /// [buildChartAxis]). The chart's Day / Week / Month control shows this, so
  /// it never claims a grouping the plot is not using.
  final ChartGrouping grouping;

  /// Ordered, contiguous periods spanning the window.
  final List<ChartPeriod> buckets;

  /// One value per [buckets] index, per series. An empty slot is `0.0`.
  final Map<ChartSeriesId, List<double>> values;

  bool get isEmpty => buckets.isEmpty;
}

/// The most bars groups the chart draws — a month by day. A grouping that
/// needs more is disabled and the plot coarsens (day → week → month): past
/// this a bar is a few pixels wide on a desktop and a hairline on a phone.
const int kChartMaxBuckets = 31;

/// The fewest slots that still show a shape. One month grouped by month is a
/// single slot — a figure the cards above already state.
const int _minUsefulBuckets = 4;

/// The slots [grouping] cuts `[start, end]` into, honouring the company's
/// [firstDayOfWeek] (0 = Sunday … 6 = Saturday). Empty for an inverted window.
List<ChartPeriod> chartPeriods(
  Date start,
  Date end,
  ChartGrouping grouping, {
  int firstDayOfWeek = 0,
}) {
  final out = <ChartPeriod>[];
  if (start.compareTo(end) > 0) return out;
  var cursor = start;
  // Date-space stepping (`Date.addDays`), never local midnight + 24 h: across
  // a DST change the `DateTime` cursor drifts an hour and drops the last day.
  while (cursor.compareTo(end) <= 0) {
    final natural = switch (grouping) {
      ChartGrouping.day => cursor,
      ChartGrouping.week => endOfWeek(cursor, firstDayOfWeek),
      ChartGrouping.month => _monthEnd(cursor),
    };
    final last = natural.compareTo(end) > 0 ? end : natural;
    out.add(ChartPeriod(cursor, last));
    cursor = last.addDays(1);
  }
  return out;
}

/// Whether [grouping] can draw the window `[start, end]` as it stands: enough
/// slots to show a shape, few enough to read as bars.
bool chartGroupingFits(
  Date start,
  Date end,
  ChartGrouping grouping, {
  int firstDayOfWeek = 0,
}) {
  if (start.compareTo(end) > 0) return false;
  final n = chartPeriods(
    start,
    end,
    grouping,
    firstDayOfWeek: firstDayOfWeek,
  ).length;
  return n >= _minUsefulBuckets && n <= kChartMaxBuckets;
}

/// Buckets [pointsBySeries] — the sparse per-date totals
/// `POST /api/v1/charts/chart_summary_v2` returns — into [grouping]-sized
/// periods over `[startDate, endDate]`.
///
/// The grouping is a request, not a promise: past [kChartMaxBuckets] slots it
/// coarsens (day → week → month), and under four it refines (month → week →
/// day) where the finer one still fits. When even months are too many — "All
/// time" is a fifty-year window — the axis starts at the first month that has
/// data rather than at 1976.
///
/// With no window it falls back to the span of the points' own dates; with
/// nothing datable it returns an empty axis (the card says "no data").
///
/// **The axis stops at [today]** when the window runs past it ("This month" on
/// the 17th): the empty slots after the current one are dropped, and the
/// current slot ends on today, so the last bar is the one still filling up
/// rather than the first of a row of blank future slots. A point dated later
/// (an invoice dated next week) keeps the axis running to it — only *empty*
/// future slots go. The grouping is still chosen on the whole window, so Week
/// does not disable itself halfway through a month. A window that lies wholly
/// in the future is drawn as asked. Null [today] (the tests' default) never
/// trims.
ChartAxis buildChartAxis({
  required Map<ChartSeriesId, List<DashboardChartPoint>> pointsBySeries,
  required Date? startDate,
  required Date? endDate,
  required ChartGrouping grouping,
  int firstDayOfWeek = 0,
  Date? today,
}) {
  Date? lo;
  Date? hi;
  for (final pts in pointsBySeries.values) {
    for (final p in pts) {
      final d = p.date;
      if (d == null) continue;
      if (lo == null || d.compareTo(lo) < 0) lo = d;
      if (hi == null || d.compareTo(hi) > 0) hi = d;
    }
  }
  var start = startDate ?? lo;
  final end = endDate ?? hi;
  if (start == null || end == null || start.compareTo(end) > 0) {
    return const ChartAxis(buckets: [], values: {});
  }

  List<ChartPeriod> cut(ChartGrouping g) =>
      chartPeriods(start!, end, g, firstDayOfWeek: firstDayOfWeek);

  var effective = grouping;
  var buckets = cut(effective);
  while (buckets.length > kChartMaxBuckets &&
      effective != ChartGrouping.month) {
    effective = effective == ChartGrouping.day
        ? ChartGrouping.week
        : ChartGrouping.month;
    buckets = cut(effective);
  }
  while (buckets.length < _minUsefulBuckets && effective != ChartGrouping.day) {
    final finer = effective == ChartGrouping.month
        ? ChartGrouping.week
        : ChartGrouping.day;
    final next = cut(finer);
    if (next.length > kChartMaxBuckets) break;
    effective = finer;
    buckets = next;
  }
  // Still too many at month: drop the empty months before the first point.
  if (buckets.length > kChartMaxBuckets &&
      lo != null &&
      lo.compareTo(start) > 0 &&
      lo.compareTo(end) <= 0) {
    start = Date(lo.year, lo.month, 1).compareTo(start) > 0
        ? Date(lo.year, lo.month, 1)
        : start;
    buckets = cut(effective);
  }
  buckets = _endAtToday(buckets, pointsBySeries, today);

  final values = <ChartSeriesId, List<double>>{
    for (final id in ChartSeriesId.values)
      id: List<double>.filled(buckets.length, 0),
  };
  pointsBySeries.forEach((id, pts) {
    final lane = values[id]!;
    for (final p in pts) {
      final d = p.date;
      if (d == null) continue;
      final idx = _bucketIndex(buckets, d);
      if (idx < 0) continue;
      lane[idx] += p.total.toDouble();
    }
  });

  return ChartAxis(buckets: buckets, values: values, grouping: effective);
}

/// [buckets] without the empty slots after [today] — the last kept slot
/// clipped to end on the later of today and the last dated point in it. See
/// [buildChartAxis].
List<ChartPeriod> _endAtToday(
  List<ChartPeriod> buckets,
  Map<ChartSeriesId, List<DashboardChartPoint>> pointsBySeries,
  Date? today,
) {
  if (today == null || buckets.isEmpty) return buckets;
  // A look-ahead window, or one already over: nothing to trim.
  if (today.compareTo(buckets.first.start) < 0) return buckets;
  if (today.compareTo(buckets.last.end) >= 0) return buckets;
  // The axis runs to today, or to the latest point inside the window if one
  // is dated later.
  var cutoff = today;
  final windowEnd = buckets.last.end;
  for (final pts in pointsBySeries.values) {
    for (final p in pts) {
      final d = p.date;
      if (d == null || d.compareTo(windowEnd) > 0) continue;
      if (d.compareTo(cutoff) > 0) cutoff = d;
    }
  }
  final out = <ChartPeriod>[];
  for (final b in buckets) {
    if (b.start.compareTo(cutoff) > 0) break;
    out.add(b.end.compareTo(cutoff) > 0 ? ChartPeriod(b.start, cutoff) : b);
  }
  return out;
}

/// The slot holding [d], or -1 when it falls outside the window.
int _bucketIndex(List<ChartPeriod> buckets, Date d) {
  var lo = 0;
  var hi = buckets.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final b = buckets[mid];
    if (d.compareTo(b.start) < 0) {
      hi = mid - 1;
    } else if (d.compareTo(b.end) > 0) {
      lo = mid + 1;
    } else {
      return mid;
    }
  }
  return -1;
}

/// A value axis for bars: a round [step] (1, 2, 2.5 or 5 × a power of ten,
/// never under one unit of money) and the multiple of it at or above
/// [rawMax], so the top gridline is a labelled amount and the tallest bar
/// sits under it. At most [maxSteps] gridlines above the baseline.
///
/// Always a whole amount: the axis labels its steps in whole units, so 2.5 is
/// skipped at the one-unit magnitude — it labelled 2.5 and 7.5 as $3 and $8.
({double step, double max}) chartValueScale(double rawMax, {int maxSteps = 4}) {
  if (!(rawMax > 0) || !rawMax.isFinite) return (step: 1, max: 1);
  final rough = rawMax / maxSteps;
  final magnitude = math.max(
    1.0,
    math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble(),
  );
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    final step = m * magnitude;
    if (step != step.roundToDouble()) continue;
    if (rawMax / step <= maxSteps) {
      return (step: step, max: (rawMax / step).ceil() * step);
    }
  }
  final step = 10 * magnitude;
  return (step: step, max: (rawMax / step).ceil() * step);
}

Date _monthEnd(Date d) {
  // Day 0 of the next month is the last day of this one.
  final dt = DateTime(d.year, d.month + 1, 0);
  return Date(dt.year, dt.month, dt.day);
}
