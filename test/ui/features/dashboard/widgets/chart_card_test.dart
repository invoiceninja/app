import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_chart_series.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/data/repositories/statics_repository.dart';
import 'package:admin/data/services/statics_service.dart';
import 'package:admin/ui/core/charts/chart_chrome.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/chart_card.dart';
import 'package:admin/ui/features/dashboard/widgets/delta_chip.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/ui/features/dashboard/helpers/totals_math.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';

import '../../../../_localization_helper.dart';

import '../_fake_dashboard_repo.dart';

/// The Cash flow chart: grouped bars for Invoiced, Payments and Expenses, a
/// legend that toggles them, and a tooltip that names a slot's every value.
void main() {
  late AppDatabase db;
  late FakeDashboardRepo repo;
  late DashboardViewModel vm;

  /// Bumped to rebuild the card alone, the way the dashboard's own
  /// `ListenableBuilder` does. Re-pumping the whole `MaterialApp` would not
  /// do: a new `ThemeData` starts `AnimatedTheme`'s tween, which is an
  /// animation too.
  late ValueNotifier<int> rebuild;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = FakeDashboardRepo(db);
    rebuild = ValueNotifier(0);
    vm = DashboardViewModel(
      repo: repo,
      companyId: 'co',
      navStateDao: db.navStateDao,
      statics: StaticsRepository(
        db: db,
        service: StaticsService(dummyDashboardClient),
      ),
      // Toggling a series or the grouping schedules a debounced nav_state
      // write; the default 500 ms outlives the pump and trips "a Timer is
      // still pending".
      persistDebounce: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  tearDown(() async {
    vm.dispose();
    rebuild.dispose();
    await db.close();
  });

  /// Three daily buckets on the "all currencies" key (999), one non-zero
  /// point per series so every curve has a distinct height.
  Map<String, dynamic> seriesJson() => {
    'start_date': '2026-04-01',
    'end_date': '2026-04-03',
    '999': {
      'invoices': [
        {'date': '2026-04-01', 'total': '400', 'currency': '1'},
        {'date': '2026-04-02', 'total': '410', 'currency': '1'},
      ],
      'payments': [
        {'date': '2026-04-01', 'total': '300', 'currency': '1'},
        {'date': '2026-04-02', 'total': '310', 'currency': '1'},
      ],
      'outstanding': [
        {'date': '2026-04-01', 'total': '200', 'currency': '1'},
        {'date': '2026-04-02', 'total': '210', 'currency': '1'},
      ],
      'expenses': [
        {'date': '2026-04-01', 'total': '100', 'currency': '1'},
        {'date': '2026-04-02', 'total': '110', 'currency': '1'},
      ],
    },
  };

  /// The card under a builder that hands it a new `ChartCard` and a new
  /// `Formatter` on every [rebuild] tick — what a parent rebuild looks like.
  Widget host() => MaterialApp(
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: kTestSupportedLocales,
    theme: buildInTheme(InTheme.light),
    home: Scaffold(
      body: SizedBox(
        width: 800,
        child: ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (context, _, _) => ChartCard(
            vm: vm,
            formatter: Formatter(
              settings: CompanyFormatSettings.fallback,
              // `money()` returns '' for an unresolvable currency, so the
              // company currency has to be present for the tooltip to hold
              // anything worth asserting on.
              currencies: {
                '1': Currency(
                  id: '1',
                  name: 'USD',
                  code: 'USD',
                  symbol: r'$',
                  precision: 2,
                  thousandSeparator: ',',
                  decimalSeparator: '.',
                  swapCurrencySymbol: false,
                  exchangeRate: Decimal.one,
                ),
              },
              countries: const {},
              dateFormats: const {},
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    repo.chart.add(DashboardChartSeries.fromJson(seriesJson()));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));
  }

  LineChartData chartData(WidgetTester tester) =>
      tester.widget<LineChart>(find.byType(LineChart)).data;

  /// Each slot's point values, series by series.
  List<List<double>> rods(WidgetTester tester) {
    final lines = chartData(tester).lineBarsData;
    if (lines.isEmpty) return const [];
    return [
      for (var i = 0; i < lines.first.spots.length; i++)
        [for (final l in lines) l.spots[i].y],
    ];
  }

  /// What the tooltip says for [slot]: fl_chart's `getTooltipItems` asked
  /// with the slot's spot on every line, as the chart asks when it opens.
  List<LineTooltipItem?> slotTooltip(LineChartData data, int slot) =>
      data.lineTouchData.touchTooltipData.getTooltipItems([
        for (var j = 0; j < data.lineBarsData.length; j++)
          LineBarSpot(
            data.lineBarsData[j],
            j,
            data.lineBarsData[j].spots[slot],
          ),
      ]);

  testWidgets('draws a point per slot on each line — three series by default', (
    tester,
  ) async {
    await pump(tester);

    // Three days, three slots, each with Invoiced · Payments · Expenses in
    // enum order, so the legend colours and the bars line up. The Unpaid
    // series is gone: the server still sends it, the chart does not draw it.
    expect(rods(tester), [
      [400.0, 300.0, 100.0],
      [410.0, 310.0, 110.0],
      [0.0, 0.0, 0.0],
    ]);
    for (final label in ['Invoiced', 'Payments', 'Expenses']) {
      expect(find.text(label), findsOneWidget, reason: '$label legend chip');
    }
    expect(find.text('Unpaid'), findsNothing);
    expect(find.text('Invoices'), findsNothing);
  });

  testWidgets('an empty slot is a point on the baseline, with no dot', (
    tester,
  ) async {
    await pump(tester);

    final data = chartData(tester);
    for (final line in data.lineBarsData) {
      // One point per slot, at the slot's centre: half a slot past each end.
      expect(line.spots.map((s) => s.x), [0, 1, 2]);
      // Smooth, but the curve may not overshoot — no dip below the baseline
      // or hump of money on a day that had none.
      expect(line.isCurved, isTrue);
      expect(line.preventCurveOverShooting, isTrue);
      // The quiet day sits on the floor, unmarked; a day with a value is
      // dotted.
      expect(line.spots.last.y, 0);
      final dot = line.dotData.checkToShowDot;
      expect(dot(line.spots.last, line), isFalse);
      expect(dot(line.spots.first, line), isTrue);
    }
    expect(data.minX, -0.5);
    expect(data.maxX, 2.5);
    expect(data.minY, 0);
  });

  group('Net received', () {
    DashboardTotals totals({String paid = '1200', String spent = '300'}) =>
        DashboardTotals.fromJson({
          'currencies': {'1': 'USD'},
          '999': {
            'revenue': {'paid_to_date': paid, 'code': 'USD'},
            'expenses': {'amount': spent, 'code': 'USD'},
            'invoices': {'invoiced_amount': '5000', 'code': 'USD'},
          },
        });

    testWidgets('is payments less expenses, from the figures\' totals', (
      tester,
    ) async {
      repo.totals.add(totals());
      await pump(tester);
      expect(find.text('Net received'), findsOneWidget);
      expect(find.text(r'+$900.00'), findsOneWidget);
      // Above the legend.
      expect(
        tester.getTopLeft(find.text(r'+$900.00')).dy,
        lessThan(tester.getTopLeft(find.text('Invoiced')).dy),
      );
      final ink = tester.widget<Text>(find.text(r'+$900.00')).style?.color;
      expect(ink, InTheme.light.paid);
    });

    testWidgets('a loss reads red, with its minus', (tester) async {
      repo.totals.add(totals(paid: '100', spent: '250'));
      await pump(tester);
      expect(find.text(r'-$150.00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(r'-$150.00')).style?.color,
        InTheme.light.overdue,
      );
    });

    testWidgets('unknown is not zero: hidden until the totals load', (
      tester,
    ) async {
      await pump(tester);
      expect(vm.totals.valueState, ValueSectionState.loading);
      expect(find.text('Net received'), findsNothing);
    });
  });

  test('netReceived: without the expenses module it is the payments', () {
    final bucket = DashboardTotals.fromJson({
      'currencies': {'1': 'USD'},
      '1': {
        'revenue': {'paid_to_date': '50', 'code': 'USD'},
        'expenses': {'amount': '20', 'code': 'USD'},
      },
    }).byCurrency['1'];
    expect(netReceived(bucket, expensesOn: true), Decimal.fromInt(30));
    expect(netReceived(bucket, expensesOn: false), Decimal.fromInt(50));
    expect(netReceived(null, expensesOn: true), Decimal.zero);
  });

  testWidgets('is "Cash flow", with no headline figure and no totals', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Cash flow'), findsOneWidget);
    expect(find.byType(DeltaChip), findsNothing);
    // The legend names each series and nothing more — the figures above
    // already state the sums.
    for (final chip in tester.widgetList<ChartLegendToggle>(
      find.byType(ChartLegendToggle),
    )) {
      expect(chip.chip, isTrue);
      expect(chip.label, isNot(contains(RegExp(r'\d'))));
    }
    expect(
      find.descendant(
        of: find.byType(ChartLegendToggle),
        matching: find.textContaining(r'$'),
      ),
      findsNothing,
    );
  });

  testWidgets('a legend chip is a real toggle', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Expenses'));
    // The screen mounts the card under the view model's chart listenable;
    // this host rebuilds on its own tick.
    rebuild.value++;
    await tester.pump(const Duration(milliseconds: 400));

    expect(vm.visibleChartSeries, isNot(contains(ChartSeriesId.expenses)));
    expect(rods(tester).first, [400.0, 300.0]);
    // A screen reader hears a switch, not a bare label.
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Expenses')),
      isSemantics(label: 'Expenses', isToggled: false, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('the last series shown cannot be switched off', (tester) async {
    vm
      ..toggleChartSeries(ChartSeriesId.payments)
      ..toggleChartSeries(ChartSeriesId.expenses);
    await pump(tester);

    await tester.tap(find.text('Invoiced'));
    rebuild.value++;
    await tester.pump(const Duration(milliseconds: 400));

    expect(vm.visibleChartSeries, {ChartSeriesId.invoices});
    expect(rods(tester).first, [400.0]);
  });

  testWidgets('a legend chip is a 44 px target on touch', (tester) async {
    await pump(tester);

    // Tests run as Android: touch-primary.
    for (final label in ['Invoiced', 'Payments', 'Expenses']) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(ChartLegendToggle),
      );
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    }
  });

  group('expenses module', () {
    Widget hostWith({required bool expensesOn}) => MaterialApp(
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      theme: buildInTheme(InTheme.light),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: ChartCard(
            vm: vm,
            formatter: Formatter(
              settings: CompanyFormatSettings.fallback,
              currencies: const {},
              countries: const {},
              dateFormats: const {},
            ),
            expensesOn: expensesOn,
          ),
        ),
      ),
    );

    testWidgets('off, Expenses is neither drawn nor offered', (tester) async {
      repo.chart.add(DashboardChartSeries.fromJson(seriesJson()));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(hostWith(expensesOn: false));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Expenses'), findsNothing);
      expect(rods(tester).first, [400.0, 300.0]);
    });

    // A selection the view model accepts (non-empty) can still draw nothing
    // here: Expenses alone, then the module is switched off.
    testWidgets('a selection with nothing to draw says why', (tester) async {
      vm
        ..toggleChartSeries(ChartSeriesId.invoices)
        ..toggleChartSeries(ChartSeriesId.payments);
      repo.chart.add(DashboardChartSeries.fromJson(seriesJson()));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(hostWith(expensesOn: false));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LineChart), findsNothing);
      expect(find.text('No series selected.'), findsOneWidget);
    });
  });

  // The series colours mean the same thing wherever the app uses them, and
  // none is the user's own accent — a green or red accent collided with
  // Payments or read as "overdue".
  testWidgets('series use fixed tones, never the accent or the overdue red', (
    tester,
  ) async {
    await pump(tester);

    final colors = [for (final l in chartData(tester).lineBarsData) l.color];
    const t = InTheme.light;
    expect(colors, [t.partial, t.paid, t.ink3]);
    expect(colors, isNot(contains(t.accent)));
    expect(colors, isNot(contains(t.overdue)));
  });

  testWidgets('gridlines are dashed, except the baseline', (tester) async {
    await pump(tester);

    final data = chartData(tester);
    final grid = data.gridData;
    final step = grid.horizontalInterval!;
    expect(grid.drawVerticalLine, isFalse);
    expect(grid.getDrawingHorizontalLine(step).dashArray, isNotNull);
    // The floor is the solid bottom border; the top is a dashed extra line.
    expect(data.borderData.show, isTrue);
    expect(data.borderData.border.bottom.width, greaterThan(0));
    expect(data.borderData.border.top.width, 0);
    final top = data.extraLinesData.horizontalLines.single;
    expect(top.y, data.maxY);
    expect(top.dashArray, isNotNull);
    // The top gridline is a round amount above the highest point (410).
    expect(chartData(tester).maxY, greaterThanOrEqualTo(410));
    expect(chartData(tester).maxY % step, 0);
    // Amounts on the right, physically, in every locale; none on the left.
    expect(
      chartData(tester).titlesData.rightTitles.sideTitles.showTitles,
      isTrue,
    );
    expect(
      chartData(tester).titlesData.leftTitles.sideTitles.showTitles,
      isFalse,
    );
  });

  group('states', () {
    testWidgets(
      'before the series answers it is a placeholder, not "no data"',
      (tester) async {
        await tester.pumpWidget(host());
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.byType(LineChart), findsNothing);
        expect(find.text('No data for this period.'), findsNothing);
      },
    );

    testWidgets('a failed fetch with nothing cached offers a retry', (
      tester,
    ) async {
      repo.refreshAllErrors = {DashboardKind.chart: Exception('x')};
      await vm.refresh();
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.text('No data for this period.'), findsNothing);
    });
  });

  testWidgets('a series that loaded with nothing in it says so', (
    tester,
  ) async {
    repo.chart.add(
      DashboardChartSeries.fromJson({
        'start_date': '2026-04-01',
        'end_date': '2026-04-30',
      }),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 10));

    // The positive control for the two `findsNothing` above: this is the
    // string, and only a loaded, empty series earns it.
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('No data for this period.'), findsOneWidget);
  });

  // A phone drawing one month by week had six full dates in ~250 px, printed
  // over one another. The axis labels as many as fit, in the company's own
  // date format, and never fewer than two.
  group('date labels', () {
    Future<List<Rect>> labelsAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      vm.setChartGrouping(ChartGrouping.day);
      repo.chart.add(
        DashboardChartSeries.fromJson({
          ...seriesJson(),
          'start_date': '2026-04-01',
          'end_date': '2026-04-30',
        }),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          theme: buildInTheme(InTheme.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartCard(
                vm: vm,
                formatter: Formatter(
                  settings: CompanyFormatSettings.fallback,
                  currencies: const {},
                  countries: const {},
                  dateFormats: const {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(chartData(tester).lineBarsData.first.spots.length, 30);
      return [
        for (final e
            in find
                .descendant(
                  of: find.byType(LineChart),
                  matching: find.textContaining(RegExp(r'^Apr \d+$')),
                )
                .evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
    }

    void expectApart(List<Rect> rects) {
      rects.sort((a, b) => a.left.compareTo(b.left));
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].left,
          greaterThanOrEqualTo(rects[i - 1].right),
          reason: 'labels $i-1 and $i overlap',
        );
      }
    }

    testWidgets('a wide plot labels more slots than a phone', (tester) async {
      final wide = await labelsAt(tester, 1000);
      expectApart(wide);
      expect(wide.length, greaterThan(5));
    });

    testWidgets('a phone-width plot skips labels rather than overlap them', (
      tester,
    ) async {
      final phone = await labelsAt(tester, 390);
      expectApart(phone);
      expect(phone.length, inInclusiveRange(2, 5));
    });
  });

  group('grouping', () {
    Set<ChartGrouping> selected(WidgetTester tester) => tester
        .widget<SegmentedButton<ChartGrouping>>(
          find.byType(SegmentedButton<ChartGrouping>),
        )
        .selected;
    Map<ChartGrouping, bool> enabled(WidgetTester tester) => {
      for (final s
          in tester
              .widget<SegmentedButton<ChartGrouping>>(
                find.byType(SegmentedButton<ChartGrouping>),
              )
              .segments)
        s.value: s.enabled,
    };

    // The default range under the default grouping: one month by month is two
    // boundaries, which plots as a single straight line.
    testWidgets('a range too short for its grouping is drawn finer, and the '
        'control says so', (tester) async {
      vm.setChartGrouping(ChartGrouping.month);
      repo.chart.add(
        DashboardChartSeries.fromJson({
          ...seriesJson(),
          'start_date': '2026-04-01',
          'end_date': '2026-04-30',
        }),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 400));

      expect(chartData(tester).lineBarsData.first.spots.length, greaterThan(3));
      expect(selected(tester), {ChartGrouping.week});
      expect(enabled(tester)[ChartGrouping.month], isFalse);
      expect(enabled(tester)[ChartGrouping.day], isTrue);
    });

    testWidgets('a grouping the range supports is drawn as asked', (
      tester,
    ) async {
      vm.setChartGrouping(ChartGrouping.month);
      repo.chart.add(
        DashboardChartSeries.fromJson({
          ...seriesJson(),
          'start_date': '2026-01-01',
          'end_date': '2026-12-31',
        }),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 400));

      expect(selected(tester), {ChartGrouping.month});
      // A year by week is 53 slots and by day 365 — past the bar chart's cap.
      expect(enabled(tester), {
        ChartGrouping.day: false,
        ChartGrouping.week: false,
        ChartGrouping.month: true,
      });
    });
  });

  // Beside the activity feed the two cards must end on one line with their
  // contents, not just their borders: the plot takes the height the row
  // settles on.
  //
  // Pumped inside the very arrangement the screen uses — `IntrinsicHeight`
  // around a stretched `Row` — because that is where it broke: fl_chart's plot
  // is a `LayoutBuilder`, which throws when asked for an intrinsic size, and
  // the row then painted nothing at all. A test that handed the card a tight
  // box passed while the dashboard showed a blank band.
  testWidgets('fillHeight: beside a taller card, the plot stretches to it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo.chart.add(DashboardChartSeries.fromJson(seriesJson()));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 17,
                    child: ChartCard(
                      vm: vm,
                      formatter: Formatter(
                        settings: CompanyFormatSettings.fallback,
                        currencies: const {},
                        countries: const {},
                        dateFormats: const {},
                      ),
                      fillHeight: true,
                    ),
                  ),
                  const Expanded(
                    flex: 10,
                    child: SizedBox(key: ValueKey('neighbour'), height: 520),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ChartCard)).height, 520);
    // A 2.4 aspect ratio at this width would be under 320; filling, the plot
    // takes what the card has left.
    expect(tester.getSize(find.byType(LineChart)).height, greaterThan(360));
  });

  testWidgets('fillHeight: beside a shorter card, the plot keeps its floor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo.chart.add(DashboardChartSeries.fromJson(seriesJson()));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 17,
                    child: ChartCard(
                      vm: vm,
                      formatter: Formatter(
                        settings: CompanyFormatSettings.fallback,
                        currencies: const {},
                        countries: const {},
                        dateFormats: const {},
                      ),
                      fillHeight: true,
                    ),
                  ),
                  const Expanded(flex: 10, child: SizedBox(height: 60)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(LineChart)).height,
      greaterThanOrEqualTo(kChartMinPlotHeight),
    );
  });

  // Asserts the getTooltipItem *contract*, not the painted tooltip: fl_chart
  // paints it on its canvas, where a finder cannot read it.
  testWidgets('a slot\'s tooltip names its date and every series', (
    tester,
  ) async {
    await pump(tester);

    final data = chartData(tester);
    final items = slotTooltip(data, 0);
    // One entry per shown spot (fl_chart's contract); the first carries the
    // whole slot and the rest are skipped.
    expect(items, hasLength(data.lineBarsData.length));
    expect(items.skip(1), everyElement(isNull));
    final item = items.first!;
    final text = item.children!.map((c) => c.toPlainText()).join();
    expect(text, startsWith('2026-04-01'));
    expect(text, contains(r'Invoiced  $400.00'));
    expect(text, contains(r'Payments  $300.00'));
    expect(text, contains(r'Expenses  $100.00'));
    // Each row's swatch carries its series' colour.
    final swatches = item.children!
        .where((c) => c.toPlainText() == '● ')
        .map((c) => c.style!.color)
        .toList();
    expect(swatches, [for (final l in data.lineBarsData) l.color]);
  });

  testWidgets('a week slot\'s tooltip spans its first and last day', (
    tester,
  ) async {
    vm.setChartGrouping(ChartGrouping.week);
    repo.chart.add(
      DashboardChartSeries.fromJson({
        ...seriesJson(),
        'start_date': '2026-04-01',
        'end_date': '2026-04-30',
      }),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));

    final item = slotTooltip(chartData(tester), 0).first!;
    // 2026-04-01 is a Wednesday; its week ends on Saturday the 4th.
    expect(item.children!.first.toPlainText(), '2026-04-01 – 2026-04-04');
  });

  // Dates go through the company's `Formatter`: the ticks short, with the
  // month as a word (a bare `11/12` reads as December to half the world), the
  // tooltip in the company's own full format.
  group('dates', () {
    Future<LineChartData> pumpWith(
      WidgetTester tester, {
      required String start,
      required String end,
      required ChartGrouping grouping,
    }) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      vm.setChartGrouping(grouping);
      repo.chart.add(
        DashboardChartSeries.fromJson({
          ...seriesJson(),
          'start_date': start,
          'end_date': end,
        }),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          theme: buildInTheme(InTheme.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChartCard(
                vm: vm,
                formatter: Formatter(
                  settings: CompanyFormatSettings.fallback,
                  currencies: const {},
                  countries: const {},
                  // The fallback settings' date format id.
                  dateFormats: {
                    CompanyFormatSettings.fallback.dateFormatId:
                        const DatetimeFormat(id: 'x', format: 'dd/MM/yyyy'),
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return chartData(tester);
    }

    Iterable<String> ticks(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(LineChart),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .where((t) => t.isNotEmpty && !t.contains(r'$'));

    String tooltipDate(LineChartData data, int slot) =>
        slotTooltip(data, slot).first!.children!.first.toPlainText();

    testWidgets('a day: "Apr 1" on the axis, the company format in the '
        'tooltip', (tester) async {
      final data = await pumpWith(
        tester,
        start: '2026-04-01',
        end: '2026-04-30',
        grouping: ChartGrouping.day,
      );
      expect(ticks(tester), contains('Apr 1'));
      expect(ticks(tester).where((t) => t.contains('2026')), isEmpty);
      expect(tooltipDate(data, 0), '01/04/2026');
    });

    testWidgets('a week: its first day on the axis, both ends in the '
        'tooltip', (tester) async {
      final data = await pumpWith(
        tester,
        start: '2026-04-01',
        end: '2026-04-30',
        grouping: ChartGrouping.week,
      );
      expect(ticks(tester), contains('Apr 5'));
      expect(tooltipDate(data, 1), '05/04/2026 – 11/04/2026');
    });

    testWidgets('a month: its name, with the year only across years', (
      tester,
    ) async {
      await pumpWith(
        tester,
        start: '2024-01-01',
        end: '2024-12-31',
        grouping: ChartGrouping.month,
      );
      expect(ticks(tester), containsAll(['Jan', 'Dec']));

      await pumpWith(
        tester,
        start: '2025-10-01',
        end: '2026-03-31',
        grouping: ChartGrouping.month,
      );
      expect(ticks(tester), containsAll(['Oct 2025', 'Mar 2026']));
    });
  });

  int? openSlot(WidgetTester tester) {
    final shown = chartData(tester).showingTooltipIndicators;
    if (shown.isEmpty) return null;
    final spots = shown.single.showingSpots;
    // The whole slot: one spot per series, all in the same column.
    expect(spots, hasLength(chartData(tester).lineBarsData.length));
    expect(spots.map((s) => s.spotIndex).toSet(), hasLength(1));
    return spots.first.spotIndex;
  }

  testWidgets('a mouse opens a slot\'s tooltip by hovering anywhere in it', (
    tester,
  ) async {
    await pump(tester);
    final box = tester.getRect(find.byType(LineChart));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    // High above the middle slot's points, in the slot's own column.
    await mouse.moveTo(Offset(box.left + (box.width - 44) / 2, box.top + 8));
    await tester.pump();
    expect(openSlot(tester), 1);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(openSlot(tester), isNull);
  });

  testWidgets(
    'a tap opens a slot\'s tooltip on touch, and a second closes it',
    (tester) async {
      await pump(tester);
      final box = tester.getRect(find.byType(LineChart));
      final middle = Offset(box.left + (box.width - 44) / 2, box.center.dy);

      await tester.tapAt(middle);
      await tester.pump();
      expect(openSlot(tester), 1, reason: 'stays open after the finger lifts');

      await tester.tapAt(middle);
      await tester.pump();
      expect(openSlot(tester), isNull);
    },
  );

  // `LineChart` is implicitly animated and restarts its tween whenever the new
  // `LineChartData` is not equal to the old — and that equality includes every
  // callback. The card rebuilds several times while the dashboard loads, so
  // callbacks minted in `build` meant a 250 ms tween per rebuild with nothing
  // different on screen.
  group('an unchanged rebuild', () {
    /// One rebuild, run to rest. fl_chart always animates the FIRST update
    /// after mount, whatever it is handed: its initial tween ends on the raw
    /// data, while every later target is that data with the axis bounds and
    /// the touch callback filled in, so the two never compare equal. Only
    /// from the second update on does equal data mean no tween — which is
    /// where these tests have to start.
    Future<void> firstUpdate(WidgetTester tester) async {
      rebuild.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.transientCallbackCount, 0, reason: 'settled');
    }

    testWidgets('does not restart the chart animation', (tester) async {
      await pump(tester);
      await firstUpdate(tester);
      final before = chartData(tester);

      rebuild.value++;
      await tester.pump();

      final after = chartData(tester);
      expect(after, isNot(same(before)), reason: 'the card did rebuild');
      expect(after, before, reason: 'and built equal chart data');
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'equal data starts no tween',
      );
    });

    // The control for the test above: the same sequence with one callback
    // built inline. If this ever stops animating, `transientCallbackCount == 0`
    // above proves nothing — fl_chart changed what it compares.
    testWidgets('re-animates when a callback is rebuilt inline (control)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 200,
            child: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, _, _) => LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(spots: const [FlSpot(0, 0), FlSpot(1, 1)]),
                  ],
                  gridData: FlGridData(
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(strokeWidth: 1),
                  ),
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await firstUpdate(tester);

      rebuild.value++;
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('still animates when the data really changed', (tester) async {
      await pump(tester);
      await firstUpdate(tester);

      vm.toggleChartSeries(ChartSeriesId.expenses);
      rebuild.value++;
      await tester.pump();

      expect(rods(tester).first, hasLength(2));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      // Past the tween and the view model's 500 ms persist debounce.
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
