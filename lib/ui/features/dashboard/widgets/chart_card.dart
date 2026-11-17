import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_chart_series.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/charts/chart_chrome.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/features/dashboard/helpers/chart_series_math.dart';
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/ui/features/dashboard/helpers/totals_math.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';

/// Floor of the plot's height when it fills its card rather than keeping an
/// aspect ratio — what the card asks for when the row's other card is shorter.
const double kChartMinPlotHeight = 220;

/// The stacked plot's floor. A phone's width over the aspect ratio is ~120 px,
/// too short to read a bar's height against its neighbour's.
const double kChartStackedMinPlotHeight = 200;

/// "Cash flow" — the period's invoiced amounts, payments and expenses per
/// day, week or month, as grouped bars, with a legend that switches each
/// series on and off.
///
/// **It has no headline figure, and its legend no totals.** The figures above
/// it already state the period's sums; the chart's job is their shape.
///
/// **Beside the activity feed it fills the row's height** ([fillHeight]), so
/// the two cards end on one line with their contents, not just their borders.
/// Stacked, it keeps its own proportions above a floor.
///
/// **Its states are the figures' states** (`ValueSectionState`): a skeleton
/// until the series has answered, a retry when the fetch failed with nothing
/// cached, and "no data" only for a series that loaded and is empty.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.vm,
    required this.formatter,
    this.fillHeight = false,
    this.legendMayJoinHeader = true,
    this.expensesOn = true,
  });

  final DashboardViewModel vm;
  final Formatter formatter;

  /// Whether Compact may move the legend into the header row. The phone body
  /// passes false: its header has room for the title and the grouping only.
  final bool legendMayJoinHeader;

  /// Take the height the parent gives (it must be bounded) instead of sizing
  /// the plot by aspect ratio.
  final bool fillHeight;

  /// Whether the company has the expenses module. Off, the Expenses series is
  /// neither drawn nor offered in the legend.
  final bool expensesOn;

  /// The series this company can chart, in legend order.
  List<ChartSeriesId> get _available => [
    ChartSeriesId.invoices,
    ChartSeriesId.payments,
    if (expensesOn) ChartSeriesId.expenses,
  ];

  /// The series drawn: the legend's selection among [_available].
  List<ChartSeriesId> get _shown => [
    for (final id in _available)
      if (vm.visibleChartSeries.contains(id)) id,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final series = vm.chart.data;
    final currencyKey = selectedCurrencyKey(vm.filter.currencyId);
    final byCurrency = _selectCurrency(series, currencyKey);

    final pointsBySeries = <ChartSeriesId, List<DashboardChartPoint>>{
      ChartSeriesId.invoices: byCurrency?.invoices ?? const [],
      ChartSeriesId.payments: byCurrency?.payments ?? const [],
      ChartSeriesId.expenses: byCurrency?.expenses ?? const [],
    };
    final axis = buildChartAxis(
      pointsBySeries: pointsBySeries,
      startDate: series?.startDate,
      endDate: series?.endDate,
      grouping: vm.chartGrouping,
      firstDayOfWeek: formatter.settings.firstDayOfWeek,
    );
    final shown = _shown;

    final Widget plot = switch (vm.chart.valueState) {
      ValueSectionState.loading => _loadingSkeleton(tokens),
      ValueSectionState.failed => _failed(context, tokens),
      ValueSectionState.stale || ValueSectionState.ready => _chart(
        context,
        tokens,
        axis,
        currencyKey,
        shown,
        // The axis is zero-filled across the whole window, so "nothing
        // happened" has to be read off the points, not the slots — or a quiet
        // period draws a row of empty slots instead of saying so.
        hasPoints: shown.any(
          (id) => (pointsBySeries[id] ?? const []).isNotEmpty,
        ),
      ),
    };

    // Compact (`docs/list-density.md` § The dashboard): on the wide layout the
    // legend joins the header row, and the plot gives up some of its floor.
    // A phone keeps the legend in the body — its header has no room.
    final dense = dashboardDense(context);
    final legendInHeader = dense && legendMayJoinHeader;
    final body = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: dense ? InSpacing.sm : InSpacing.md(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (!legendInHeader) ...[
            _legend(context, tokens, shown),
            SizedBox(height: InSpacing.md(context)),
          ],
          if (fillHeight)
            // The plot is a POSITIONED child, and that is load-bearing. The
            // host lays this card out beside the activity feed with
            // `IntrinsicHeight`, and fl_chart's plot is a `LayoutBuilder`,
            // which cannot answer an intrinsic-size query — asked, it throws
            // and the whole row paints nothing. A `Stack` measures only its
            // non-positioned children, so the row sees the floor below and the
            // plot is never asked; it then fills whatever height the row
            // settles on.
            Expanded(
              child: Stack(
                children: [
                  SizedBox(
                    height: dense
                        ? kChartMinPlotHeightDense
                        : kChartMinPlotHeight,
                    width: double.infinity,
                  ),
                  Positioned.fill(child: plot),
                ],
              ),
            )
          else
            // A floor under the ratio: on a phone the ratio alone is ~120 px.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kChartStackedMinPlotHeight,
              ),
              child: AspectRatio(
                aspectRatio: !dense ? 2.4 : (legendMayJoinHeader ? 3.2 : 3.0),
                child: plot,
              ),
            ),
        ],
      ),
    );

    // The card's own frame rather than `DashboardCardShell`: that shell lays
    // its child out at the child's own height, so nothing inside it can fill
    // a taller row. The decoration and header band are the shell's, so the
    // chart and the Activity card beside it read as one pair.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(dashboardCardRadius(context)),
        border: Border.all(color: tokens.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _header(
              context,
              tokens,
              series,
              axis,
              shown,
              legendInHeader: legendInHeader,
            ),
            Divider(height: 1, thickness: 1, color: tokens.border),
            if (fillHeight) Expanded(child: body) else body,
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    InTheme tokens,
    DashboardChartSeries? series,
    ChartAxis axis,
    List<ChartSeriesId> shown, {
    required bool legendInHeader,
  }) {
    final vertical = legendInHeader ? InSpacing.sm : InSpacing.md(context);
    final title = Text(
      context.tr('cash_flow'),
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: tokens.ink,
        fontWeight: FontWeight.w600,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        InSpacing.lg(context),
        vertical,
        InSpacing.lg(context),
        vertical,
      ),
      child: Row(
        children: [
          if (legendInHeader) ...[
            title,
            SizedBox(width: InSpacing.md(context)),
            // A `Wrap`, which answers an intrinsic height for its width, so a
            // narrow card wraps the legend to two lines inside the header
            // rather than overflowing — and the `IntrinsicHeight` row this card
            // sits in can still measure it.
            Expanded(child: _legend(context, tokens, shown)),
          ] else
            Expanded(child: title),
          const SizedBox(width: 8),
          _groupingControl(context, series, axis),
        ],
      ),
    );
  }

  /// Day / Week / Month, showing the grouping **in effect**.
  ///
  /// A grouping that cannot draw this range — a single month by month is one
  /// slot; a year by day is 365 hairlines — is disabled, and the plot uses the
  /// nearest that can.
  Widget _groupingControl(
    BuildContext context,
    DashboardChartSeries? series,
    ChartAxis axis,
  ) {
    final start = series?.startDate;
    final end = series?.endDate;
    final known = start != null && end != null && !axis.isEmpty;
    final effective = known ? axis.grouping : vm.chartGrouping;
    bool fits(ChartGrouping g) =>
        !known ||
        g == effective ||
        chartGroupingFits(
          start,
          end,
          g,
          firstDayOfWeek: formatter.settings.firstDayOfWeek,
        );
    ButtonSegment<ChartGrouping> seg(ChartGrouping g, String key) =>
        ButtonSegment<ChartGrouping>(
          value: g,
          enabled: fits(g),
          label: Text(context.tr(key), style: const TextStyle(fontSize: 12)),
        );
    return SegmentedButton<ChartGrouping>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      segments: [
        seg(ChartGrouping.day, 'day'),
        seg(ChartGrouping.week, 'week'),
        seg(ChartGrouping.month, 'month'),
      ],
      selected: {effective},
      onSelectionChanged: (s) => vm.setChartGrouping(s.first),
    );
  }

  /// One chip per series the company can chart, colour square and name — no
  /// total: the figures above already state each sum.
  ///
  /// **The last series shown cannot be switched off.** The view model refuses
  /// an empty selection, but a selection can be non-empty and still draw
  /// nothing here — expenses alone with the module off — so the card guards
  /// what it draws as well.
  Widget _legend(
    BuildContext context,
    InTheme tokens,
    List<ChartSeriesId> shown,
  ) => Wrap(
    spacing: InSpacing.sm,
    runSpacing: InSpacing.sm,
    children: [
      for (final id in _available)
        ChartLegendToggle(
          chip: true,
          label: _labelFor(context, id),
          color: _colorFor(tokens, id),
          active: shown.contains(id),
          onTap: () {
            if (shown.length == 1 && shown.first == id) return;
            vm.toggleChartSeries(id);
          },
        ),
    ],
  );

  Widget _loadingSkeleton(InTheme tokens) => Container(
    decoration: BoxDecoration(
      // The border tone, not the alternate surface: against a card that one
      // is 1.04–1.22:1, a placeholder nobody could see.
      color: tokens.border.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(InRadii.r1),
    ),
  );

  Widget _disabledOverlay(InTheme tokens, String message) => Container(
    decoration: BoxDecoration(
      color: tokens.surfaceAlt,
      borderRadius: BorderRadius.circular(InRadii.r1),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(InSpacing.sm),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: tokens.ink2, fontSize: 12),
    ),
  );

  /// The fetch failed and nothing is cached: say so, and offer the retry.
  Widget _failed(BuildContext context, InTheme tokens) => Container(
    decoration: BoxDecoration(
      color: tokens.surfaceAlt,
      borderRadius: BorderRadius.circular(InRadii.r1),
    ),
    alignment: Alignment.center,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 18, color: tokens.overdue),
        const SizedBox(width: InSpacing.sm),
        Text(
          context.tr('could_not_load_label'),
          style: TextStyle(color: tokens.ink2, fontSize: 13),
        ),
        const SizedBox(width: InSpacing.sm),
        TextButton(
          onPressed: () => vm.retry(DashboardKind.chart),
          child: Text(context.tr('retry')),
        ),
      ],
    ),
  );

  Widget _chart(
    BuildContext context,
    InTheme tokens,
    ChartAxis axis,
    String? currencyKey,
    List<ChartSeriesId> shown, {
    required bool hasPoints,
  }) {
    if (shown.isEmpty) {
      return _disabledOverlay(tokens, context.tr('no_series_selected'));
    }
    if (axis.isEmpty || !hasPoints) {
      return _disabledOverlay(tokens, context.tr('no_data_for_period'));
    }
    return _CashFlowBarChart(
      series: [
        for (final id in shown)
          _BarSeries(
            label: _labelFor(context, id),
            color: _colorFor(tokens, id),
            values: axis.values[id] ?? const [],
          ),
      ],
      buckets: axis.buckets,
      grouping: axis.grouping,
      tokens: tokens,
      formatter: formatter,
      currencyKey: currencyKey,
    );
  }

  /// Localized series label, paired with [_colorFor] by the legend, the bars
  /// and the tooltip.
  String _labelFor(BuildContext context, ChartSeriesId id) => switch (id) {
    ChartSeriesId.invoices => context.tr('invoiced'),
    ChartSeriesId.payments => context.tr('payments'),
    ChartSeriesId.expenses => context.tr('expenses'),
  };

  /// Three tones that mean the same thing wherever the app uses them, and none
  /// that the user picks: the accent is their own choice, so a green or red
  /// one would have collided with Payments or read as "overdue". Invoiced is
  /// the blue of the status pills' `partial` pair, payments the green of
  /// `paid`, expenses a neutral grey.
  Color _colorFor(InTheme tokens, ChartSeriesId id) => switch (id) {
    ChartSeriesId.invoices => tokens.partial,
    ChartSeriesId.payments => tokens.paid,
    ChartSeriesId.expenses => tokens.ink3,
  };

  DashboardCurrencyChart? _selectCurrency(
    DashboardChartSeries? series,
    String? key,
  ) {
    if (series == null || series.isEmpty) return null;
    if (key != null) return series.byCurrency[key];
    // "All" → server-converted base-currency bucket (id 999); single-currency
    // companies may omit it, so fall back to the sole currency.
    return series.byCurrency[kDashboardCurrencyAll.toString()] ??
        series.byCurrency.values.first;
  }
}

