import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// Direction-of-good for the [DeltaChip]: which way a positive delta is good.
/// Revenue/Paid: up. Outstanding/Overdue/Expenses: down. Avg days to pay: down.
enum GoodDirection { up, down }

/// Compact "+18.4% vs prior" pill with an up/down arrow. The color resolves
/// from the sign × [goodDirection]:
///   - matches direction-of-good → paid color (positive vibe)
///   - opposes direction-of-good → overdue color (negative vibe)
///   - zero → ink3 (neutral)
///
/// [filled] is the dashboard summary cards' form: the trend on a soft tinted
/// chip (a rounded rectangle, never a pill) with ↑ / ↓ and the sign, so the
/// direction never rests on colour alone. With nothing to divide by (a null
/// [percent]: the previous figure was zero) there is **no chip** — just the
/// [suffix], "vs $0.00", which already says why there is no trend. The
/// neutral "—" chip this replaced read as a missing value, and a rise from
/// zero has no percentage worth inventing.
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.percent,
    required this.goodDirection,
    this.suffix,
    this.filled = false,
  });

  final bool filled;

  /// Signed percent. Positive = `up`, negative = `down`.
  final double? percent;

  final GoodDirection goodDirection;

  /// Optional trailing text (e.g. "vs prior"). Renders in `ink3`.
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final p = percent;
    if (filled) return _filled(context, tokens, p);
    if (p == null) {
      return Text(
        suffix == null ? '—' : '— $suffix',
        style: TextStyle(fontSize: 11.5, color: tokens.ink3),
      );
    }
    final isZero = p.abs() < 0.05;
    final dir = p < 0 ? GoodDirection.down : GoodDirection.up;
    final Color color;
    if (isZero) {
      color = tokens.ink3;
    } else {
      color = dir == goodDirection ? tokens.paid : tokens.overdue;
    }
    final arrow = dir == GoodDirection.up
        ? Icons.arrow_drop_up
        : Icons.arrow_drop_down;
    final formatted = '${p > 0 ? '+' : ''}${p.toStringAsFixed(1)}%';
    final trend = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isZero) Icon(arrow, size: 14, color: color),
        Text(
          formatted,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
    return _withSuffix(trend, tokens);
  }

  Widget _filled(BuildContext context, InTheme tokens, double? p) {
    // Nothing to divide by: the comparison alone, no chip.
    if (p == null) {
      final tail = suffix;
      return tail == null ? const SizedBox.shrink() : _suffixText(tail, tokens);
    }
    final isZero = p.abs() < 0.05;
    final dir = p < 0 ? GoodDirection.down : GoodDirection.up;
    final good = dir == goodDirection;
    final (Color ink, Color fill) = isZero
        ? (tokens.ink2, tokens.draftSoft)
        : good
        ? (tokens.paid, tokens.paidSoft)
        : (tokens.overdue, tokens.overdueSoft);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(InRadii.r1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isZero) ...[
            Icon(
              dir == GoodDirection.up
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 11,
              color: ink,
            ),
            const SizedBox(width: 2),
          ],
          Text(
            '${p > 0 ? '+' : ''}${p.toStringAsFixed(1)}%',
            // An LTR run: "+36.2%" keeps its sign in front in Arabic too.
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
    return _withSuffix(chip, tokens);
  }

  Widget _withSuffix(Widget trend, InTheme tokens) {
    final tail = suffix;
    if (tail == null) return trend;
    // A `Wrap`, so a suffix the cell has no room for ("vs $9,286.00" in a
    // third of a phone's width, or at a large text size) drops to a line of
    // its own instead of overflowing. Not a `LayoutBuilder`: the dashboard's
    // figure cells sit in an `IntrinsicHeight` row.
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [trend, _suffixText(tail, tokens)],
    );
  }

  Widget _suffixText(String tail, InTheme tokens) => Text(
    tail,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    // `ink2` on the summary cards: `ink3` at this size is under 4:1.
    style: TextStyle(fontSize: 11.5, color: filled ? tokens.ink2 : tokens.ink3),
  );
}
