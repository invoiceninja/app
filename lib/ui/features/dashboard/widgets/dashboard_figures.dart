import 'package:decimal/decimal.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/widgets/aging_bar.dart';
import 'package:admin/ui/features/dashboard/widgets/delta_chip.dart';
import 'package:admin/utils/bidi.dart';

/// One period figure: what it is called, what it is, and how it moved.
class PeriodFigure {
  const PeriodFigure({
    required this.label,
    required this.value,
    required this.deltaPercent,
    required this.goodDirection,
    this.compared,
    this.onTap,
  });

  /// The compared period's amount, formatted, shown after the trend ("vs
  /// $9,286.00") where the cell has room: a percentage alone does not say
  /// whether 43 % down is a bad month or a rounding of two small ones.
  final String? compared;

  final String label;

  /// The formatted amount. Only read when the section is ready or stale.
  final String value;

  /// Change against the compared period, or null when there is nothing to
  /// compare with — in which case no trend is drawn at all, rather than a
  /// dash that reads as "no change".
  final double? deltaPercent;
  final GoodDirection goodDirection;

  /// Opens the list behind the figure. Null draws no chevron: a figure with no
  /// list that can show the same rows is not dressed up as a link.
  final VoidCallback? onTap;
}

/// Height floor of a figure card. A floor, not an extent — the fixed 140 px
/// cell this replaced clipped its last line as soon as a caption met a larger
/// text size.
const double kFigureCardMinHeight = 104;

/// The card surface every figure sits on: surface, hairline border, the card
/// radius and the resting shadow.
class _FigureSurface extends StatelessWidget {
  const _FigureSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final radius = BorderRadius.circular(dashboardCardRadius(context));
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius),
      child: Material(
        color: tokens.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border),
          borderRadius: radius,
        ),
        child: child,
      ),
    );
  }
}

/// A figure's caption — sentence case in `ink2` (`ink3` at this size is under
/// 4:1 on a white card), with ↗ after it when the figure is a link.
class _FigureCaption extends StatelessWidget {
  const _FigureCaption({required this.label, required this.linked});

  final String label;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: tokens.ink2,
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
    );
    // Scaled down to fit, like the figure beneath it, never ellipsised: three
    // cells across a phone at 140% text leave a caption about 75 px, and
    // "RECHNU…" over a number does not say what the number is.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(width: 4),
                // ↗ — "opens a list". Only on a link: Expenses has none.
                Icon(Icons.arrow_outward, size: 14, color: tokens.ink2),
              ],
            )
          : text,
    );
  }
}

/// A figure's value in each of the states it can honestly be in.
///
/// * `loading` — a bar where the number will be. Never a zero: `$0.00` is an
///   answer, and before the fetch returns there isn't one.
/// * `failed` — a dash. The card it sits in offers the retry.
/// * `ready` / `stale` — the number, scaled down to fit rather than
///   ellipsised: `$1,234,5…` is not an amount.
class FigureValue extends StatelessWidget {
  const FigureValue({
    super.key,
    required this.state,
    required this.value,
    this.fontSize = 24,
  });

  final ValueSectionState state;
  final String value;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final style = moneyTextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.4,
      height: 1.25,
      color: tokens.ink,
    );
    switch (state) {
      case ValueSectionState.loading:
        // Sized by the same line box as the number it stands in for, so the
        // card does not change height when the value lands.
        return Semantics(
          label: context.tr('loading_ellipsis'),
          child: SizedBox(
            height:
                (fontSize * 1.25) * MediaQuery.textScalerOf(context).scale(1),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FigureSkeletonBar(width: fontSize * 4.5, height: 14),
            ),
          ),
        );
      case ValueSectionState.failed:
        return Text(
          '—',
          maxLines: 1,
          style: style.copyWith(color: tokens.ink3),
        );
      case ValueSectionState.stale:
      case ValueSectionState.ready:
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: LtrText(value, maxLines: 1, softWrap: false, style: style),
        );
    }
  }
}

/// A placeholder bar for something still loading. Drawn in the border tone:
/// the alternate surface the old skeletons used is 1.04–1.22:1 against a card,
/// which is to say invisible.
class FigureSkeletonBar extends StatelessWidget {
  const FigureSkeletonBar({super.key, required this.width, this.height = 12});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.inTheme.border,
      borderRadius: BorderRadius.circular(InRadii.r1),
    ),
  );
}

