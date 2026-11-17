import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_aging.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_list_rows.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/data/repositories/statics_repository.dart';
import 'package:admin/data/services/statics_service.dart';
import 'package:admin/ui/features/dashboard/helpers/needs_attention.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/aging_bar.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_figures.dart';
import 'package:admin/ui/features/dashboard/widgets/delta_chip.dart';
import 'package:admin/ui/features/dashboard/widgets/kpi_row.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../_localization_helper.dart';
import '../_fake_dashboard_repo.dart';

/// The dashboard's figures: Outstanding (everything unpaid today) beside
/// Invoices · Payments · Expenses for the selected period.
///
/// What these tests hold in place:
///
/// * **Unknown is not zero.** The row this replaced formatted `amount ?? zero`,
///   so a figure that had not loaded — or could not be — read `$0.00`, which is
///   an answer.
/// * **Labels never bake in the range** (flutter#37 — "Paid this month" under a
///   quarter's figure).
/// * **Outstanding is not a period figure**: it reads its own section, carries
///   no trend, and a new date range does not blank it.
void main() {
  late AppDatabase db;
  late FakeDashboardRepo repo;
  late DashboardViewModel vm;

  final formatter = Formatter(
    settings: CompanyFormatSettings.fallback,
    // `money()` returns '' for a currency it cannot resolve, so the company
    // currency has to exist for a figure to render anything.
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
  );

  DashboardTotals totalsOf({
    String invoiced = '0',
    String paid = '0',
    String expenses = '0',
    String outstanding = '0',
    int unpaid = 0,
  }) => DashboardTotals.fromJson({
    'currencies': {'1': 'USD'},
    '1': {
      'invoices': {'invoiced_amount': invoiced, 'code': 'USD'},
      'revenue': {'paid_to_date': paid, 'code': 'USD'},
      'expenses': {'amount': expenses, 'code': 'USD'},
      'outstanding': {
        'amount': outstanding,
        'outstanding_count': unpaid,
        'code': 'USD',
      },
    },
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = FakeDashboardRepo(db);
    vm = DashboardViewModel(
      repo: repo,
      companyId: 'co',
      navStateDao: db.navStateDao,
      statics: StaticsRepository(
        db: db,
        service: StaticsService(dummyDashboardClient),
      ),
      // A range change schedules a debounced nav_state write; the default
      // 500 ms outlives the pump and trips "a Timer is still pending".
      persistDebounce: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  /// The default 800 px test surface would clamp every width asked for below.
  void wideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  int outstandingTaps = 0;
  int invoicesTaps = 0;
  int paidTaps = 0;
  setUp(() {
    outstandingTaps = 0;
    invoicesTaps = 0;
    paidTaps = 0;
  });

  /// `theme: buildInTheme(...)` is mandatory — `context.inTheme` null-checks
  /// without it. The figures land on per-section notifiers, so the host
  /// listens to those like the screen does.
  Future<void> pumpRow(
    WidgetTester tester, {
    double width = 1400,
    bool showExpenses = true,
    NeedsAttention? attention,
  }) async {
    wideSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ListenableBuilder(
                listenable: Listenable.merge([vm, vm.kpiListenable]),
                builder: (context, _) => KpiRow(
                  vm: vm,
                  formatter: formatter,
                  showExpenses: showExpenses,
                  attention: attention,
                  onOutstandingTap: () => outstandingTaps++,
                  onInvoicesTap: () => invoicesTaps++,
                  onPaidTap: () => paidTaps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Explicit durations, never pumpAndSettle — the VM holds a live watch
    // subscription per section.
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> land(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 10));

  group('unknown is not zero', () {
    testWidgets('before anything loads, no figure shows an amount', (
      tester,
    ) async {
      await pumpRow(tester);

      expect(find.byType(FigureSkeletonBar), findsNWidgets(4));
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.byType(DeltaChip), findsNothing);
    });

    testWidgets('a failed fetch with nothing cached is a dash and a retry', (
      tester,
    ) async {
      repo.refreshAllErrors = {DashboardKind.totalsCurrent: Exception('x')};
      await vm.refresh();
      await pumpRow(tester);

      // The three period figures failed together, on one card: one retry.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
      // The other cells keep the retry's height, so the dashes share a line.
      final tops = {
        for (final e in find.text('—').evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      };
      expect(tops.length, 1, reason: '$tops');
    });

    testWidgets('a failed refresh over cached figures keeps them, marked', (
      tester,
    ) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      // `pump`, never `Future.delayed`: a real delay never elapses inside
      // `testWidgets`' fake clock.
      await tester.pump(const Duration(milliseconds: 10));
      repo.refreshAllErrors = {DashboardKind.totalsCurrent: Exception('x')};
      await vm.refresh();
      await pumpRow(tester);

      expect(find.text(r'$1,200.00'), findsOneWidget);
      // One mark for the shared card the three figures sit on.
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('a loaded zero is a zero', (tester) async {
      repo.totals.add(totalsOf());
      await pumpRow(tester);
      await land(tester);

      expect(find.text(r'$0.00'), findsNWidgets(3));
    });
  });

  group('the period figures', () {
    testWidgets('are Invoices, Payments and Expenses, whatever the range', (
      tester,
    ) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      await pumpRow(tester);
      await land(tester);

      for (final label in ['Invoiced', 'Payments', 'Expenses']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(r'$1,200.00'), findsOneWidget);
      expect(find.text(r'$900.00'), findsOneWidget);
      expect(find.text(r'$50.00'), findsOneWidget);

      await vm.setDateRange(
        const DashboardPresetRange(DashboardDatePreset.lastQuarter),
      );
      await land(tester);
      // The window is named once, in the row above the figures; a label that
      // baked it in could disagree with the number beneath it.
      expect(
        find.textContaining(RegExp('month|quarter', caseSensitive: false)),
        findsNothing,
      );
      for (final label in ['Invoiced', 'Payments', 'Expenses']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Expenses is left out with the module off', (tester) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      await pumpRow(tester, showExpenses: false);
      await land(tester);

      expect(find.text('Expenses'), findsNothing);
      expect(find.text(r'$50.00'), findsNothing);
    });

    testWidgets('a trend is drawn only with something to compare against', (
      tester,
    ) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      await pumpRow(tester);
      await land(tester);
      expect(find.byType(DeltaChip), findsNothing);

      repo.totalsPrev.add(
        totalsOf(invoiced: '600', paid: '900', expenses: '100'),
      );
      await land(tester);
      expect(find.byType(DeltaChip), findsNWidgets(3));
      expect(find.text('+100.0%'), findsOneWidget);
      expect(find.text('vs \$600.00'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    // Hillel's call (critique pass 2): a rise from zero has no percentage
    // worth inventing, and a neutral "—" chip read as a missing value. The
    // comparison alone says why there is no trend.
    testWidgets('a previous zero draws no chip — just "vs \$0.00"', (
      tester,
    ) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      repo.totalsPrev.add(totalsOf(invoiced: '0', paid: '900', expenses: '50'));
      await pumpRow(tester);
      await land(tester);

      final invoiced = find.ancestor(
        of: find.text('Invoiced'),
        matching: find.byType(PeriodSummaryCard),
      );
      expect(
        find.descendant(of: invoiced, matching: find.text('—')),
        findsNothing,
      );
      expect(
        find.descendant(of: invoiced, matching: find.textContaining('%')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: invoiced,
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: invoiced, matching: find.text('vs \$0.00')),
        findsOneWidget,
      );
      // The other two still compare against a non-zero figure: a chip each.
      expect(find.text('0.0%'), findsNWidgets(2));
    });

    testWidgets('"All time" has nothing to compare and draws no trend', (
      tester,
    ) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      await vm.setDateRange(
        const DashboardPresetRange(DashboardDatePreset.allTime),
      );
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      await pumpRow(tester);
      await land(tester);
      expect(find.byType(DeltaChip), findsNothing);
    });

    testWidgets('Invoices and Payments open their lists; Expenses does not', (
      tester,
    ) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      await pumpRow(tester);
      await land(tester);

      await tester.tap(find.text('Invoiced'));
      await tester.tap(find.text('Payments'));
      await tester.tap(find.text('Expenses'));
      await land(tester);

      expect(invoicesTaps, 1);
      expect(paidTaps, 1);
      // No ↗ either: the expenses list has no date filter to show.
      expect(
        find.descendant(
          of: find.byType(PeriodSummaryCard),
          matching: find.byIcon(Icons.arrow_outward),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('a figure that has not loaded is not a link', (tester) async {
      await pumpRow(tester);

      await tester.tap(find.text('Invoiced'));
      await land(tester);

      expect(invoicesTaps, 0);
    });
  });

  /// The band's buckets over [balances] late invoices, all due a fortnight
  /// ago. [total] makes the list a page of a longer one (an unproven sum).
  NeedsAttention lateOf(
    List<String> balances, {
    String currency = '',
    int? total,
  }) => needsAttention(
    pastDue: DashboardRows([
      for (var i = 0; i < balances.length; i++)
        DashboardInvoiceRow(
          id: 'i$i',
          number: '000$i',
          clientId: 'c',
          clientName: 'Client',
          dueDate: const Date(2026, 10, 1),
          balance: Decimal.parse(balances[i]),
          amount: Decimal.parse(balances[i]),
          statusId: 2,
          currencyId: currency,
        ),
    ], total: total ?? balances.length),
    upcomingInvoices: const [],
    upcomingQuotes: const [],
    today: const Date(2026, 10, 14),
    companyCurrencyId: '1',
  );

  DashboardAging agingOf({
    String current = '9000',
    String d30 = '2000',
    String d60 = '1000',
    String d90 = '400',
  }) => DashboardAging.fromJson({
    'currencies': {'1': 'USD'},
    '1': {
      'aging': {
        'total': '12400',
        'current_amount': current,
        'age_0_30': d30,
        'age_31_60': d60,
        'age_61_90': d90,
        'age_91_120': '0',
        'age_120_plus': '0',
        'outstanding_count': 9,
      },
    },
  });

  group('Outstanding', () {
    testWidgets('reads its own section, not the period totals', (tester) async {
      // The period's own "outstanding" is what invoices dated in the range
      // still owe; the card must not show it.
      repo.totals.add(totalsOf(outstanding: '300', unpaid: 1));
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      await pumpRow(tester, attention: lateOf(['100', '200', '300', '400']));
      await land(tester);

      final card = find.byType(OutstandingFigureCard);
      expect(
        find.descendant(of: card, matching: find.text(r'$12,400.00')),
        findsOneWidget,
      );
      expect(find.text(r'$300.00'), findsNothing);
      expect(
        find.descendant(of: card, matching: find.text('9 unpaid')),
        findsOneWidget,
      );
      // A balance, not a flow: nothing to compare it with.
      expect(
        find.descendant(of: card, matching: find.byType(DeltaChip)),
        findsNothing,
      );
    });

    testWidgets('past due is the band\'s proven sum when there is one', (
      tester,
    ) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      // The aging says otherwise (a deposit the server buckets as current);
      // the band's number wins, because the band prints it too.
      repo.aging.add(agingOf(d30: '50', d60: '0', d90: '0'));
      await pumpRow(tester, attention: lateOf(['100', '200', '300', '400']));
      await land(tester);

      expect(find.text(r'$1,000.00 past due'), findsOneWidget);
    });

    testWidgets('past due falls back to the aging when the band cannot sum', (
      tester,
    ) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
      // Four rows of eighty: the band has no proven sum.
      await pumpRow(
        tester,
        attention: lateOf(['100', '200', '300', '400'], total: 80),
      );
      await land(tester);

      // 1-30 + 31-60 + 60+ days = 2000 + 1000 + 400.
      expect(find.text(r'$3,400.00 past due'), findsOneWidget);
    });

    testWidgets('an empty band means nothing past due, whatever else says', (
      tester,
    ) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
      await pumpRow(tester, attention: lateOf(const []));
      await land(tester);

      expect(find.textContaining('past due'), findsNothing);
    });

    testWidgets('with neither an amount nor a bar, the band\'s count', (
      tester,
    ) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      await pumpRow(
        tester,
        attention: lateOf(['100', '200', '300', '400'], total: 80),
      );
      await land(tester);

      expect(find.text('80 past due'), findsOneWidget);
    });

    testWidgets('names no past-due count it does not have', (tester) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      await pumpRow(tester);
      await land(tester);

      expect(find.text('9 unpaid'), findsOneWidget);
      expect(find.textContaining('past due'), findsNothing);
    });

    testWidgets('survives a new date range', (tester) async {
      repo.totals.add(totalsOf(invoiced: '1200'));
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      await pumpRow(tester);
      await land(tester);

      await vm.setDateRange(
        const DashboardPresetRange(DashboardDatePreset.lastQuarter),
      );
      await land(tester);

      // The period figures start over; the balance as of today does not.
      expect(find.text(r'$12,400.00'), findsOneWidget);
      expect(find.text(r'$1,200.00'), findsNothing);
    });

    testWidgets('opens the unpaid list', (tester) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      await pumpRow(tester);
      await land(tester);

      await tester.tap(find.text('Outstanding'));
      await land(tester);

      expect(outstandingTaps, 1);
    });
  });

  group('the aging bar', () {
    testWidgets('draws one share per non-empty bucket, and says them all', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf(d60: '0'));
      await pumpRow(tester);
      await land(tester);

      final bar = find.byType(AgingBar);
      expect(bar, findsOneWidget);
      // Current, 0-30 and 60+; the empty 30-60 bucket draws nothing.
      expect(
        find.descendant(of: bar, matching: find.byType(ColoredBox)),
        findsNWidgets(3),
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Aging: Current \$9,000\.00, 0 - 30 Days \$2,000\.00, '
            r'30 - 60 Days \$0\.00, 60\+ Days \$400\.00',
          ),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('is never a zero bar: no aging, no bar', (tester) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      await pumpRow(tester);
      await land(tester);
      expect(find.byType(AgingBar), findsNothing);

      // A server without the endpoint answers "unsupported".
      repo.aging.add(DashboardAging.none);
      await land(tester);
      expect(find.byType(AgingBar), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a failed aging fetch hides the bar and offers no retry', (
      tester,
    ) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.refreshAllErrors = {DashboardKind.aging: Exception('x')};
      await vm.refresh();
      await pumpRow(tester);
      await land(tester);

      expect(find.byType(AgingBar), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.sync_problem), findsNothing);
      // Nor does it make the pass a failed one.
      expect(vm.globalError, isNull);
      expect(vm.lastRefreshed, isNotNull);
    });

    testWidgets('follows the selected currency', (tester) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      // Only a pound bucket: nothing in the figure's currency to draw.
      repo.aging.add(
        DashboardAging.fromJson({
          '2': {
            'aging': {'total': '50', 'current_amount': '50'},
          },
          '999': {
            'aging': {'total': '60', 'current_amount': '60'},
          },
        }),
      );
      await pumpRow(tester);
      await land(tester);
      // "All currencies" draws the converted aggregate.
      expect(find.byType(AgingBar), findsOneWidget);

      await vm.setCurrency(1);
      await land(tester);
      expect(find.byType(AgingBar), findsNothing);
    });

    testWidgets('on touch, a tap opens the breakdown', (tester) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
      await pumpRow(tester);
      await land(tester);

      await tester.tap(find.byKey(const ValueKey('aging-bar-tap')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AgingBreakdownSheet), findsOneWidget);
      // The tap went to the bar, not the card's link.
      expect(outstandingTaps, 0);
      expect(
        find.descendant(
          of: find.byType(AgingBreakdownSheet),
          matching: find.text(r'$2,000.00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with a pointer, it is a tooltip and a click is the link', (
      tester,
    ) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
      await pumpRow(tester);
      await land(tester);

      expect(find.byKey(const ValueKey('aging-bar-tap')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AgingBar),
          matching: find.byType(Tooltip),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(AgingBar));
      await land(tester);
      expect(outstandingTaps, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('mirrors in a right-to-left layout', (tester) async {
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
      wideSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          theme: buildInTheme(InTheme.light),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListenableBuilder(
                listenable: Listenable.merge([vm, vm.kpiListenable]),
                builder: (context, _) => KpiRow(vm: vm, formatter: formatter),
              ),
            ),
          ),
        ),
      );
      await land(tester);

      final boxes = find.descendant(
        of: find.byType(AgingBar),
        matching: find.byType(ColoredBox),
      );
      // Current is the first bucket, and sits at the start — the right.
      expect(
        tester.getCenter(boxes.first).dx,
        greaterThan(tester.getCenter(boxes.last).dx),
      );
    });
  });

  group('layout', () {
    double bottomOf(WidgetTester tester, Finder f) =>
        tester.getBottomLeft(f).dy;
    double topOf(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;
    final outstanding = find.byType(OutstandingFigureCard);
    final periods = find.byType(PeriodSummaryCard);

    Future<void> seed(WidgetTester tester) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      repo.totalsPrev.add(
        totalsOf(invoiced: '600', paid: '450', expenses: '9'),
      );
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
    }

    final group = find.byType(PeriodSummaryGroup);
    final dividers = find.descendant(
      of: group,
      matching: find.byType(VerticalDivider),
    );

    testWidgets('one row: Outstanding, then one card of three cells', (
      tester,
    ) async {
      await seed(tester);
      await pumpRow(tester, width: 1000);
      await land(tester);

      // Hillel, against 5.1.30: "keep invoices, payments and expenses grouped
      // together" — one surface, hairlines between the cells.
      expect(group, findsOneWidget);
      expect(periods, findsNWidgets(3));
      expect(dividers, findsNWidgets(2));
      final top = topOf(tester, outstanding);
      final bottom = bottomOf(tester, outstanding);
      expect(topOf(tester, group), top);
      expect(bottomOf(tester, group), bottom);
      for (var i = 0; i < 3; i++) {
        expect(bottomOf(tester, periods.at(i)), closeTo(bottom, 1));
      }
      // The three values on one line, and the cells as wide as Outstanding.
      final valueTops = {
        for (final v in [r'$1,200.00', r'$900.00', r'$50.00'])
          topOf(tester, find.text(v)),
      };
      expect(valueTops.length, 1, reason: '$valueTops');
      for (var i = 0; i < 3; i++) {
        expect(
          tester.getSize(periods.at(i)).width,
          closeTo(tester.getSize(outstanding).width, 2),
        );
      }
      // The aging bar makes Outstanding the tallest; the trends still end on
      // its footer's last line.
      expect(
        tester.getBottomLeft(find.textContaining('past due')).dy,
        closeTo(tester.getBottomLeft(find.text('vs \$600.00')).dy, 4),
      );
    });

    testWidgets('with Expenses off the two left stay grouped', (tester) async {
      await seed(tester);
      await pumpRow(tester, width: 1000, showExpenses: false);
      await land(tester);

      expect(group, findsOneWidget);
      expect(periods, findsNWidgets(2));
      expect(dividers, findsOneWidget);
      expect(topOf(tester, group), topOf(tester, outstanding));
      for (var i = 0; i < 2; i++) {
        expect(
          tester.getSize(periods.at(i)).width,
          closeTo(tester.getSize(outstanding).width, 2),
        );
      }
    });

    testWidgets('below the one-row width, the group takes a row of its own', (
      tester,
    ) async {
      await seed(tester);
      await pumpRow(tester, width: kFiguresOneRowWidth - 1);
      await land(tester);

      expect(topOf(tester, group), greaterThan(bottomOf(tester, outstanding)));
      // Still one card, its cells side by side.
      expect(dividers, findsNWidgets(2));
      for (var i = 1; i < 3; i++) {
        expect(topOf(tester, periods.at(i)), topOf(tester, periods.at(0)));
      }
    });

    testWidgets('two cells and Outstanding share a row from 660 px', (
      tester,
    ) async {
      await seed(tester);
      await pumpRow(tester, width: 660, showExpenses: false);
      await land(tester);
      expect(topOf(tester, group), topOf(tester, outstanding));

      await pumpRow(tester, width: 659, showExpenses: false);
      await land(tester);
      expect(topOf(tester, group), greaterThan(bottomOf(tester, outstanding)));
    });

    testWidgets('narrow, the cells stay side by side, as on a phone', (
      tester,
    ) async {
      await seed(tester);
      // The wide body's narrowest: a 600 px pane less its padding. A phone
      // draws the figures through `PeriodFiguresCard` instead.
      await pumpRow(tester, width: 560);
      await land(tester);

      expect(tester.takeException(), isNull);
      for (var i = 1; i < 3; i++) {
        expect(topOf(tester, periods.at(i)), topOf(tester, periods.at(0)));
      }
    });

    test('figuresShareRow', () {
      expect(figuresShareRow(880, 3), isTrue);
      expect(figuresShareRow(879, 3), isFalse);
      expect(figuresShareRow(660, 2), isTrue);
      expect(figuresShareRow(659, 2), isFalse);
      expect(figuresShareRow(440, 1), isTrue);
    });

    testWidgets('a large amount scales down; it is never cut off', (
      tester,
    ) async {
      repo.totals.add(
        totalsOf(
          invoiced: '123456789012.34',
          paid: '123456789012.34',
          expenses: '123456789012.34',
        ),
      );
      repo.outstanding.add(totalsOf(outstanding: '123456789012.34'));
      await pumpRow(tester, width: 900);
      await land(tester);

      expect(tester.takeException(), isNull);
      for (final text in tester.widgetList<Text>(
        find.text(r'$123,456,789,012.34'),
      )) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(text.softWrap, isFalse);
      }
      expect(find.text(r'$123,456,789,012.34'), findsNWidgets(4));
    });

    testWidgets('holds at 140% text', (tester) async {
      repo.totals.add(totalsOf(invoiced: '1200', paid: '900', expenses: '50'));
      repo.totalsPrev.add(
        totalsOf(invoiced: '600', paid: '450', expenses: '9'),
      );
      repo.outstanding.add(totalsOf(outstanding: '12400', unpaid: 9));
      repo.aging.add(agingOf());
      wideSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          theme: buildInTheme(InTheme.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 900,
                child: ListenableBuilder(
                  listenable: Listenable.merge([vm, vm.kpiListenable]),
                  builder: (context, _) => KpiRow(
                    vm: vm,
                    formatter: formatter,
                    attention: lateOf(['100', '200', '300', '400']),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await land(tester);

      expect(tester.takeException(), isNull);
      // A caption shrinks to fit, like the figure under it: "Invoi…" over a
      // number does not say what the number is.
      for (final label in ['Outstanding', 'Invoiced', 'Payments', 'Expenses']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.overflow, isNot(TextOverflow.ellipsis), reason: label);
        expect(
          find.ancestor(of: find.text(label), matching: find.byType(FittedBox)),
          findsWidgets,
          reason: label,
        );
      }
      // Nothing clipped: the caption under the figure is fully inside its card.
      final card = tester.getRect(find.byType(OutstandingFigureCard));
      for (final text in ['9 unpaid', r'$1,000.00 past due']) {
        final caption = tester.getRect(find.text(text));
        expect(caption.bottom, lessThan(card.bottom), reason: text);
      }
    });
  });

  group('PeriodSummaryGroup', () {
    PeriodFigure figureOf(String label) => PeriodFigure(
      label: label,
      value: r'$1.00',
      deltaPercent: null,
      goodDirection: GoodDirection.up,
    );

    Future<void> pumpGroup(WidgetTester tester, List<String> labels) async {
      wideSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.dark),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: PeriodSummaryGroup(
                  figures: [for (final l in labels) figureOf(l)],
                  state: ValueSectionState.failed,
                  onRetry: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a lone figure is just a card, with its own retry', (
      tester,
    ) async {
      await pumpGroup(tester, ['Invoiced']);

      expect(find.byType(VerticalDivider), findsNothing);
      expect(
        tester.widget<PeriodSummaryCard>(find.byType(PeriodSummaryCard)).framed,
        isTrue,
      );
      expect(find.text('Retry').hitTestable(), findsOneWidget);
    });

    testWidgets('grouped cells share one surface and one retry, at the end', (
      tester,
    ) async {
      await pumpGroup(tester, ['Invoiced', 'Payments', 'Expenses']);

      expect(find.byType(VerticalDivider), findsNWidgets(2));
      final cells = tester.widgetList<PeriodSummaryCard>(
        find.byType(PeriodSummaryCard),
      );
      expect(cells.map((c) => c.framed), everyElement(isFalse));
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Expenses'),
            matching: find.byType(PeriodSummaryCard),
          ),
          matching: find.text('Retry'),
        ),
        findsOneWidget,
      );
    });
  });
}