/// The gridlines' dash: three on, three off.
const List<int> _kDash = [3, 3];

/// One drawn series: its name, its colour and a value per slot.
@immutable
class _BarSeries {
  const _BarSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<double> values;
}

/// The plot. A [StatefulWidget] for two reasons.
///
/// **Its fl_chart callbacks are [State] methods**, so they are the same
/// objects from one build to the next. fl_chart includes every callback in
/// `BarChartData`'s equality, and `BarChart` is implicitly animated — it
/// restarts its tween whenever the new data is not equal to the old. Written
/// as closures in `build` they would re-run the 250 ms tween on every rebuild
/// of the card with nothing different on screen (`docs/dashboard-panels.md`
/// § A chart's callbacks are State tear-offs).
///
/// **It owns which slot's tooltip is showing** ([_touched]), because the
/// built-in touch handling shows one bar's value and hides it on a touch
/// screen the moment the finger lifts. The tooltip here is the whole slot —
/// its dates and every visible series — opened by a hover with a mouse and by
/// a tap on touch, where a second tap on the same slot closes it.
class _CashFlowBarChart extends StatefulWidget {
  const _CashFlowBarChart({
    required this.series,
    required this.buckets,
    required this.grouping,
    required this.tokens,
    required this.formatter,
    required this.currencyKey,
  });