/// The small control in a card's corner when its figures could not be loaded:
/// "Retry" when there is nothing to show, a warning glyph when an older answer
/// is still on screen.
class _FigureRetry extends StatelessWidget {
  const _FigureRetry({required this.state, required this.onRetry});

  final ValueSectionState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;
    if (onRetry == null) return const SizedBox.shrink();
    final tokens = context.inTheme;
    final extent = Env.isTouchPrimary ? InSizes.touchTarget : 28.0;
    switch (state) {
      case ValueSectionState.failed:
        return TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            minimumSize: Size(48, extent),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(context.tr('retry')),
        );
      case ValueSectionState.stale:
        return IconButton(
          // The figure is real, but not current: the last refresh failed.
          tooltip:
              '${context.tr('could_not_load_label')} · ${context.tr('retry')}',
          onPressed: onRetry,
          icon: Icon(Icons.sync_problem, size: 16, color: tokens.warning),
          constraints: BoxConstraints.tightFor(width: extent, height: extent),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case ValueSectionState.loading:
      case ValueSectionState.ready:
        return const SizedBox.shrink();
    }
  }
}

/// The one layout every summary figure shares — Outstanding and, on a wide
/// screen, each period figure: the label (with ↗ only when the card is a
/// link), the value, an optional strip under it (Outstanding's aging bar),
/// and a footer pinned to the card's bottom edge.
///
/// The footer sits at the bottom whatever the card's height: the top block and
/// the footer are the two children of a `spaceBetween` column, so in a
/// stretched row (`IntrinsicHeight`) every card's footer lands on one line,
/// and alone the card is as tall as its content above the floor. No
/// `LayoutBuilder` anywhere under it — the row measures it intrinsically.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.state,
    required this.value,
    required this.valueFontSize,
    required this.spoken,
    this.onTap,
    this.onRetry,
    this.strip,
    this.footer,
    this.inlineFooter = false,
    this.semanticsActions,
  });

  final String label;
  final ValueSectionState state;
  final String value;
  final double valueFontSize;

  /// The whole card as one sentence for a screen reader.
  final String spoken;

  /// Null draws no ↗ and no ink: a figure with nowhere to go is not a link.
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  /// Drawn under the value — the aging bar.
  final Widget? strip;
  final Widget? footer;

  /// Compact's one-line form: the footer beside the value, not under it.
  final bool inlineFooter;
  final Map<CustomSemanticsAction, VoidCallback>? semanticsActions;

  @override
  Widget build(BuildContext context) {
    final dense = dashboardDense(context);
    final valueWidget = FigureValue(
      state: state,
      value: value,
      fontSize: valueFontSize,
    );
    final footer = this.footer;
    final strip = this.strip;
    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _FigureCaption(label: label, linked: onTap != null),
              ),
            ),
            _FigureRetry(state: state, onRetry: onRetry),
          ],
        ),
        SizedBox(height: dense ? 2 : 6),
        if (inlineFooter && footer != null)
          _InlineSubline(value: valueWidget, subline: footer)
        else
          valueWidget,
        // On touch the strip brings its own room: it is centred in a 44 px
        // band, its tap target.
        if (strip != null) ...[
          if (!Env.isTouchPrimary) SizedBox(height: dense ? 2 : 6),
          strip,
        ],
      ],
    );
    final body = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: dense ? kFigureCardMinHeightDense : kFigureCardMinHeight,
      ),
      child: Padding(
        padding: _figurePadding(context, dense: dense),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // `min` still takes a tight height in full — a stretched row's — and
          // `spaceBetween` then puts the spare room above the footer.
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            top,
            if (footer != null && !inlineFooter)
              Padding(
                padding: EdgeInsets.only(
                  top: strip == null
                      ? (dense ? 4 : 8)
                      : (Env.isTouchPrimary ? 0 : (dense ? 2 : 4)),
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: spoken,
      button: onTap != null,
      onTap: onTap,
      customSemanticsActions: semanticsActions,
      child: ExcludeSemantics(
        child: _FigureSurface(
          child: onTap == null ? body : InkWell(onTap: onTap, child: body),
        ),
      ),
    );
  }
}

