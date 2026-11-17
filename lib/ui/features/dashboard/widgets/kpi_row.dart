import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_aging.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/data/repositories/dashboard_repository.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/dashboard/helpers/needs_attention.dart';
import 'package:admin/ui/features/dashboard/helpers/totals_math.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/aging_bar.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_figures.dart';
import 'package:admin/ui/features/dashboard/widgets/delta_chip.dart';
import 'package:admin/utils/formatting.dart';

/// Content width from which every summary card shares one row. Measured on the
/// row's own width, not the window: a 1280 px window leaves ~1000 px of
/// content beside the sidebar, and a threshold of 1024 put the figures on two
/// rows there.
const double kFiguresOneRowWidth = 880;

/// Content width from which the cards go two to a row; below it, one.
const double kFiguresTwoPerRowWidth = 440;

/// The dashboard's figures on a wide screen: four cards in one layout —
/// **Outstanding**, what is unpaid today with its aging bar, then
/// **Invoiced · Payments · Expenses** for the selected period, each with its
/// change against the compared period the row above names.
///
/// Outstanding is a balance as of now and ignores the date range; the other
/// three are flows inside it. They share a layout — label (↗ only on a link),
/// value, footer — so the eye reads four answers, not two kinds of card.
/// Expenses is drawn only with the module on, and is never a link.
///
/// Four (or three) to a row from [kFiguresOneRowWidth], two to a row from
/// [kFiguresTwoPerRowWidth] — with an odd count Outstanding takes the first
/// row alone, so the pairs under it are even — and one to a row below that.
/// The `LayoutBuilder` measuring that is the row's root; nothing under the
/// `IntrinsicHeight` rows it builds is measured by one.
///
/// Every figure draws a skeleton until its section has answered, and a dash
/// with a retry when it could not: the old row formatted `amount ?? zero`, so
/// "not loaded" and "failed" both read as `$0.00`.
class KpiRow extends StatelessWidget {
  const KpiRow({
    super.key,
    required this.vm,
    required this.formatter,
    this.attention,
    this.showExpenses = true,
    this.onOutstandingTap,
    this.onInvoicesTap,
    this.onPaidTap,
  });

  final DashboardViewModel vm;
  final Formatter formatter;

  /// The needs-attention band's buckets, so what Outstanding calls past due
  /// is what the band calls past due. Null when the past-due list has not
  /// loaded or is not offered.
  final NeedsAttention? attention;

  /// Whether the Expenses figure is drawn (the expenses module is on).
  final bool showExpenses;