  final List<_BarSeries> series;
  final List<ChartPeriod> buckets;

  /// The grouping [buckets] were built at — picks the axis ticks' form.
  final ChartGrouping grouping;
  final InTheme tokens;
  final Formatter formatter;
  final String? currencyKey;

  @override
  State<_CashFlowBarChart> createState() => _CashFlowBarChartState();
}

class _CashFlowBarChartState extends State<_CashFlowBarChart> {
  /// How many date labels the axis has room for — set in [build] from the
  /// plot's width, read by [_dateTitle]. A field rather than a closure
  /// argument so the callback stays a tear-off.
  int _maxLabels = 6;

  /// The value axis step, set in [build], read by [_valueTitle] and
  /// [_gridLine].
  double _step = 1;

  /// The slot whose tooltip is open, or null.
  int? _touched;

  /// [_touched] as it was when the current tap went down — a tap on the slot
  /// that was already open closes it.
  int? _touchedAtDown;

  /// The last rebuild was a tooltip opening or closing, not new data: skip the
  /// tween, so the tooltip follows the pointer instead of trailing it.
  bool _touchOnly = false;

  @override
  void didUpdateWidget(_CashFlowBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _touchOnly = false;
    // A new grouping or window moves every slot: the open one is gone.
    if (!listEquals(oldWidget.buckets, widget.buckets)) _touched = null;
  }

