import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/domain/activity/activity_ip.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';
import 'package:admin/utils/formatting.dart';

/// Row width from which a full-page [ActivityFeedRow] is one line: the
/// sentence, then its meta at the row's end, with the time in a leading
/// column. Measured on the row itself — the pane, never the window: the
/// sidebar and the `/activity` filter rail take their share of a desktop
/// window, and a 1024 px window left the old window-width gate drawing one
/// line in a 500 px feed.
const double kActivityRowInlineMinWidth = 600;

/// The leading time column's width at 1× text, wide enough for "12:59 PM" at
/// 12 px with tabular figures.
const double _kTimeColumnWidth = 64;

/// The audit-lens `meta` line for [ActivityFeedRow]: an absolute,
/// company-formatted local timestamp joined with the originating IP.
///
/// `Formatter.date` suffixes a missing `Z` and calls `.toLocal()` itself, so
/// the UTC epoch the server sends is what must go in — hence `isUtc: true`.
/// Falls back to the relative [ActivityRender.meta] until the company
/// `Formatter` has loaded, and note the IP is only in the raw payload
/// (`DashboardActivity` doesn't destructure it). A loopback IP — what the
/// server stamps on every background job's activity — is left out
/// (`displayableActivityIp`).
///
/// [note] sits between the time and the IP: what the row stands for beyond
/// its own sentence ("also updated", for edits folded into a create).
///
/// [showDate] false drops the date and keeps the time — for a row already
/// sitting under a day header that names the date. [showTime] false drops the
/// time too, for a row that passes it as [ActivityFeedRow.time]; until the
/// `Formatter` loads the relative time stands in for both.
String activityAuditMeta(
  DashboardActivity a, {
  required ActivityRender render,
  required Formatter? formatter,
  bool showDate = true,
  bool showTime = true,
  String? note,
}) {
  final String? when;
  if (formatter == null) {
    when = render.meta;
  } else if (!showDate && !showTime) {
    when = null;
  } else {
    when = formatter.date(
      _utcIso(a),
      showDate: showDate,
      showTime: true,
      showSeconds: false,
    );
  }
  // A background job's activity carries the loopback address — dropped.
  final ip = displayableActivityIp(a.raw['ip']?.toString());
  return [
    ?when,
    if (note != null && note.isNotEmpty) note,
    if (ip.isNotEmpty) ip,
  ].join(' · ');
}

/// The local time of day [a] happened at, in the company's time format — the
/// `/activity` row's leading time column.
String activityTimeLabel(DashboardActivity a, Formatter formatter) => formatter
    .date(_utcIso(a), showDate: false, showTime: true, showSeconds: false);

String _utcIso(DashboardActivity a) => DateTime.fromMillisecondsSinceEpoch(
  a.createdAt * 1000,
  isUtc: true,
).toIso8601String();

/// Visual weight of an [ActivityFeedRow].
enum ActivityRowDensity {
  /// The dashboard card's compact row — 26 px circle, 12.5/11 px text.
  card,

  /// [card] under the Compact density preference (`docs/list-density.md`
  /// § The dashboard): a 22 px circle, 4 px vertical padding and a one-line
  /// title. The row deep-links to the record and the full feed is one tap
  /// away, so the clamp costs nothing that cannot be reached.
  cardDense,

  /// Full-page / detail-section row — 28 px rounded square, body text styles.
  page,
}

/// One rendered activity line, shared by the `/activity` screen and the
/// per-user activity section on User Details (the dashboard card draws its
/// own `DashboardActivityRow`, and these card densities its skeleton).
///
/// **The sentence reads like the dashboard card's**: the template's words in
/// the secondary ink and the values it filled in (the actor, the record's
/// number, the client) in the strong weight, from [ActivityRender.segments] —
/// so a four-word name still reads as one name.
///
/// **One line where the row has room** ([kActivityRowInlineMinWidth], measured
/// on the row): the [time] in a fixed leading column, the sentence, then
/// [meta] muted at the end. Narrower, the sentence wraps and the time and
/// meta go on a line under it.
///
/// [meta] is supplied by the caller rather than derived here because the
/// surfaces answer different questions with it: the audit lenses show an
/// absolute company-formatted timestamp joined with the originating IP.
///
/// **A row with no [onTap] renders inert** — no ripple, no chevron, no `button`
/// semantics. `activityDeepLinkTarget` returns null for system-only rows that
/// reference no entity, and dressing those as tappable was tolerable across the
/// card's five rows but is a screenful of dead taps on the full feed.
class ActivityFeedRow extends StatelessWidget {
  const ActivityFeedRow({
    super.key,
    required this.render,
    required this.meta,
    this.time,
    this.density = ActivityRowDensity.page,
    this.onTap,
  });

  final ActivityRender render;
  final String meta;

  /// The time of day, for a row under a day header: a leading column of its
  /// own on a one-line row, the head of the meta line otherwise. Null → the
  /// time, if any, is part of [meta].
  final String? time;

  final ActivityRowDensity density;

  /// Null → the row is not a navigation target and must not look like one.
  final VoidCallback? onTap;

  bool get _isCard => density != ActivityRowDensity.page;
  bool get _isDense => density == ActivityRowDensity.cardDense;

  @override
  Widget build(BuildContext context) {
    // The card densities are one line by construction and never measured:
    // a card can sit in an `IntrinsicHeight` row, where a `LayoutBuilder`
    // throws.
    if (_isCard) return _build(context, inline: true);
    return LayoutBuilder(
      builder: (context, c) =>
          _build(context, inline: c.maxWidth >= kActivityRowInlineMinWidth),
    );
  }

