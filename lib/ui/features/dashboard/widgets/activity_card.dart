import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/activity/activity_timeline.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/activity/activity_deep_link.dart';
import 'package:admin/ui/features/activity/widgets/activity_feed_row.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_panel_grid.dart';
import 'package:admin/ui/features/dashboard/widgets/list_card.dart';
import 'package:admin/utils/formatting.dart';

/// Rows the card shows.
const int kActivityCardRows = 5;

/// "Activity" feed — the five most recent rows, under day headers ("Today",
/// "Yesterday", then the company-formatted date). Each row reads *who did what
/// to which record* — the server's `activity_<N>` template, filled by
/// [ActivityFormatter] — with the values (the actor's name, the record's
/// number) in the strong ink, a tone icon from the `activity_type_id` catalog
/// (`kActivityTones`), and a muted meta line: what the sentence does not
/// already name (the client, else the amount) and how long ago.
///
/// The actor's label is the user's `first_name last_name` as the server joins
/// them (`UserPresenter::name`). On the demo server both halves are seeded
/// with a full fake name (`UserFactory`: `faker->name()` twice), so the actor
/// reads "Carey Feest Danyka Terry" — one person, not an actor and a client
/// run together. The strong weight is what keeps it reading as one name, and
/// the client sits on the meta line, apart from it.
///
/// **The whole row is the one tap target** — no inline link, which a finger
/// cannot hit (`docs/comments-and-activity.md` § An inline link in a sentence
/// cannot be hit by a finger). A row naming no record renders inert.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.section,
    required this.onViewAll,
    required this.onRetry,
    required this.onActivityTap,
    required this.formatter,
  });

  final AsyncSection<List<DashboardActivity>> section;

  /// "View all" footer link tap — the `/activity` screen. **Null hides the
  /// link entirely**, so a host with no destination shows no dead affordance
  /// rather than a "coming soon" snackbar.
  final VoidCallback? onViewAll;
  final VoidCallback onRetry;

  /// Fired when an activity row is tapped. The dashboard resolves the most
  /// specific entity referenced (invoice > quote > payment > recurring >
  /// expense > client) and navigates there. Rows that reference no entity
  /// never fire it — they render inert (no ripple) rather than as a dead tap.
  final void Function(DashboardActivity) onActivityTap;

  /// Formats the day headers older than yesterday, through the company's
  /// `date_format_id`. Required: an ISO date is never shown to the user.
  final Formatter formatter;

  @override
  Widget build(BuildContext context) {
    final state = section.listState;
    final short =
        state == ListSectionState.empty || state == ListSectionState.failed;
    // Beside the chart this card is stretched to the row's height — see
    // `DashboardPanelCell`.
    final centred = short && DashboardPanelCell.stretchedOf(context);
    return DashboardCardShell(
      title: context.tr('activity'),
      trailing: onViewAll == null
          ? null
          : DashboardCardFooterLink(
              label: context.tr('view_all'),
              onTap: onViewAll,
            ),
      // The one-line states bring the panels' own padding; the feed rows and
      // their skeleton use the shell's.
      padding: short ? EdgeInsets.zero : null,
      bodyFills: centred,
      child: centred ? Center(child: _body(context)) : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final dense = dashboardDense(context);
    switch (section.listState) {
      // The same one-line states as every list panel — this card sits beside
      // the chart, which fills whatever height is left over.
      case ListSectionState.failed:
        return DashboardPanelError(onRetry: onRetry);
      case ListSectionState.loading:
        return ActivityFeedSkeleton(
          density: dense
              ? ActivityRowDensity.cardDense
              : ActivityRowDensity.card,
        );
      case ListSectionState.empty:
        return DashboardPanelMessage(title: context.tr('no_activity_yet'));
      case ListSectionState.rows:
        break;
    }
    final activityFormatter = ActivityFormatter(context);
    // As on the Activity screen: an edit made within minutes of creating a
    // record is part of creating it, and five rows are too few to spend two on
    // one act (`absorbCreateEdits`).
    final visible = absorbCreateEdits(
      section.data!,
      targetOf: activityDeepLinkTarget,
    ).rows.take(kActivityCardRows).toList();
    final today = Date.today();
    final children = <Widget>[];
    Date? day;
    for (final a in visible) {
      final rowDay = activityLocalDay(a);
      if (rowDay != day) {
        day = rowDay;
        children.add(
          _DayHeader(
            label: activityDayLabel(context, rowDay, today, formatter),
            first: children.isEmpty,
          ),
        );
      }
      children.add(
        DashboardActivityRow(
          activity: a,
          render: activityFormatter.format(a),
          dense: dense,
          onTap: activityDeepLinkTarget(a) == null
              ? null
              : () => onActivityTap(a),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// The device-local calendar day [a] happened on — the day the user lived it.
Date activityLocalDay(DashboardActivity a) {
  final t = DateTime.fromMillisecondsSinceEpoch(a.createdAt * 1000);
  return Date(t.year, t.month, t.day);
}

/// "Today" / "Yesterday" / the company-formatted date of [day]. Counted in
/// calendar days through `Date`, so a DST change cannot make yesterday today.
String activityDayLabel(
  BuildContext context,
  Date day,
  Date today,
  Formatter formatter,
) {
  final delta = today.differenceInDays(day);
  if (delta == 0) return context.tr('today');
  if (delta == 1) return context.tr('yesterday');
  // `toIso()` only as `Formatter.date`'s input, never as the label.
  return formatter.date(day.toIso());
}

/// What the meta line says ahead of the time: the client (or vendor) when the
/// sentence does not already name it, else the amount when the server sent
/// one the sentence does not show. Null when there is nothing to add.
String? activityRelatedLabel(DashboardActivity a, ActivityRender render) {
  for (final token in const ['client', 'vendor', 'payment_amount']) {
    if (render.tokens.contains(token)) {
      // The sentence names the party already; an amount beside it would be a
      // second subject, not context.
      if (token != 'payment_amount') return null;
      continue;
    }
    final label = a.labels[token]?.trim() ?? '';
    if (label.isNotEmpty) return label;
  }
  return null;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 4,
        end: 4,
        top: first ? 0 : InSpacing.sm,
        bottom: 2,
      ),
      child: Semantics(
        header: true,
        headingLevel: 3,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: tokens.ink3,
          ),
        ),
      ),
    );
  }
}