  void _setTouched(int? next) {
    if (next == _touched) return;
    setState(() {
      _touched = next;
      _touchOnly = true;
    });
  }

  void _onTouch(FlTouchEvent event, BarTouchResponse? response) {
    final slot = response?.spot?.touchedBarGroupIndex;
    switch (event) {
      case FlPointerHoverEvent():
        _setTouched(slot);
      case FlPointerExitEvent():
        _setTouched(null);
      case FlTapDownEvent():
        _touchedAtDown = _touched;
      case FlTapUpEvent(:final details):
        // A mouse already opened it by hovering; a click must not close it.
        if (details.kind == PointerDeviceKind.mouse) return;
        _setTouched(slot == null || slot == _touchedAtDown ? null : slot);
      case FlPanUpdateEvent() || FlLongPressMoveUpdate() || FlLongPressStart():
        if (slot != null) _setTouched(slot);
      default:
        break;
    }
  }

  /// The slot's dates, said in full: a day, or the first and last day of a
  /// week or month (clipped to the window at either end).
  String _periodLabel(ChartPeriod p) {
    final f = widget.formatter;
    if (p.isSingleDay) return f.date(p.start.toIso());
    return '${f.date(p.start.toIso())} – ${f.date(p.end.toIso())}';
  }

  /// A slot's axis tick: short, with the month as a word in the company's
  /// locale — `Nov 12` / `12 Nov` for a day, the week's first day for a week
  /// (the tooltip names its last), `Nov` for a month, `Nov 2026` when the
  /// axis crosses a year. The company's full format (`11/12/2026`) does not
  /// fit under a bar, and a bare `11/12` reads as the 11th of December to
  /// half the world. The tooltip carries the full format.
  String _tickLabel(ChartPeriod p) {
    final f = widget.formatter;
    final iso = p.start.toIso();
    if (widget.grouping != ChartGrouping.month) return f.dateShort(iso);
    final buckets = widget.buckets;
    final crossesYear =
        buckets.isNotEmpty && buckets.first.start.year != buckets.last.end.year;
    return f.dateMonth(iso, withYear: crossesYear);
  }

