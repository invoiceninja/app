import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_aging.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/utils/formatting.dart';

/// One bucket of the aging bar: what it is called, how much is in it, and
/// the tone it is drawn in.
class AgingSegment {
  const AgingSegment({
    required this.label,
    required this.amount,
    required this.formatted,
    required this.color,
  });

  final String label;
  final Decimal amount;

  /// [amount] through the company `Formatter`, in the figure's currency.
  final String formatted;
  final Color color;
}

/// The four buckets of [buckets] — Current, 1–30, 31–60, 60+ days past due —
/// labelled, formatted in [currencyId] (null: the company currency, which is
/// what the converted "All currencies" aggregate is in) and toned.
///
/// **One hue darkening with age, then amber and red.** Current and the first
/// month late are the same blue — the second a darker, greyer step of it — so
/// the bar reads as "mostly fine" until something is genuinely old; only the
/// last two buckets take a status tone (`warning`, `overdue`). The step is
/// derived from the `partial` token rather than added as a colour of its own.
List<AgingSegment> agingSegments(
  BuildContext context,
  DashboardAgingBuckets buckets, {
  required Formatter formatter,
  required String? currencyId,
}) {
  final tokens = context.inTheme;
  final blue = HSLColor.fromColor(tokens.partial);
  final olderBlue = blue
      .withLightness((blue.lightness - 0.12).clamp(0.0, 1.0))
      .withSaturation(blue.saturation * 0.55)
      .toColor();
  AgingSegment segment(String key, Decimal amount, Color color) => AgingSegment(
    label: context.tr(key),
    amount: amount,
    formatted: formatter.money(amount, currencyId: currencyId),
    color: color,
  );
  return [
    segment('current', buckets.current, tokens.partial),
    // The server's own aging report names its buckets with these keys.
    segment('age_group_0', buckets.days1To30, olderBlue),
    segment('age_group_30', buckets.days31To60, tokens.warning),
    segment('age_group_60_plus', buckets.days60Plus, tokens.overdue),
  ];
}

/// What a screen reader hears for the bar: "Aging: Current $24,310.00,
/// 0 - 30 Days $8,120.00, …". Every bucket, the empty ones included, so the
/// listener is never left to infer that a bucket was skipped.
String agingSpokenLabel(BuildContext context, List<AgingSegment> segments) =>
    '${context.tr('aging')}: '
    '${segments.map((s) => '${s.label} ${s.formatted}').join(', ')}';

/// The aging bar under Outstanding: one strip, each non-empty bucket a share
/// of it in proportion to its amount.
///
/// * **Proportions, so it mirrors in RTL.** The row follows the ambient
///   direction: Current sits at the start edge, the oldest at the end. It is
///   not a time axis (which stays physical) but a part-to-whole bar, read
///   from where the language starts reading.
/// * **No `LayoutBuilder`.** It sits in the figure row's `IntrinsicHeight`
///   (CLAUDE.md § Dashboard panels); the shares are `Expanded` flexes.
/// * **The details are a tooltip with a pointer and a sheet on touch.**
///   Hovering — or focusing — the bar lists every bucket; on touch a tap on
///   it opens [showAgingBreakdown] instead, through a 44 px band around the
///   8 px strip. With a pointer a click falls through to the card, whose link
///   it sits in.
///
/// Semantics are the card's: it reads [agingSpokenLabel] as part of its own
/// label and offers the breakdown as a custom action.
class AgingBar extends StatefulWidget {
  const AgingBar({super.key, required this.segments, this.onOpenBreakdown});

  final List<AgingSegment> segments;

  /// Opens the breakdown — wired on touch only.
  final VoidCallback? onOpenBreakdown;

  /// The strip's thickness. The review asked for at least 8: thinner, the
  /// two late buckets of a mostly current balance were hairlines.
  static const double height = 8;

  /// Space between two buckets, in the card's own surface.
  static const double gap = 2;

  /// The smallest share a non-empty bucket is drawn at, in thousandths — so
  /// $12 late against $40,000 owed is still a visible sliver, not nothing.
  static const int minShare = 12;