/// A footer's small text style: `ink2` on the card.
TextStyle? _footerStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.inTheme.ink2, fontSize: 12);

/// **Outstanding** — everything unpaid today, whatever the date range.
///
/// It carries no trend. The figure is a balance, not a flow: there is no
/// "outstanding last month" in the totals to set it against, and the old chip
/// compared the unpaid remainder of two unrelated sets of invoices.
///
/// Under the value, the aging bar ([aging]) when the server gave one; in the
/// footer, "14 unpaid" and what is past due — an amount when one is known
/// ([pastDueAmount]), otherwise the band's count ([pastDueCount]). See
/// `outstandingPastDue` for which source wins.
class OutstandingFigureCard extends StatelessWidget {
  const OutstandingFigureCard({
    super.key,
    required this.state,
    required this.value,
    required this.caption,
    this.pastDueAmount,
    this.pastDueCount,
    this.aging,
    this.onTap,
    this.onRetry,
    this.valueFontSize = 26,
  });

  final ValueSectionState state;
  final String value;

  /// "9 unpaid". Null while not known.
  final String? caption;

  /// What is past due, formatted ("$12,838.00") — drawn "$12,838.00 past
  /// due" in the overdue tone. Null when no amount is known.
  final String? pastDueAmount;

  /// How many invoices are past due ("4"), drawn "4 past due" — only when
  /// there is no [pastDueAmount].
  final String? pastDueCount;

  /// The aging bar's buckets; null (or nothing in them) draws no bar. Never a
  /// zero bar: a server without the endpoint, or a failed fetch, leaves it
  /// out.
  final List<AgingSegment>? aging;

  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final double valueFontSize;

  /// Whether this card is showing a figure the server returned — as opposed to
  /// a placeholder or a dash. The integration suites wait on it as their
  /// "dashboard has loaded" signal: the card itself is on screen from the
  /// first frame, so its presence alone proves nothing.
  bool get showsLoadedValue =>
      state == ValueSectionState.ready || state == ValueSectionState.stale;

  /// The past-due half of the footer as plain text, for the spoken label.
  String? _pastDueText(BuildContext context) {
    final amount = pastDueAmount;
    if (amount != null) {
      return context.tr('past_due_amount_label', {'amount': amount});
    }
    final count = pastDueCount;
    if (count != null) {
      return context.tr('past_due_count_label', {'count': count});
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final label = context.tr('outstanding');
    final known = showsLoadedValue;
    final dense = dashboardDense(context);
    final segments = known ? aging : null;
    final hasBar =
        segments != null && segments.any((s) => s.amount > Decimal.zero);
    void openBreakdown() => showAgingBreakdown(context, segments: segments!);

    Widget? footer;
    if (known && (caption != null || _pastDueText(context) != null)) {
      final style = _footerStyle(context);
      final unpaid = caption == null
          ? null
          : Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
      final late = _pastDue(context, style, tokens);
      // A `Wrap`, not a `Row`: at a large text size the past-due half drops to
      // a line of its own rather than being cut. Ends apart while they fit.
      footer = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: InSpacing.sm,
        children: [?unpaid, ?late],
      );
    }

    final spoken = known
        ? [
            label,
            value,
            ?caption,
            ?_pastDueText(context),
            if (hasBar) agingSpokenLabel(context, segments),
          ].join(', ')
        : '$label, ${context.tr('loading_ellipsis')}';
    return _SummaryCard(
      label: label,
      state: state,
      value: value,
      valueFontSize: valueFontSize,
      spoken: spoken,
      onTap: onTap,
      onRetry: onRetry,
      // Compact keeps the old one-line form — the footer beside the value —
      // and the bar under both.
      inlineFooter: dense,
      footer: footer,
      strip: hasBar
          ? AgingBar(segments: segments, onOpenBreakdown: openBreakdown)
          : null,
      semanticsActions: hasBar
          ? {CustomSemanticsAction(label: context.tr('aging')): openBreakdown}
          : null,
    );
  }