  /// Room one tick needs at the user's text size: **one and a half times the
  /// widest** (month words differ in width). A label is centred on its slot,
  /// except the first and last, which are pushed inside the plot
  /// (`fitInside`) — so each sits half a width closer to its neighbour.
  double _labelWidth(BuildContext context) {
    final buckets = widget.buckets;
    if (buckets.isEmpty) return 80;
    var widest = 0.0;
    for (final b in buckets) {
      final painter = TextPainter(
        text: TextSpan(
          text: _tickLabel(b),
          style: chartAxisStyle(widget.tokens),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest * 1.5;
  }

  /// A gridline between the floor and the top: dashed, a scale to read the
  /// bars against. (fl_chart draws neither bound here — the baseline is the
  /// solid bottom border and the top the dashed extra line, see [_plot].)
  FlLine _gridLine(double _) =>
      FlLine(color: widget.tokens.border, strokeWidth: 1, dashArray: _kDash);

  Widget _valueTitle(double value, TitleMeta meta) {
    // Only the round steps — fl_chart also offers the axis bounds.
    final ratio = value / _step;
    if ((ratio - ratio.round()).abs() > 0.001) return const SizedBox.shrink();
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: LtrText(
        widget.formatter.money(
          Decimal.parse(value.toStringAsFixed(0)),
          currencyId: widget.currencyKey,
          compact: true,
        ),
        style: moneyTextStyle(fontSize: 10, color: widget.tokens.ink3),
      ),
    );
  }

  Widget _dateTitle(double value, TitleMeta meta) {
    final buckets = widget.buckets;
    final idx = value.round();
    if (idx < 0 ||
        idx >= buckets.length ||
        idx % chartLabelStep(buckets.length, maxLabels: _maxLabels) != 0) {
      return const SizedBox.shrink();
    }
    // `fitInside` clamps the first and last label inside the axis box, so the
    // opening date is not clipped and the closing one does not slide under
    // the value axis. `space: 4`: the axis reserves 18 px, and the default 8
    // plus a 10 px label's line box cut the dates' descenders off.
    return SideTitleWidget(
      meta: meta,
      space: 4,
      fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
      child: LtrText(
        _tickLabel(buckets[idx]),
        style: chartAxisStyle(widget.tokens),
      ),
    );
  }

  Color _tooltipColor(BarChartGroupData _) => widget.tokens.ink;

  /// The whole slot, whichever bar anchors it: its dates, then a row per
  /// visible series — a swatch in the series' colour, its name and its value.
  /// Values on `surface`, not the series colour: those reach only ~3.3:1
  /// against the `ink` fill, below the small-text contrast floor.
  BarTooltipItem? _tooltipItem(
    BarChartGroupData group,
    int groupIndex,
    BarChartRodData rod,
    int rodIndex,
  ) {
    final tokens = widget.tokens;
    final buckets = widget.buckets;
    if (groupIndex < 0 || groupIndex >= buckets.length) return null;
    final plain = TextStyle(color: tokens.surface, fontSize: 11.5);
    return BarTooltipItem(
      '',
      plain,
      textAlign: TextAlign.start,
      // fl_chart lays tooltip text out LTR unless told otherwise.
      textDirection: Directionality.of(context),
      children: [
        TextSpan(
          text: _periodLabel(buckets[groupIndex]),
          style: plain.copyWith(fontWeight: FontWeight.w600),
        ),
        for (final s in widget.series) ...[
          const TextSpan(text: '\n'),
          TextSpan(
            text: '■ ',
            style: plain.copyWith(color: s.color),
          ),
          TextSpan(text: '${s.label}  ', style: plain),
          TextSpan(
            text: widget.formatter.money(
              Decimal.parse(
                (groupIndex < s.values.length ? s.values[groupIndex] : 0)
                    .toStringAsFixed(2),
              ),
              currencyId: widget.currencyKey,
            ),
            style: moneyTextStyle(color: tokens.surface, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Measured, because the room for bars and dates is the plot's width. The
    // plot's host never asks this subtree for an intrinsic size (it sits under
    // an `AspectRatio` or a positioned `Stack` child), which is what makes a
    // `LayoutBuilder` legal here — fl_chart's own plot is one too.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - chartValueAxisWidth(context);
        _maxLabels = room.isFinite
            ? (room / _labelWidth(context)).floor().clamp(2, 12)
            : 6;
        return _plot(context, room.isFinite ? room : 600);
      },
    );
  }

  Widget _plot(BuildContext context, double room) {
    final tokens = widget.tokens;
    final buckets = widget.buckets;
    final series = widget.series;
    final n = math.max(1, buckets.length);
    final k = math.max(1, series.length);

    var rawMax = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > rawMax) rawMax = v;
      }
    }
    final scale = chartValueScale(rawMax);
    _step = scale.step;

    // Bar widths scale with the slot: a group takes about 60% of its slot,
    // split between its bars, so a month by day and a quarter by week both
    // read as bars. Between 2 px (a hairline still shows a value) and 16.
    final slot = room / n;
    final barsSpace = slot < 24 ? 1.0 : 3.0;
    final rodWidth = ((slot * 0.6 - barsSpace * (k - 1)) / k).clamp(2.0, 16.0);
    final groupWidth = rodWidth * k + barsSpace * (k - 1);
    // The whole slot is the hover / tap target, not just the bars: each bar's
    // hit box reaches out to the slot's edges, and a transparent back-draw
    // makes it the full height of the plot.
    final reach = math.max(0.0, (slot - groupWidth) / 2) + barsSpace;
    final radius = BorderRadius.vertical(
      top: Radius.circular(math.min(3, rodWidth / 2)),
    );

    final touched = _touched;
    final groups = <BarChartGroupData>[
      for (var i = 0; i < buckets.length; i++)
        BarChartGroupData(
          x: i,
          barsSpace: barsSpace,
          // The tooltip hangs off the slot's tallest bar, so it never covers
          // one of them.
          showingTooltipIndicators: i == touched
              ? [_tallestRod(series, i)]
              : const [],
          barRods: [
            for (final s in series)
              BarChartRodData(
                toY: i < s.values.length ? s.values[i] : 0,
                color: s.color,
                width: rodWidth,
                borderRadius: radius,
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: scale.max,
                  color: Colors.transparent,
                ),
              ),
          ],
        ),
    ];

    return BarChart(
      BarChartData(
        barGroups: groups,
        // Every slot the same width, an empty one included: the spacing of
        // the bars is the spacing of time.
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: scale.max,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: scale.step,
          getDrawingHorizontalLine: _gridLine,
        ),
        // The baseline, solid: the bars stand on a floor. It also carries
        // the grid's token into the compared data — the grid colour comes
        // from a callback fl_chart cannot see inside, so without it a palette
        // change that left every bar's colour alone would compare equal and
        // never repaint the grid.
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        // The top gridline, at the labelled round amount above the tallest
        // bar. fl_chart's grid stops short of both bounds.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: scale.max,
              color: tokens.border,
              strokeWidth: 1,
              dashArray: _kDash,
            ),
          ],
        ),
        // rtl: physical — a time axis runs left to right in every locale (as
        // the Reports and Projects charts do), so the amounts stay on the
        // right, at the end the latest bar is drawn.
        titlesData: FlTitlesData(
          show: true,
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: chartValueAxisWidth(context),
              interval: scale.step,
              getTitlesWidget: _valueTitle,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: chartCategoryAxisHeight(context),
              getTitlesWidget: _dateTitle,
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          handleBuiltInTouches: false,
          allowTouchBarBackDraw: true,
          touchExtraThreshold: EdgeInsets.symmetric(horizontal: reach),
          touchCallback: _onTouch,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: _tooltipColor,
            getTooltipItem: _tooltipItem,
            tooltipBorderRadius: BorderRadius.circular(InRadii.r2),
            // The default 120 wraps a named amount, and the painter applies
            // the user's text scaler on top.
            maxContentWidth: 240,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
          ),
        ),
      ),
      duration: _touchOnly || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
  }

  static int _tallestRod(List<_BarSeries> series, int slot) {
    var best = 0;
    var bestValue = double.negativeInfinity;
    for (var j = 0; j < series.length; j++) {
      final values = series[j].values;
      final v = slot < values.length ? values[slot] : 0.0;
      if (v > bestValue) {
        bestValue = v;
        best = j;
      }
    }
    return best;
  }
}
