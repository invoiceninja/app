import 'package:material_ui/material_ui.dart';

/// Whether [text] needs more than [maxLines] lines at [maxWidth] in [style] —
/// the one measurement behind every "show the rest on hover" in the app.
bool textOverflows(
  BuildContext context, {
  required String text,
  required TextStyle? style,
  required double maxWidth,
  int maxLines = 1,
}) {
  if (text.isEmpty || !maxWidth.isFinite) return false;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    maxLines: maxLines,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth <= 0 ? 0 : maxWidth);
  final overflows = painter.didExceedMaxLines;
  painter.dispose();
  return overflows;
}

/// A name held to [maxLines] that says the rest in a tooltip — on hover with
/// a mouse, on a long press with a finger — and only when it was actually cut
/// off, so a name that fits never grows a tooltip repeating it.
///
/// For a value the user has to recognise at a glance (a product key in a
/// picker): beta feedback was that a long item name could not be told from
/// its neighbours without opening the record.
///
/// Measured through a `LayoutBuilder`, so not for a subtree whose parent asks
/// for intrinsic dimensions.
class OverflowTooltipText extends StatelessWidget {
  const OverflowTooltipText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle? style;

  /// Null shows the whole text, and so never a tooltip.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final lines = maxLines;
    final label = Text(
      text,
      style: style,
      maxLines: lines,
      overflow: lines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
    if (lines == null) return label;
    return LayoutBuilder(
      builder: (context, constraints) =>
          textOverflows(
            context,
            text: text,
            style: style,
            maxWidth: constraints.maxWidth,
            maxLines: lines,
          )
          ? Tooltip(message: text, child: label)
          : label,
    );
  }
}
