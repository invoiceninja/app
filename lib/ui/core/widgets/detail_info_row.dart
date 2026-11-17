import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/link_text.dart';

/// One row inside an entity detail card: a small ink3 label in a fixed-width
/// column on the left, value left-aligned right next to it. Keeps values close
/// to their labels so short fields (phone, country, price) don't leave a big
/// gap on the right edge.
///
/// Entity-agnostic — used by client, product, invoice, …  detail cards.
class DetailInfoRow extends StatelessWidget {
  const DetailInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
    this.valueColor,
    this.onTap,
    this.copyable = true,
    this.copyText,
    this.trailing,
    this.semanticsLabel,
    this.tooltip,
    this.child,
  });

  /// A widget to draw in place of [value] — a name resolved from an id
  /// (`UserNameLabel`), say, which is a stream and cannot be a string. It gets
  /// the row's label and alignment and nothing else: no copy affordance and no
  /// link treatment, since the row does not know what the widget shows. Pass
  /// [value] as `''` alongside it.
  final Widget? child;

  final String label;
  final String value;

  /// Renders the value with tabular figures so money columns align.
  final bool monospace;

  /// Override the default value color (used to dim zero amounts).
  final Color? valueColor;

  /// When non-null the value renders as a clickable link (accent color,
  /// hover underline) that invokes [onTap].
  final VoidCallback? onTap;

  /// Whether the value gets a copy affordance (hover icon on desktop/web,
  /// tap-to-copy on mobile). On by default; set false for values that aren't
  /// worth copying — resolved enum/display names ("US Dollar", "Yes"),
  /// composites, or formatted dates.
  final bool copyable;

  /// The exact string copied when [copyable]. Defaults to [value]; override
  /// when the displayed text differs from what's useful to copy.
  final String? copyText;

  /// A small annotation rendered immediately after the value, *inside* the
  /// copy wrapper — so the desktop hover-copy icon keeps its own trailing
  /// column and [copyText] stays the bare value. Meant for dimmed context
  /// (the callee's local time beside a phone number), not for a button: a
  /// touch-sized control here would drive the row's cross axis and stack on
  /// top of its padding (see CLAUDE.md § Design system, trap 4).
  final Widget? trailing;

  /// Announces the row's value as an actionable button to a screen reader.
  /// [LinkText] emits no semantics of its own, so without this a tappable
  /// value is read out as plain text with no hint that it does anything.
  final String? semanticsLabel;

  /// Hover hint naming what [onTap] does. Pointer platforms only — pass null
  /// on touch, where there is no hover and the tooltip only fires on a
  /// long-press that is usually already taken by copy.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: valueColor ?? tokens.ink,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      fontFeatures: monospace ? const [FontFeature.tabularFigures()] : null,
    );
    Widget display =
        child ??
        (onTap == null
            ? Text(value, style: valueStyle)
            // `accentInk`, never `accent`: the accent is the user's own
            // colour and is the same mid tone in both brightnesses, which on
            // a dark surface falls under the contrast floor. And an underline
            // at rest where there is no hover to reveal one — a finger cannot
            // discover a link by pointing at it. Both per
            // `docs/row-actions-and-values.md`, which this row predated.
            // One line, ellipsized: a link value is an address (a website,
            // an email), and a URL wrapped over three lines of a 400 px
            // rail. The whole value is still what is copied and opened.
            : LinkText(
                label: value,
                style: valueStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: tokens.accentInk,
                underlineAtRest: linkNeedsAtRestCue,
                onTap: onTap,
              ));
    if (tooltip != null) {
      display = Tooltip(message: tooltip!, child: display);
    }
    if (semanticsLabel != null) {
      // `excludeSemantics` so the child's own text node doesn't merge in and
      // announce the value twice — which also drops the descendant's
      // `SemanticsAction.tap`, so `onTap` has to be re-declared here or the
      // node is a button with no `ACTION_CLICK` for TalkBack / switch access
      // to invoke.
      display = Semantics(
        button: true,
        label: semanticsLabel,
        onTap: onTap,
        excludeSemantics: true,
        child: display,
      );
    }
    if (trailing != null) {
      display = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: display),
          trailing!,
        ],
      );
    }
    // Copy affordance: hover icon (desktop/web) or tap-to-copy (mobile). A row
    // with its own onTap (e.g. a website launch) keeps tap for that action and
    // exposes copy via the hover icon / a mobile long-press instead.
    final Widget valueWidget = copyable && value.isNotEmpty
        ? CopyableValue(
            value: copyText ?? value,
            enableTapToCopy: onTap == null,
            enableLongPressToCopy: onTap != null,
            child: display,
          )
        : display;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: detailInfoRowPadding(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              // `ink2`: the label is the field's name, and `ink3` at this size
              // is 3.98:1 on a card in the default light theme — under the
              // 4.5:1 floor. The tab strip made the same call for the same
              // reason.
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.ink2,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: InSpacing.sm),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

/// A [DetailInfoRow]'s padding above and below its text.
///
/// Tighter with a pointer, and tighter again under the Compact density: a
/// card of eight facts ran 33 px a row, and with a mouse the row is only a
/// copy-on-hover target. **Touch keeps 7 at every density** — there the row is
/// a tap-to-copy target already under 44 px, and trimming it would trade a
/// touch target for a few pixels (`docs/detail-screen-layout.md` § The phone
/// record layout).
double detailInfoRowPadding(BuildContext context) {
  if (Env.isTouchPrimary) return 7;
  return ListDensityScope.isCompactOf(context) ? 3 : 5;
}

/// The space between rows in a detail card. It was a hairline rule under
/// every row, which made a card of six facts read as a table of six; the
/// rows' own padding now carries the rhythm, as in the record designs.
class DetailRowDivider extends StatelessWidget {
  const DetailRowDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 2);
}

/// Stacks a list of [DetailInfoRow]s with [DetailRowDivider]s between them,
/// dropping any null entries (so callers can write
/// `if (foo.isEmpty) null else DetailInfoRow(...)`).
class DetailRowStack extends StatelessWidget {
  const DetailRowStack({super.key, required this.children});

  final List<Widget?> children;

  @override
  Widget build(BuildContext context) {
    final rows = children.whereType<Widget>().toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const DetailRowDivider());
      out.add(rows[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: out,
    );
  }
}