  Widget _build(BuildContext context, {required bool inline}) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final (bg, fg) = activityToneColors(tokens, render.tone);

    final avatarSize = _isDense ? 22.0 : (_isCard ? 26.0 : 28.0);
    final time = this.time;
    final timeColumn = inline && time != null && !_isCard;
    // Narrow, the time leads the meta line instead.
    final metaText = timeColumn
        ? meta
        : [?time, if (meta.isNotEmpty) meta].join(' · ');

    final baseStyle = _isCard
        ? TextStyle(fontSize: 12.5, color: tokens.ink, height: 1.35)
        : theme.textTheme.bodyMedium?.copyWith(color: tokens.ink2);
    final sentence = Text.rich(
      TextSpan(
        children: render.segments.isEmpty
            ? [TextSpan(text: render.title)]
            : [
                for (final s in render.segments)
                  TextSpan(
                    text: s.text,
                    style: s.isValue
                        ? TextStyle(
                            color: tokens.ink,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
              ],
      ),
      // The dashboard card only. A logged call's note is deliberately
      // multi-line (a metadata header, then what was said), and five
      // unbounded ones grew the card to fill its column. The full-page feed
      // and the User Details audit section stay unclamped on purpose: a typed
      // comment can run to six lines (`add_comment_dialog.dart`), the row's
      // tap deep-links to the *entity* rather than to the note, and there is
      // no other place on those screens to read the rest.
      maxLines: _isDense ? 1 : (_isCard ? 2 : null),
      overflow: _isCard ? TextOverflow.ellipsis : null,
      style: baseStyle,
    );
    final metaStyle = _isCard
        ? TextStyle(fontSize: 11, color: tokens.ink3)
        : theme.textTheme.bodySmall?.copyWith(color: tokens.ink3);
    final metaLine = Text(metaText, style: metaStyle);

    final padded = Padding(
      padding: _isCard
          ? EdgeInsets.symmetric(vertical: _isDense ? 4 : 10, horizontal: 4)
          : const EdgeInsets.symmetric(vertical: InSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timeColumn)
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(_kTimeColumnWidth),
              child: Padding(
                // Onto the sentence's first line: 12 px type beside 14 px.
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: LtrText(
                  time,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: metaStyle?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          Container(
            width: avatarSize,
            height: avatarSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: _isCard ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: _isCard ? null : BorderRadius.circular(InRadii.r2),
            ),
            child: Icon(
              render.icon,
              size: _isDense ? 12 : (_isCard ? 14 : 16),
              color: fg,
            ),
          ),
          SizedBox(width: _isCard ? 10 : InSpacing.md(context)),
          Expanded(
            child: inline
                // One line: the sentence, then the meta at the row's end,
                // muted. Two lines a row made the feed twice as long as the
                // events in it.
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: sentence),
                      if (metaText.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: _isCard ? 0 : 2,
                          ),
                          child: metaLine,
                        ),
                      ],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      sentence,
                      if (metaText.isNotEmpty) ...[
                        if (!_isCard) const SizedBox(height: 2),
                        metaLine,
                      ],
                    ],
                  ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: _isCard ? 14 : 16,
              color: tokens.ink3,
            ),
          ],
        ],
      ),
    );
    // The dense card row is ~42 px with 4 px padding; on touch it keeps the
    // 44 px target.
    final content = _isDense && Env.isTouchPrimary
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: InSizes.touchTarget),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              heightFactor: 1,
              child: padded,
            ),
          )
        : padded;

    final label = [render.title, ?time, if (meta.isNotEmpty) meta].join(', ');
    if (onTap == null) {
      return Semantics(
        label: label,
        child: ExcludeSemantics(child: content),
      );
    }

    final tappable = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(InRadii.r1),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) return tokens.border;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return tokens.surfaceAlt;
          }
          return null;
        }),
        child: content,
      ),
    );
    // `onTap` is **re-declared**: `ExcludeSemantics` drops the whole subtree,
    // and the tap action lives on `InkResponse`'s own `Semantics(onTap:)` —
    // which does not set `button`, so the two halves of an activatable button
    // come from different nodes. Without this the row announces as a button
    // that TalkBack and switch access cannot invoke. Same rule as `linkOrText`
    // and the task-calendar cell; `semantics_excludes_need_ontap_test.dart`
    // pins it.
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(child: tappable),
    );
  }
}

/// Placeholder rows shown while the activity cache is still empty. Shared so
/// the card and the full feed agree on what "loading" looks like.
class ActivityFeedSkeleton extends StatelessWidget {
  const ActivityFeedSkeleton({
    super.key,
    this.count = 5,
    this.density = ActivityRowDensity.card,
  });

  final int count;
  final ActivityRowDensity density;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final isCard = density != ActivityRowDensity.page;
    final isDense = density == ActivityRowDensity.cardDense;
    final avatarSize = isDense ? 22.0 : (isCard ? 26.0 : 28.0);
    return Column(
      children: List.generate(count, (i) {
        return Padding(
          padding: EdgeInsets.symmetric(vertical: isDense ? 4 : 10),
          child: Row(
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: tokens.surfaceAlt,
                  shape: isCard ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: isCard
                      ? null
                      : BorderRadius.circular(InRadii.r2),
                ),
              ),
              SizedBox(width: isCard ? 10 : InSpacing.md(context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 180,
                      height: 12,
                      decoration: BoxDecoration(
                        color: tokens.surfaceAlt,
                        borderRadius: BorderRadius.circular(InRadii.r1),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: tokens.surfaceAlt,
                        borderRadius: BorderRadius.circular(InRadii.r1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