  /// "$12,838.00 past due" with the amount in the overdue tone, or "4 past
  /// due". The sentence is the translation's, split around the amount so the
  /// amount alone takes the tone; in a right-to-left layout the amount is an
  /// LTR isolate, so its sign and symbol stay where they belong.
  Widget? _pastDue(BuildContext context, TextStyle? style, InTheme tokens) {
    final amount = pastDueAmount;
    if (amount == null) {
      final text = _pastDueText(context);
      return text == null
          ? null
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
    }
    const mark = '\u0000';
    final parts = context
        .tr('past_due_amount_label', {'amount': mark})
        .split(mark);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final shown = rtl ? ltrIsolate(amount) : amount;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (parts.isNotEmpty) TextSpan(text: parts.first),
          TextSpan(
            text: shown,
            style: TextStyle(
              color: tokens.overdue,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (parts.length > 1) TextSpan(text: parts.sublist(1).join()),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// One period figure as a card of its own — Invoiced, Payments or Expenses
/// on a wide screen, in the same layout as Outstanding beside it.
///
/// The footer is the trend: a chip (arrow and sign, not colour alone) and
/// "vs {previous}". With a compared period but nothing to divide by (the
/// previous figure is zero) there is no chip, just "vs $0.00"; with no
/// compared period at all ("All time") there is no footer.
class PeriodSummaryCard extends StatelessWidget {
  const PeriodSummaryCard({
    super.key,
    required this.figure,
    required this.state,
    this.compares = false,
    this.onRetry,
    this.valueFontSize = 24,
  });

  final PeriodFigure figure;
  final ValueSectionState state;

  /// Whether the compared period's figure is in hand — draws the footer even
  /// when [PeriodFigure.deltaPercent] is null (then "vs $0.00" alone, no
  /// chip).
  final bool compares;

  final VoidCallback? onRetry;
  final double valueFontSize;

  @override
  Widget build(BuildContext context) {
    final known =
        state == ValueSectionState.ready || state == ValueSectionState.stale;
    final onTap = known ? figure.onTap : null;
    final delta = figure.deltaPercent;
    final compared = figure.compared;
    // A previous zero leaves nothing to divide by: the footer is then the
    // comparison alone, which `DeltaChip` draws without its chip.
    final footer = known && compares && (delta != null || compared != null)
        ? DeltaChip(
            percent: delta,
            goodDirection: figure.goodDirection,
            filled: true,
            suffix: compared == null
                ? null
                : context.tr('vs_amount', {'amount': compared}),
          )
        : null;
    return _SummaryCard(
      label: figure.label,
      state: state,
      value: figure.value,
      valueFontSize: valueFontSize,
      spoken: known
          ? _spokenFigure(context, figure, delta)
          : '${figure.label}, ${context.tr('loading_ellipsis')}',
      onTap: onTap,
      onRetry: onRetry,
      footer: footer,
    );
  }
}

/// A period figure as a screen reader hears it, trend included.
String _spokenFigure(BuildContext context, PeriodFigure figure, double? delta) {
  if (delta == null) {
    return context.tr('kpi_no_delta_semantic', {
      'label': figure.label,
      'value': figure.value,
    });
  }
  return context.tr('kpi_with_delta_semantic', {
    'label': figure.label,
    'value': figure.value,
    'direction': context.tr(delta > 0 ? 'delta_up' : 'delta_down'),
    'percent': delta.abs().toStringAsFixed(1),
  });
}

/// The period's figures — Invoices, Payments, Expenses — as cells of one card,
/// divided by hairlines.
///
/// One card rather than three tiles: they are one answer ("how did this period
/// go") from one request, they load and fail together, and a shared surface
/// lets them share a single retry instead of three.
class PeriodFiguresCard extends StatelessWidget {
  const PeriodFiguresCard({
    super.key,
    required this.state,
    required this.figures,
    this.onRetry,
    this.valueFontSize = 22,
    this.inlineDelta = true,
  });

  final ValueSectionState state;
  final List<PeriodFigure> figures;

  final VoidCallback? onRetry;
  final double valueFontSize;

  /// Whether Compact may put each trend on its value's line. A phone's three
  /// narrow cells cannot take it; they keep the trend on a line of its own
  /// and give up only padding.
  final bool inlineDelta;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final dense = dashboardDense(context);
    return _FigureSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: !dense
              ? kFigureCardMinHeight
              : (inlineDelta ? kFigureCardMinHeightDense : 72),
        ),
        child: Stack(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < figures.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: tokens.border,
                      ),
                    Expanded(
                      child: _PeriodCell(
                        figure: figures[i],
                        state: state,
                        valueFontSize: valueFontSize,
                        inlineDelta: inlineDelta,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // In the corner, over the last cell's free space: one retry for
            // the three figures that fail together.
            PositionedDirectional(
              top: 4,
              end: 4,
              child: _FigureRetry(state: state, onRetry: onRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodCell extends StatelessWidget {
  const _PeriodCell({
    required this.figure,
    required this.state,
    required this.valueFontSize,
    required this.inlineDelta,
  });

  final PeriodFigure figure;
  final ValueSectionState state;
  final double valueFontSize;
  final bool inlineDelta;

  @override
  Widget build(BuildContext context) {
    final known =
        state == ValueSectionState.ready || state == ValueSectionState.stale;
    final delta = figure.deltaPercent;
    final onTap = known ? figure.onTap : null;
    final dense = dashboardDense(context);
    final valueWidget = FigureValue(
      state: state,
      value: figure.value,
      fontSize: valueFontSize,
    );
    final chip = known && delta != null
        ? DeltaChip(
            percent: delta,
            goodDirection: figure.goodDirection,
            // Not under Compact or on a phone's inline cell: three figures
            // share that row.
            suffix: dense || figure.compared == null
                ? null
                : context.tr('vs_amount', {'amount': figure.compared!}),
          )
        : null;
    final Widget body;
    if (dense && inlineDelta) {
      body = Padding(
        padding: _figurePadding(context, dense: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _FigureCaption(label: figure.label, linked: onTap != null),
            ),
            const SizedBox(height: 2),
            if (chip == null)
              valueWidget
            else
              _InlineSubline(value: valueWidget, subline: chip),
          ],
        ),
      );
    } else {
      body = _stackedBody(context, onTap, valueWidget, chip, dense: dense);
    }
    return Semantics(
      container: true,
      label: known
          ? _spokenFigure(context, figure, delta)
          : '${figure.label}, ${context.tr('loading_ellipsis')}',
      button: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }

  /// Caption, value and the trend on a line of its own — Normal everywhere,
  /// and Compact in a phone's narrow cells.
  Widget _stackedBody(
    BuildContext context,
    VoidCallback? onTap,
    Widget valueWidget,
    Widget? chip, {
    required bool dense,
  }) {
    return Padding(
      padding: dense
          ? EdgeInsets.symmetric(
              horizontal: InSpacing.lg(context),
              vertical: InSpacing.sm,
            )
          : EdgeInsets.all(InSpacing.lg(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _FigureCaption(label: figure.label, linked: onTap != null),
          ),
          const SizedBox(height: 4),
          valueWidget,
          const SizedBox(height: 2),
          // The line is kept even with no trend to draw, so the three cells
          // put their values on one baseline.
          SizedBox(
            height: 18 * MediaQuery.textScalerOf(context).scale(1),
            child: chip == null
                ? null
                : Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: chip,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Zero when the totals carry no bucket for the selected currency — a real
/// zero, since the totals did load. (Before they load the cards draw a
/// skeleton and never read this.)
Decimal figureAmount(Decimal? amount) => amount ?? Decimal.zero;

/// A figure card's padding: [InSpacing.lg] all round, or under Compact the
/// same sides over `md` top and bottom.
EdgeInsets _figurePadding(BuildContext context, {required bool dense}) => dense
    ? EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: InSpacing.md(context),
      )
    : EdgeInsets.all(InSpacing.lg(context));

/// Compact's one-line figure: the value, then its caption or trend beside it
/// rather than under it ("\$57,905.00  17 unpaid"). The value keeps the room
/// it needs and the subline ellipsises; both scale with the text size, so the
/// card's floor is still a floor.
class _InlineSubline extends StatelessWidget {
  const _InlineSubline({required this.value, required this.subline});

  final Widget value;
  final Widget subline;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Flexible(flex: 3, child: value),
      const SizedBox(width: InSpacing.sm),
      Flexible(flex: 2, child: subline),
    ],
  );
}