/// One row of the dashboard's activity card: a tone circle, the sentence with
/// its values set apart, and a muted meta line under it.
///
/// Its own widget rather than [ActivityFeedRow]: the `/activity` timeline and
/// User Details keep that row's one-line sentence-and-time layout and its
/// plain-string title, and neither has a client to put on a meta line.
class DashboardActivityRow extends StatelessWidget {
  const DashboardActivityRow({
    super.key,
    required this.activity,
    required this.render,
    required this.dense,
    this.onTap,
  });

  final DashboardActivity activity;
  final ActivityRender render;

  /// The Compact density: a smaller circle and a one-line sentence.
  final bool dense;

  /// Null → the row names no record and must not look tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final (bg, fg) = activityToneColors(tokens, render.tone);
    final avatar = dense ? 22.0 : 28.0;
    final related = activityRelatedLabel(activity, render);
    final meta = [?related, render.meta].join(' · ');

    final sentence = Text.rich(
      TextSpan(
        children: [
          for (final s in render.segments)
            TextSpan(
              text: s.text,
              style: s.isValue
                  ? TextStyle(color: tokens.ink, fontWeight: FontWeight.w600)
                  : null,
            ),
        ],
      ),
      // A logged call's note is deliberately multi-line, and five unbounded
      // ones grew the card to fill its column; the row opens the record, and
      // the full feed is one tap away.
      maxLines: dense ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, height: 1.35, color: tokens.ink2),
    );

    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 7, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: avatar,
            height: avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(render.icon, size: dense ? 12 : 15, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                sentence,
                const SizedBox(height: 1),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: tokens.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // A row is never under the touch target on a touch device, dense or not.
    final floored = Env.isTouchPrimary
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: InSizes.touchTarget),
            child: row,
          )
        : row;
    final tap = onTap;
    if (tap == null) {
      return Semantics(
        label: '${render.title}, $meta',
        child: ExcludeSemantics(child: floored),
      );
    }
    final tappable = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(InRadii.r2),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) return tokens.border;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return tokens.surfaceAlt;
          }
          return null;
        }),
        child: floored,
      ),
    );
    // `onTap` is re-declared: `ExcludeSemantics` drops the InkWell's own tap
    // action, and a button TalkBack cannot invoke is worse than none
    // (`semantics_excludes_need_ontap_test.dart`).
    return Semantics(
      button: true,
      label: '${render.title}, $meta',
      onTap: tap,
      child: ExcludeSemantics(child: tappable),
    );
  }
}
