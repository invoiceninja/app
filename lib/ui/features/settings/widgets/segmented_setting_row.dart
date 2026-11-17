import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/fill_if_fits.dart';

// Width of the SizedBox we wrap every segment label in. Pins each segment's
// intrinsic width so the buttons line up across rows.
const double _kSegmentLabelWidth = 80;

// Below this row width a ~320px multi-segment SegmentedButton no longer fits in
// a ListTile's trailing slot — `_RenderListTile` throws "Trailing widget
// consumes the entire tile width". [SegmentedSettingRow] stacks the button on
// its own row under that width instead.
const double _kWideRowThreshold = 520;

/// A fixed-width, centered, single-line segment label so segmented buttons line
/// up column-to-column across settings rows. Shared by the theme rows and the
/// font-size row on Device Settings.
///
/// Under a narrow [SegmentedSettingRow] the label drops the fixed width and
/// takes its natural one, so the row can tell whether the segments fit the
/// card and, when they do, stretch them across it.
Widget segmentLabel(BuildContext context, String key) => _SegmentLabel(key);

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.labelKey);

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      context.tr(labelKey),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    if (_SegmentFillScope.of(context)) return text;
    return SizedBox(
      width: _kSegmentLabelWidth,
      child: Center(child: text),
    );
  }
}

/// Marks a narrow row's control: its [segmentLabel]s go natural-width.
class _SegmentFillScope extends InheritedWidget {
  const _SegmentFillScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SegmentFillScope>() != null;

  @override
  bool updateShouldNotify(_SegmentFillScope oldWidget) => false;
}

/// A settings row with a leading icon, a title + subtitle, and a wide
/// [SegmentedButton] control.
///
/// On a window at least [_kWideRowThreshold] wide the control sits in the
/// `ListTile.trailing` slot (the compact, right-aligned look). Below that width
/// the button overflows the tile — `_RenderListTile` throws "Trailing widget
/// consumes the entire tile width" — so the control drops to its own full-width
/// row beneath the title, with a horizontal-scroll guard for sub-320px widths.
class SegmentedSettingRow extends StatelessWidget {
  const SegmentedSettingRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.control,
    this.scrollableTrailing = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget control;

  /// Set when [control] can grow past the trailing slot — a natural-width
  /// [SegmentedButton] (e.g. the font-size row's "Small / … / Extra Large"),
  /// which at a large text scale would otherwise trip `_RenderListTile`'s
  /// "Trailing widget consumes the entire tile width" assert. The wide layout
  /// then caps + horizontally scrolls the control; the narrow layout already
  /// scrolls. Fixed-width rows (the theme mode/palette rows whose 80px labels
  /// ellipsise) leave this off.
  final bool scrollableTrailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _kWideRowThreshold) {
          return ListTile(
            leading: leading,
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: scrollableTrailing
                // Cap the control at ~60% of the row and let it scroll
                // horizontally so a wide/large-scale button can't starve the
                // title (which throws inside `_RenderListTile`). `reverse`
                // keeps the trailing edge — the selected segment side — visible.
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.6,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: control,
                    ),
                  )
                : control,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: leading,
              title: Text(title),
              subtitle: Text(subtitle),
            ),
            Padding(
              // Match ListTile's default 16px horizontal content inset so the
              // control lines up with the tile edges. Segments that fit are
              // stretched across the card (a phone's segments were a short
              // strip, or clipped "Dark" / "Paper" at fixed 80 px labels);
              // the horizontal scroll stays for rows that still don't fit.
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LayoutBuilder(
                builder: (context, inner) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: FillIfFits(
                    width: inner.maxWidth,
                    child: _SegmentFillScope(child: control),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