  @override
  State<AgingBar> createState() => _AgingBarState();
}

class _AgingBarState extends State<AgingBar> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final s in widget.segments)
        if (s.amount > Decimal.zero) s,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final total = shown.fold<double>(0, (sum, s) => sum + s.amount.toDouble());
    final strip = ClipRRect(
      // Square-ish, never a pill: 2 px on an 8 px strip.
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: AgingBar.height,
        child: Row(
          // A childless `ColoredBox` takes the smallest size it is allowed:
          // stretched, it fills the strip's height.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: AgingBar.gap),
              Expanded(
                flex: _flexOf(shown[i].amount.toDouble(), total),
                child: ColoredBox(color: shown[i].color),
              ),
            ],
          ],
        ),
      ),
    );
    if (Env.isTouchPrimary) {
      // A 44 px band, the strip centred in it: the strip alone is a target
      // nobody can hit.
      const pad = (InSizes.touchTarget - AgingBar.height) / 2;
      final band = Padding(
        padding: const EdgeInsets.symmetric(vertical: pad),
        child: strip,
      );
      final open = widget.onOpenBreakdown;
      if (open == null) return band;
      return GestureDetector(
        key: const ValueKey('aging-bar-tap'),
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: band,
      );
    }
    final tokens = context.inTheme;
    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          _tooltip.currentState?.ensureTooltipVisible();
        } else {
          Tooltip.dismissAllToolTips();
        }
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Tooltip(
            key: _tooltip,
            richMessage: TextSpan(
              children: [
                for (var i = 0; i < widget.segments.length; i++)
                  TextSpan(
                    text:
                        '${i > 0 ? '\n' : ''}${widget.segments[i].label}  '
                        '${widget.segments[i].formatted}',
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: focused
                      ? Border.all(color: tokens.accent, width: 1)
                      : null,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: strip,
              ),
            ),
          );
        },
      ),
    );
  }

  static int _flexOf(double amount, double total) {
    if (total <= 0) return 1;
    final share = (amount / total * 1000).round();
    return share < AgingBar.minShare ? AgingBar.minShare : share;
  }
}

/// The bar's details, for touch: each bucket with its tone, its amount and
/// its share of the whole. On the root navigator, so it rises over the shell
/// and Android back closes it (it is a route).
Future<void> showAgingBreakdown(
  BuildContext context, {
  required List<AgingSegment> segments,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AgingBreakdownSheet(segments: segments),
  );
}

/// The body of [showAgingBreakdown] — public so a test can pump it without
/// the modal route.
class AgingBreakdownSheet extends StatelessWidget {
  const AgingBreakdownSheet({super.key, required this.segments});

  final List<AgingSegment> segments;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final gutter = InSpacing.lg(context);
    // The bar's total: only buckets above zero are drawn in it, so a credit
    // (a negative bucket) summed in here pushed the others past 100%.
    final total = segments.fold<double>(
      0,
      (sum, s) => s.amount > Decimal.zero ? sum + s.amount.toDouble() : sum,
    );
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(gutter, 0, gutter, gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            headingLevel: 1,
            child: Text(
              context.tr('aging'),
              style: textTheme.titleMedium?.copyWith(
                color: tokens.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: InSpacing.md(context)),
          ExcludeSemantics(child: AgingBar(segments: segments)),
          SizedBox(height: InSpacing.md(context)),
          for (final s in segments)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: InSizes.touchTarget),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: InSpacing.sm),
                  Expanded(
                    child: Text(
                      s.label,
                      style: textTheme.bodyMedium?.copyWith(color: tokens.ink),
                    ),
                  ),
                  LtrText(
                    // A credit has no share of the bar: a dash, not 0%.
                    s.amount < Decimal.zero
                        ? '—'
                        : total <= 0
                        ? '0%'
                        : '${(s.amount.toDouble() / total * 100).round()}%',
                    style: textTheme.bodySmall?.copyWith(color: tokens.ink2),
                  ),
                  SizedBox(width: InSpacing.md(context)),
                  LtrText(
                    s.formatted,
                    style: moneyTextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: tokens.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
