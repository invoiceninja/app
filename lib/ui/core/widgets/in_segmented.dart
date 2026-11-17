import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/ui/core/widgets/fill_if_fits.dart';

/// The width each segment gets on a wide row: equal, so the options of every
/// row on a page line up column to column.
const double kInSegmentWidth = 92;

/// The track's inset around the segments.
const double _kTrackPad = 3;

/// One option of an [InSegmented].
class InSegment<T> {
  const InSegment({
    required this.value,
    required this.label,
    this.semanticLabel,
    this.swatch,
    this.icon,
    this.glyph,
  });

  final T value;

  /// The words on the segment. Also what a screen reader says, unless
  /// [semanticLabel] is given.
  final String label;

  /// What a screen reader says instead of [label] — for a segment whose face
  /// is a [glyph] rather than words.
  final String? semanticLabel;

  /// A colour dot drawn before the label, ringed with `borderStrong` so a
  /// white or near-black swatch still reads against the track.
  final Color? swatch;

  /// An icon drawn before the label.
  final IconData? icon;

  /// Replaces the label on the segment's face — the font-size row's "A"s.
  /// [label] is still the segment's name for a screen reader (via
  /// [semanticLabel] when set).
  final Widget? glyph;
}

/// Tells every [InSegmented] below it to fill the line it is given instead of
/// taking [kInSegmentWidth] a segment — published by a narrow `SettingRow`
/// around the control it stacks under its text.
class InSegmentedFill extends InheritedWidget {
  const InSegmentedFill({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InSegmentedFill>() != null;

  @override
  bool updateShouldNotify(InSegmentedFill oldWidget) => false;
}

/// The app's segmented picker: a `surfaceAlt` track holding the options, the
/// chosen one raised on a `surface` face in `ink` at weight 600. A restyled
/// [SegmentedButton], so focus, arrow keys, hover and the selected state a
/// screen reader announces all come from the framework.
///
/// Segments are equal and [segmentWidth] wide on a wide row; under an
/// [InSegmentedFill] (a narrow row) they share the line between them. Either
/// way a set of labels too long for the space keeps its natural width rather
/// than ellipsising — the row around it scrolls.
///
/// 46 px tall on a touch platform (`Env.isTouchPrimary`), 38 with a pointer. Rounded
/// rectangles throughout: `r2` for the track, `r1` for a face — never a pill.
class InSegmented<T> extends StatelessWidget {
  const InSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.segmentWidth = kInSegmentWidth,
  });

  final List<InSegment<T>> segments;
  final T selected;

  /// Null disables every segment.
  final ValueChanged<T>? onChanged;

  final double segmentWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final fill = InSegmentedFill.of(context);
    final touch = Env.isTouchPrimary;
    // A segment is a `TextButton`, whose 40 px minimum `SegmentedButton`
    // does not let a style lower — only a density can. Standard on touch
    // (40 + the track's 2 × 3 = 46, over the 44 floor), compact with a
    // pointer (32 + 6 = 38). The face fills the segment either way.
    final density = touch ? VisualDensity.standard : VisualDensity.compact;
    final faceHeight = 40 + density.baseSizeAdjustment.dy;
    final button = SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final s in segments)
          ButtonSegment<T>(
            value: s.value,
            label: _SegmentFace(
              segment: s,
              selected: s.value == selected,
              enabled: onChanged != null,
              height: faceHeight,
            ),
          ),
      ],
      selected: {selected},
      onSelectionChanged: onChanged == null
          ? null
          : (values) => onChanged!(values.first),
      style: ButtonStyle(
        // The face draws the selection; the segment itself stays clear so
        // its square inner corners never show.
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? tokens.ink4
              : states.contains(WidgetState.selected)
              ? tokens.ink
              : tokens.ink2,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return tokens.ink.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return tokens.accent.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return tokens.ink.withValues(alpha: 0.04);
          }
          return null;
        }),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(InRadii.r1)),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        // Pinned: the touch theme's `padded` tap target would pad a segment
        // out to 48 under the track, and the theme's own density is not ours
        // to inherit (docs/touch-targets.md, traps 2 and 3).
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: density,
      ),
    );
    final track = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kTrackPad),
        child: fill
            ? button
            // Equal segments: a tight width is shared equally among them. A
            // translation too long for it keeps its natural width.
            : FillIfFits(width: segmentWidth * segments.length, child: button),
      ),
    );
    return track;
  }
}

class _SegmentFace extends StatelessWidget {
  const _SegmentFace({
    required this.segment,
    required this.selected,
    required this.enabled,
    required this.height,
  });

  final InSegment<dynamic> segment;
  final bool selected;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final color = !enabled
        ? tokens.ink4
        : selected
        ? tokens.ink
        : tokens.ink2;
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    final swatch = segment.swatch;
    final icon = segment.icon;
    final glyph = segment.glyph;
    final Widget face = glyph != null
        ? Semantics(
            label: segment.semanticLabel ?? segment.label,
            excludeSemantics: true,
            child: DefaultTextStyle.merge(style: style, child: glyph),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (swatch != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.borderStrong),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  semanticsLabel: segment.semanticLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          );
    return Container(
      constraints: BoxConstraints(minHeight: height),
      // 1 px a side: the 2 px gap between neighbouring faces.
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: selected
          ? BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(InRadii.r1),
              boxShadow: [
                BoxShadow(
                  color: tokens.ink.withValues(alpha: 0.14),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            )
          : null,
      child: face,
    );
  }
}
