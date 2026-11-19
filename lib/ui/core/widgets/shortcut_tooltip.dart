import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/key_cap.dart';

/// Wraps [child] in a Material [Tooltip] whose message shows [label] plus the
/// keyboard shortcut rendered as [KeyCap] chips — so hovering a button
/// reveals how to trigger it from the keyboard.
///
/// [keys] are display glyphs: `['N']`, `[platformModifierLabel(), 'K']`
/// (⌘ K), etc. Set [sequence] `true` for a leader sequence (`G` then `C`),
/// which inserts a localized "then" between the caps instead of a bare gap.
///
/// The label rides the tooltip's own text style (so it stays legible on the
/// tooltip background in both themes); the caps are self-styled chips.
class ShortcutTooltip extends StatelessWidget {
  const ShortcutTooltip({
    super.key,
    required this.label,
    required this.keys,
    this.sequence = false,
    this.waitDuration,
    this.triggerMode,
    this.positionDelegate,
    required this.child,
  });

  final String label;
  final List<String> keys;
  final bool sequence;

  /// Hover delay before the tooltip appears. Null takes the theme's
  /// `InTooltip.labelDelay` — right for an icon-only control, whose tooltip is
  /// its only label. Pass `InTooltip.hintDelay` when [child] already shows
  /// [label], so the tooltip only adds the shortcut (`docs/tooltip-delays.md`).
  final Duration? waitDuration;

  /// How a *touch* opens the tooltip. Null keeps Material's default
  /// (`longPress`); pass [TooltipTriggerMode.manual] when an ancestor owns the
  /// long press.
  ///
  /// This is not cosmetic. On the default, `RawTooltip` registers a
  /// `LongPressGestureRecognizer` from a `Listener` *below* this widget, so it
  /// enters the gesture arena ahead of any `onLongPressStart` wrapped around
  /// the outside and wins the same 500 ms deadline — silently swallowing that
  /// ancestor's long press. Hover is unaffected either way: trigger mode
  /// "does not affect mouse devices", which reach the tooltip through a
  /// `MouseRegion` rather than the arena.
  final TooltipTriggerMode? triggerMode;

  /// Where the tooltip goes; null is Material's above / below. A row in a
  /// vertical stack passes [tooltipBesideTarget], so the tooltip never lands
  /// on the next row.
  final TooltipPositionDelegate? positionDelegate;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final separator = sequence ? ' ${context.tr('then')} ' : ' ';
    return Tooltip(
      waitDuration: waitDuration,
      triggerMode: triggerMode,
      positionDelegate: positionDelegate,
      // A `richMessage` tooltip takes the pointer by default (Material only
      // defaults `ignorePointer` on for a plain `message`), so a tooltip drawn
      // over a neighbouring control stayed open under the pointer and hid
      // that control from hover and click.
      ignorePointer: true,
      richMessage: TextSpan(
        children: [
          TextSpan(text: '$label   '),
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) TextSpan(text: separator),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: KeyCap(label: keys[i]),
            ),
          ],
        ],
      ),
      child: child,
    );
  }
}

/// Places a tooltip beside its target, vertically centred on it, on the
/// target's end side ([direction]) — the start side when the end has no room,
/// Material's above / below when neither does.
///
/// For a control in a vertical stack (a sidebar row), where above or below
/// covers the neighbouring row the pointer is about to move to.
TooltipPositionDelegate tooltipBesideTarget(
  TextDirection direction, {
  double gap = 8,
}) {
  return (TooltipPositionContext c) {
    // rtl: physical — the overlay positions in global coordinates; the
    // reading direction only picks which side is tried first.
    final halfWidth = c.targetSize.width / 2;
    final right = c.target.dx + halfWidth + gap;
    final left = c.target.dx - halfWidth - gap - c.tooltipSize.width;
    final fitsRight = right + c.tooltipSize.width <= c.overlaySize.width;
    final fitsLeft = left >= 0;
    final double? x = direction == TextDirection.ltr
        ? (fitsRight ? right : (fitsLeft ? left : null))
        : (fitsLeft ? left : (fitsRight ? right : null));
    if (x == null) {
      return positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: c.verticalOffset,
        preferBelow: c.preferBelow,
      );
    }
    final maxY = math.max(0.0, c.overlaySize.height - c.tooltipSize.height);
    final y = (c.target.dy - c.tooltipSize.height / 2).clamp(0.0, maxY);
    return Offset(x, y);
  };
}
