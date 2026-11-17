import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_chart_series.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/ui/features/dashboard/helpers/chart_series_math.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart'
    show ChartSeriesId, ChartGrouping;

DashboardChartPoint _p(String date, num total) => DashboardChartPoint(
  date: Date.tryParse(date),
  total: Decimal.parse(total.toString()),
  currency: '1',
);

/// Contiguous: each period starts the day after the last one ended, and the
/// whole run spans exactly [start]..[end].
void _expectContiguous(List<ChartPeriod> periods, Date start, Date end) {
  expect(periods, isNotEmpty);
  expect(periods.first.start, start);
  expect(periods.last.end, end);
  for (var i = 0; i < periods.length; i++) {
    expect(periods[i].start.compareTo(periods[i].end), lessThanOrEqualTo(0));
    if (i > 0) expect(periods[i].start, periods[i - 1].end.addDays(1));
  }
}

double _sum(List<double> lane) => lane.fold(0, (a, b) => a + b);

void main() {
  group('chartPeriods', () {
    test('day: one period per day', () {
      final p = chartPeriods(
        const Date(2026, 1, 1),
        const Date(2026, 1, 5),
        ChartGrouping.day,
      );
      expect(p.length, 5);
      expect(p.every((d) => d.isSingleDay), isTrue);
      _expectContiguous(p, const Date(2026, 1, 1), const Date(2026, 1, 5));
    });

    // The line chart's web-client boundaries made the first slot the window's
    // first day alone. As a bar that was a one-day spike beside week-wide
    // bars; a period is a whole week, clipped only at the window's edges.
    test('week: whole weeks, clipped at the window edges', () {
      // 2026-04-01 is a Wednesday; weeks start on Sunday (0).
      final p = chartPeriods(
        const Date(2026, 4, 1),
        const Date(2026, 4, 30),
        ChartGrouping.week,
      );
      expect(p.first, const ChartPeriod(Date(2026, 4, 1), Date(2026, 4, 4)));
      expect(p[1], const ChartPeriod(Date(2026, 4, 5), Date(2026, 4, 11)));
      expect(p.last, const ChartPeriod(Date(2026, 4, 26), Date(2026, 4, 30)));
      expect(p.length, 5);
      _expectContiguous(p, const Date(2026, 4, 1), const Date(2026, 4, 30));
    });

    test('week honours the company first day of week', () {
      final p = chartPeriods(
        const Date(2026, 4, 1),
        const Date(2026, 4, 30),
        ChartGrouping.week,
        firstDayOfWeek: 1, // Monday
      );
      expect(p.first.end, const Date(2026, 4, 5)); // a Sunday
      expect(p[1].start, const Date(2026, 4, 6)); // a Monday
    });

    test('month: calendar months, partial at the ends', () {
      final p = chartPeriods(
        const Date(2026, 1, 15),
        const Date(2026, 3, 20),
        ChartGrouping.month,
      );
      expect(p, const [
        ChartPeriod(Date(2026, 1, 15), Date(2026, 1, 31)),
        ChartPeriod(Date(2026, 2, 1), Date(2026, 2, 28)),
        ChartPeriod(Date(2026, 3, 1), Date(2026, 3, 20)),
      ]);
    });

    test('an inverted window has no periods', () {
      expect(
        chartPeriods(
          const Date(2026, 5, 1),
          const Date(2026, 4, 1),
          ChartGrouping.day,
        ),
        isEmpty,
      );
    });
  });

  group('buildChartAxis', () {
    test('zero-fills the window: an empty slot keeps its place', () {
      final axis = buildChartAxis(
        pointsBySeries: {
          ChartSeriesId.expenses: [_p('2026-01-03', 100)],
          ChartSeriesId.invoices: const [],
        },
        startDate: const Date(2026, 1, 1),
        endDate: const Date(2026, 1, 5),
        grouping: ChartGrouping.day,
      );
      expect(axis.buckets.length, 5);
      expect(axis.values[ChartSeriesId.expenses], [0, 0, 100, 0, 0]);
      expect(axis.values[ChartSeriesId.invoices], [0, 0, 0, 0, 0]);
      expect(axis.values[ChartSeriesId.payments], [0, 0, 0, 0, 0]);
    });

    test('sums the points that fall in one period', () {
      final axis = buildChartAxis(
        pointsBySeries: {
          ChartSeriesId.payments: [
            _p('2026-04-01', 10), // the window's first day
            _p('2026-04-03', 5), // same week
            _p('2026-04-12', 7), // the third week (Apr 12–18)
          ],
        },
        startDate: const Date(2026, 4, 1),
        endDate: const Date(2026, 4, 30),
        grouping: ChartGrouping.week,
      );
      final lane = axis.values[ChartSeriesId.payments]!;
      expect(lane[0], 15, reason: 'the first day is part of its week');
      expect(lane[2], 7);
      expect(_sum(lane), 22);
    });

    test('drops points outside the window and points with no date', () {
      final axis = buildChartAxis(
        pointsBySeries: {
          ChartSeriesId.invoices: [
            _p('2026-03-31', 999),
            _p('2026-04-02', 3),
            _p('not a date', 999),
            _p('2026-05-01', 999),
          ],
        },
        startDate: const Date(2026, 4, 1),
        endDate: const Date(2026, 4, 7),
        grouping: ChartGrouping.day,
      );
      expect(_sum(axis.values[ChartSeriesId.invoices]!), 3);
    });

    test('derives the window from the points when start/end are null', () {
      final axis = buildChartAxis(
        pointsBySeries: {
          ChartSeriesId.payments: [_p('2026-03-10', 5), _p('2026-03-13', 7)],
        },
        startDate: null,
        endDate: null,
        grouping: ChartGrouping.day,
      );
      expect(axis.buckets.first.start, const Date(2026, 3, 10));
      expect(axis.buckets.last.end, const Date(2026, 3, 13));
      expect(axis.values[ChartSeriesId.payments], [5, 0, 0, 7]);
    });

    test('empty when there is nothing datable to plot', () {
      final axis = buildChartAxis(
        pointsBySeries: const {ChartSeriesId.invoices: []},
        startDate: null,
        endDate: null,
        grouping: ChartGrouping.day,
      );
      expect(axis.isEmpty, isTrue);
    });
  });

  // The grouping is a request: the chart draws the nearest one that has
  // between four and [kChartMaxBuckets] slots.
  group('the grouping that fits', () {
    Map<ChartSeriesId, List<DashboardChartPoint>> points() => {
      ChartSeriesId.invoices: [_p('2026-04-08', 100), _p('2026-04-22', 50)],
    };

    test('one month by month is one slot — drawn by week, and says so', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 4, 1),
        endDate: const Date(2026, 4, 30),
        grouping: ChartGrouping.month,
      );
      expect(axis.grouping, ChartGrouping.week);
      expect(axis.buckets.length, greaterThanOrEqualTo(4));
      expect(_sum(axis.values[ChartSeriesId.invoices]!), 150);
    });

    test('a week by month goes all the way down to days', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 4, 6),
        endDate: const Date(2026, 4, 12),
        grouping: ChartGrouping.month,
      );
      expect(axis.grouping, ChartGrouping.day);
      expect(axis.buckets.length, 7);
    });

    test('a year by month is left alone', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 1, 1),
        endDate: const Date(2026, 12, 31),
        grouping: ChartGrouping.month,
      );
      expect(axis.grouping, ChartGrouping.month);
      expect(axis.buckets.length, 12);
    });

    test('a year by day is too many bars — coarsened to months', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 1, 1),
        endDate: const Date(2026, 12, 31),
        grouping: ChartGrouping.day,
      );
      // 365 days and 53 weeks are both past the cap.
      expect(axis.grouping, ChartGrouping.month);
      expect(axis.buckets.length, lessThanOrEqualTo(kChartMaxBuckets));
      expect(_sum(axis.values[ChartSeriesId.invoices]!), 150);
    });

    test('a quarter by day is drawn by week', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 4, 1),
        endDate: const Date(2026, 6, 30),
        grouping: ChartGrouping.day,
      );
      expect(axis.grouping, ChartGrouping.week);
      expect(axis.buckets.length, lessThanOrEqualTo(kChartMaxBuckets));
    });

    test('a 31-day month by day fits exactly', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 5, 1),
        endDate: const Date(2026, 5, 31),
        grouping: ChartGrouping.day,
      );
      expect(axis.grouping, ChartGrouping.day);
      expect(axis.buckets.length, 31);
    });

    test('a single day cannot be refined past days', () {
      final axis = buildChartAxis(
        pointsBySeries: points(),
        startDate: const Date(2026, 4, 8),
        endDate: const Date(2026, 4, 8),
        grouping: ChartGrouping.month,
      );
      expect(axis.grouping, ChartGrouping.day);
      expect(axis.buckets.length, 1);
    });

    // "All time" is a fifty-year window: six hundred months of bars, nearly
    // all of them before the company existed.
    test('too many months starts at the first month with data', () {
      final axis = buildChartAxis(
        pointsBySeries: {
          ChartSeriesId.invoices: [_p('2025-03-14', 10), _p('2026-04-02', 5)],
        },
        startDate: const Date(1976, 1, 1),
        endDate: const Date(2026, 4, 30),
        grouping: ChartGrouping.month,
      );
      expect(axis.grouping, ChartGrouping.month);
      expect(axis.buckets.first.start, const Date(2025, 3, 1));
      expect(axis.buckets.last.end, const Date(2026, 4, 30));
      expect(axis.buckets.length, 14);
      expect(_sum(axis.values[ChartSeriesId.invoices]!), 15);
    });
  });

  group('chartGroupingFits', () {
    test('a month fits days and weeks, not months', () {
      const start = Date(2026, 4, 1);
      const end = Date(2026, 4, 30);
      expect(chartGroupingFits(start, end, ChartGrouping.day), isTrue);
      expect(chartGroupingFits(start, end, ChartGrouping.week), isTrue);
      expect(chartGroupingFits(start, end, ChartGrouping.month), isFalse);
    });

    test('a year fits months, not weeks or days', () {
      const start = Date(2026, 1, 1);
      const end = Date(2026, 12, 31);
      expect(chartGroupingFits(start, end, ChartGrouping.month), isTrue);
      expect(chartGroupingFits(start, end, ChartGrouping.week), isFalse);
      expect(chartGroupingFits(start, end, ChartGrouping.day), isFalse);
    });

    test('an inverted window fits nothing', () {
      expect(
        chartGroupingFits(
          const Date(2026, 5, 1),
          const Date(2026, 4, 1),
          ChartGrouping.day,
        ),
        isFalse,
      );
    });
  });

  group('chartValueScale', () {
    test('a round step, and a top that is a step above the tallest bar', () {
      final s = chartValueScale(15800);
      expect(s.step, 5000);
      expect(s.max, 20000);
    });

    test('at most four steps', () {
      for (final raw in [1.0, 7.0, 99.0, 420.0, 4001.0, 123456.0, 9.9e6]) {
        final s = chartValueScale(raw);
        expect(s.max, greaterThanOrEqualTo(raw), reason: '$raw');
        expect(s.max / s.step, lessThanOrEqualTo(4), reason: '$raw');
      }
    });

    test('never a step under one unit of money', () {
      final s = chartValueScale(0.4);
      expect(s.step, 1);
      expect(s.max, 1);
    });

    test('nothing to scale is a one-unit axis', () {
      expect(chartValueScale(0), (step: 1.0, max: 1.0));
    });
  });
}