  final VoidCallback? onOutstandingTap;
  final VoidCallback? onInvoicesTap;
  final VoidCallback? onPaidTap;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      buildOutstandingCard(
        context,
        vm: vm,
        formatter: formatter,
        attention: attention,
        onTap: onOutstandingTap,
        valueFontSize: dashboardDense(context) ? 20 : 24,
      ),
      ...buildPeriodSummaryCards(
        context,
        vm: vm,
        formatter: formatter,
        showExpenses: showExpenses,
        onInvoicesTap: onInvoicesTap,
        onPaidTap: onPaidTap,
      ),
    ];
    final gap = dashboardDense(context)
        ? InSpacing.md(context)
        : InSpacing.lg(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perRow = width >= kFiguresOneRowWidth
            ? cards.length
            : width >= kFiguresTwoPerRowWidth
            ? 2
            : 1;
        final rows = figureRows(cards.length, perRow);
        var next = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: gap),
              _row([for (var i = 0; i < rows[r]; i++) cards[next++]], gap),
            ],
          ],
        );
      },
    );
  }

  Widget _row(List<Widget> cards, double gap) {
    if (cards.length == 1) return cards.single;
    // Stretched so the cards end on one line, and their footers with them.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

/// How [count] cards are laid out at [perRow] to a row: the size of each row,
/// in order. With an odd count over rows of two, the first card — Outstanding
/// — takes a row alone, so the rest pair up evenly instead of leaving a
/// half-empty last row.
List<int> figureRows(int count, int perRow) {
  if (count <= 0) return const [];
  if (perRow <= 1) return List.filled(count, 1);
  if (perRow >= count) return [count];
  final rows = <int>[];
  var left = count;
  if (perRow == 2 && count.isOdd) {
    rows.add(1);
    left--;
  }
  while (left > 0) {
    final n = left < perRow ? left : perRow;
    rows.add(n);
    left -= n;
  }
  return rows;
}

/// What Outstanding's footer calls past due — **the band's definition**: an
/// invoice is past due once its due date has passed (`needsAttention`), and
/// the late amount is `lateAmount`'s.
///
/// In order:
///
/// 1. **The band's proven sum** ([NeedsAttention.pastDueSum]) when it is in
///    the currency the figure shows — the selected one, or the company's
///    under "All currencies". The band prints that same number, so the two
///    cannot disagree.
/// 2. **Nothing**, when the band has loaded and is exactly empty: a figure
///    claiming something is late beside a band saying nothing is would be
///    the one contradiction this rule exists to prevent.
/// 3. **The aging's late buckets** ([DashboardAgingBuckets.pastDue]) — the
///    server's sum over every invoice whose due date has passed, in the
///    figure's currency (converted under "All"). Used when the band cannot
///    prove a sum: more than a page of late invoices, or several currencies.
///    The one case it can differ from the band's rule is a late *deposit* on
///    an invoice not yet due, which the server buckets as current.
/// 4. **The band's count** ("4 past due"), as the card said before there was
///    an aging, when no amount is known.
({Decimal? amount, AttentionCount? count}) outstandingPastDue({
  required NeedsAttention? attention,
  required DashboardAgingBuckets? aging,
  required String? currencyKey,
  required String companyCurrencyId,
}) {
  final sum = attention?.pastDueSum;
  final shownCurrency = currencyKey ?? companyCurrencyId;
  if (attention != null && sum != null) {
    final sumCurrency = attention.pastDueCurrencyId.isEmpty
        ? companyCurrencyId
        : attention.pastDueCurrencyId;
    if (sumCurrency == shownCurrency) {
      return (amount: sum > Decimal.zero ? sum : null, count: null);
    }
  }
  final count = attention?.pastDueCount;
  if (count != null && count.exact && count.value == 0) {
    return (amount: null, count: null);
  }
  if (aging != null) {
    final late = aging.pastDue;
    return (amount: late > Decimal.zero ? late : null, count: null);
  }
  return (amount: null, count: count != null && count.value > 0 ? count : null);
}

/// The Outstanding card for [vm]. A function rather than a widget so the wide
/// row and the phone's hero build the very same card from the same rules.
OutstandingFigureCard buildOutstandingCard(
  BuildContext context, {
  required DashboardViewModel vm,
  required Formatter formatter,
  required NeedsAttention? attention,
  required VoidCallback? onTap,
  double? valueFontSize,
}) {
  final currencyKey = selectedCurrencyKey(vm.filter.currencyId);
  final bucket = selectCurrencyTotals(vm.outstanding.data, currencyKey);
  final aging = selectAgingBuckets(vm.aging.data, currencyKey);
  final late = outstandingPastDue(
    attention: attention,
    aging: aging,
    currencyKey: currencyKey,
    companyCurrencyId: formatter.settings.currencyId,
  );
  final lateAmount = late.amount;
  return OutstandingFigureCard(
    state: vm.outstanding.valueState,
    value: formatter.money(
      figureAmount(bucket?.outstandingAmount),
      currencyId: currencyKey,
    ),
    caption: context.tr('unpaid_count_label', {
      'count': '${bucket?.outstandingCount ?? 0}',
    }),
    pastDueAmount: lateAmount == null
        ? null
        : formatter.money(lateAmount, currencyId: currencyKey),
    pastDueCount: late.count?.toString(),
    aging: aging == null
        ? null
        : agingSegments(
            context,
            aging,
            formatter: formatter,
            currencyId: currencyKey,
          ),
    onTap: onTap,
    onRetry: () => vm.retry(DashboardKind.totalsOutstanding),
    // The wide card's own size, one step smaller under Compact.
    valueFontSize: valueFontSize ?? (dashboardDense(context) ? 22 : 26),
  );
}

/// The three period figures — Invoiced, Payments, Expenses — for [vm], read
/// once for the phone's single card and the wide row's three.
List<PeriodFigure> _periodFigures(
  BuildContext context, {
  required DashboardViewModel vm,
  required Formatter formatter,
  required bool showExpenses,
  required VoidCallback? onInvoicesTap,
  required VoidCallback? onPaidTap,
  required bool comparedWhenFlat,
}) {
  final currencyKey = selectedCurrencyKey(vm.filter.currencyId);
  final DashboardCurrencyTotals? current = selectCurrencyTotals(
    vm.totals.data,
    currencyKey,
  );
  final DashboardCurrencyTotals? previous = selectCurrencyTotals(
    vm.totalsPrevious.data,
    currencyKey,
  );
  String money(DashboardCurrencyTotals? t, _Pick pick) =>
      formatter.money(figureAmount(pick(t)), currencyId: currencyKey);
  double? delta(_Pick pick) => percentDelta(pick(current), pick(previous));
  // Only beside a trend: with nothing to compare against there is no "vs".
  // The wide cards also name a previous zero ("vs $0.00" by a neutral chip).
  String? compared(_Pick pick) {
    if (vm.totalsPrevious.data == null) return null;
    if (delta(pick) == null && !comparedWhenFlat) return null;
    return money(previous, pick);
  }

  return [
    PeriodFigure(
      label: context.tr('invoiced'),
      value: money(current, (t) => t?.invoicedAmount),
      deltaPercent: delta((t) => t?.invoicedAmount),
      compared: compared((t) => t?.invoicedAmount),
      goodDirection: GoodDirection.up,
      onTap: onInvoicesTap,
    ),
    PeriodFigure(
      label: context.tr('payments'),
      value: money(current, (t) => t?.revenuePaidToDate),
      deltaPercent: delta((t) => t?.revenuePaidToDate),
      compared: compared((t) => t?.revenuePaidToDate),
      goodDirection: GoodDirection.up,
      onTap: onPaidTap,
    ),
    if (showExpenses)
      PeriodFigure(
        label: context.tr('expenses'),
        value: money(current, (t) => t?.expensesAmount),
        deltaPercent: delta((t) => t?.expensesAmount),
        compared: compared((t) => t?.expensesAmount),
        // Spending less is the good direction.
        goodDirection: GoodDirection.down,
        // No link: the expenses list has no date filter it can show, and a
        // figure that opens an unfiltered list promises rows it does not
        // deliver.
      ),
  ];
}

/// The period figures as cards of their own, for the wide row.
List<PeriodSummaryCard> buildPeriodSummaryCards(
  BuildContext context, {
  required DashboardViewModel vm,
  required Formatter formatter,
  required bool showExpenses,
  required VoidCallback? onInvoicesTap,
  required VoidCallback? onPaidTap,
}) {
  final figures = _periodFigures(
    context,
    vm: vm,
    formatter: formatter,
    showExpenses: showExpenses,
    onInvoicesTap: onInvoicesTap,
    onPaidTap: onPaidTap,
    comparedWhenFlat: true,
  );
  // A trend needs a compared period ("All time" has none) whose figures are
  // in hand.
  final compares = vm.comparison != null && vm.totalsPrevious.data != null;
  final dense = dashboardDense(context);
  return [
    for (final figure in figures)
      PeriodSummaryCard(
        figure: figure,
        state: vm.totals.valueState,
        compares: compares,
        // The three fail together, but each card is its own surface: a retry
        // on each is one tap wherever the eye lands.
        onRetry: () => vm.retry(DashboardKind.totalsCurrent),
        valueFontSize: dense ? 20 : 24,
      ),
  ];
}

/// The period card for [vm] — one card, three cells: the phone's form.
PeriodFiguresCard buildPeriodCard(
  BuildContext context, {
  required DashboardViewModel vm,
  required Formatter formatter,
  required bool showExpenses,
  required VoidCallback? onInvoicesTap,
  required VoidCallback? onPaidTap,
  double? valueFontSize,
  bool inlineDelta = true,
}) {
  return PeriodFiguresCard(
    state: vm.totals.valueState,
    onRetry: () => vm.retry(DashboardKind.totalsCurrent),
    valueFontSize: valueFontSize ?? (dashboardDense(context) ? 20 : 22),
    inlineDelta: inlineDelta,
    figures: _periodFigures(
      context,
      vm: vm,
      formatter: formatter,
      showExpenses: showExpenses,
      onInvoicesTap: onInvoicesTap,
      onPaidTap: onPaidTap,
      comparedWhenFlat: false,
    ),
  );
}

typedef _Pick = Decimal? Function(DashboardCurrencyTotals? totals);
