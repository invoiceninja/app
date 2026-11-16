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
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.percent,
    required this.goodDirection,
    this.suffix,
  });

  /// Signed percent. Positive = `up`, negative = `down`.
  final double? percent;

  final GoodDirection goodDirection;

  /// Optional trailing text (e.g. "vs prior"). Renders in `ink3`.
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final p = percent;
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
    final tail = suffix;
    if (tail == null) return trend;
    // A `Wrap`, so a suffix the cell has no room for ("vs $9,286.00" in a
    // third of a phone's width, or at a large text size) drops to a line of
    // its own instead of overflowing. Not a `LayoutBuilder`: the dashboard's
    // figure cells sit in an `IntrinsicHeight` row.
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        trend,
        Text(
          tail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: tokens.ink3),
        ),
      ],
    );
  }
}
