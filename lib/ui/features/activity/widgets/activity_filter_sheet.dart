import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/user.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/data/static/activity_types_catalog.dart';
import 'package:admin/domain/activity/activity_record_types.dart';
import 'package:admin/domain/activity/activity_timeline.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/multi_entity_picker.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/activity/view_models/activity_view_model.dart';
import 'package:admin/ui/features/activity/widgets/activity_period_labels.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';
import 'package:admin/ui/features/dashboard/widgets/filters/date_range_picker_button.dart';
import 'package:admin/utils/formatting.dart';

/// One activity-type option for the multi-select.
typedef ActivityTypeOption = ({String id, String name});

/// Localized, name-sorted activity-type options. Built the same way the
/// Activity report's filter builds them (`report_filters.dart`), but rendered
/// through the public [MultiEntityPicker] rather than that file's private
/// `_MultiEntityField`.
List<ActivityTypeOption> activityTypeOptions(BuildContext context) => [
  for (final e in kActivityTypeLabelKeys.entries)
    (id: '${e.key}', name: context.tr(e.value)),
]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// The label a category chip and its header chip read.
String activityCategoryLabel(BuildContext context, ActivityCategory c) =>
    switch (c) {
      ActivityCategory.sent => context.tr('sent'),
      ActivityCategory.viewed => context.tr('viewed'),
      ActivityCategory.paid => context.tr('activity_category_paid'),
      ActivityCategory.edited => context.tr('activity_category_edited'),
      ActivityCategory.expense => context.tr('expenses'),
      ActivityCategory.comment => context.tr('comments'),
      ActivityCategory.other => context.tr('other'),
    };

/// The glyph a category chip wears — the row icon of the rows it keeps, so
/// the chip and its rows read as one thing. Comments get the speech bubble
/// rather than the neutral circle they share with "other" in the feed.
IconData activityCategoryIcon(ActivityCategory c) =>
    c == ActivityCategory.comment
    ? Icons.chat_bubble_outline
    : activityIconFor(toneForCategory(c));

/// Opens the activity filter surface: a centered dialog on wide viewports, a
/// scroll-controlled bottom sheet on narrow ones — the same split
/// `openManageDashboardCards` uses, so the two read as one family. A pane wide
/// enough for the side rail never opens this: the rail *is* the same panel.
///
/// [showCategories] false leaves the category chips out, for a screen that
/// draws them under its chart.
///
/// Mutations apply live against [vm]; there is no Save gate.
Future<void> openActivityFilters(
  BuildContext context, {
  required ActivityViewModel vm,
  required String companyId,
  Formatter? formatter,
  bool showCategories = true,
}) {
  final body = ActivityFilterPanel(
    vm: vm,
    companyId: companyId,
    formatter: formatter,
    showCategories: showCategories,
  );
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The user picker is a real text field, and `showModalBottomSheet` lifts
    // nothing by itself. Padding first also makes the 0.92 fraction measure
    // against the keyboard-reduced box rather than the whole screen — otherwise
    // the sheet keeps its full height and simply hides behind the keyboard.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: FractionallySizedBox(heightFactor: 0.92, child: body),
    ),
  );
}

/// The activity filters: date range, category, user, source (the lens),
/// record type and activity type.
///
/// One widget, two hosts — the sheet / dialog from [openActivityFilters], and
/// (with [inline]) the side rail a wide `/activity` pane shows instead of a
/// filter button. Inline drops the close button and the safe-area inset (the
/// rail sits inside the screen's own `Scaffold`).
class ActivityFilterPanel extends StatefulWidget {
  const ActivityFilterPanel({
    super.key,
    required this.vm,
    required this.companyId,
    this.formatter,
    this.inline = false,
    this.showCategories = true,
  });

  final ActivityViewModel vm;
  final String companyId;
  final Formatter? formatter;
  final bool inline;

  /// False where the screen draws the category chips under its chart (a pane
  /// ≥ 600 px wide showing it): the chips redraw the bars, so that is where
  /// they belong, and a second copy here would be two controls for one state.
  final bool showCategories;

  @override
  State<ActivityFilterPanel> createState() => _ActivityFilterPanelState();
}

class _ActivityFilterPanelState extends State<ActivityFilterPanel> {
  // Hoisted out of `build`: the inline rail rebuilds on every keystroke in
  // the search box, and a watch stream opened per build re-queries the roster
  // each time.
  late final Stream<List<User>> _users = context
      .read<Services>()
      .user
      .watchAllForPicker(companyId: widget.companyId);

  ActivityViewModel get vm => widget.vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeOptions = activityTypeOptions(context);

    final panel = Padding(
      padding: EdgeInsets.all(InSpacing.lg(context)),
      child: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final f = vm.filters;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      headingLevel: widget.inline ? 2 : 1,
                      child: Text(
                        context.tr('filters'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (!widget.inline)
                    IconButton(
                      icon: const Icon(Icons.close),
                      iconSize: 20,
                      tooltip: context.tr('close'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              SizedBox(height: InSpacing.md(context)),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DateRangeRow(vm: vm, formatter: widget.formatter),
                      SizedBox(height: InSpacing.lg(context)),
                      if (widget.showCategories) ...[
                        ActivityCategoryChips(vm: vm),
                        SizedBox(height: InSpacing.lg(context)),
                      ],
                      StreamBuilder<List<User>>(
                        stream: _users,
                        builder: (context, snap) {
                          final users = (snap.data ?? const <User>[]).toList()
                            ..sort(
                              (a, b) => a.displayName.toLowerCase().compareTo(
                                b.displayName.toLowerCase(),
                              ),
                            );
                          User? selected;
                          for (final u in users) {
                            if (u.id == f.userId) {
                              selected = u;
                              break;
                            }
                          }
                          return SearchableDropdownField<User>(
                            label: context.tr('user'),
                            // No user picked is everyone's activity.
                            hintText: context.tr('all'),
                            items: users,
                            initialValue: selected,
                            displayString: (u) => u.displayName,
                            idOf: (u) => u.id,
                            // "No records" only once the roster has answered;
                            // before that the field says it is loading.
                            emptyHintKey: snap.hasData
                                ? 'no_records_found'
                                : null,
                            onChanged: (u) => vm.setUser(u?.id),
                          );
                        },
                      ),
                      SizedBox(height: InSpacing.lg(context)),
                      _SectionLabel(context.tr('source')),
                      const SizedBox(height: InSpacing.xs),
                      // The human-written lens subsumes the type filter, so
                      // it sits above it and visibly disables it — see
                      // `ActivityFilters.lens`. A `SegmentedButton`, never a
                      // `RadioGroup`: this body is a `showModalBottomSheet`
                      // below 600 px, and `RadioGroup` mutates its subtree
                      // mid-frame and crashes that layout (the reason
                      // `entity_sort_filter_sheet.dart` hand-rolls a list).
                      // Horizontal scroll, not `width: double.infinity`.
                      // `SegmentedButton` clamps each child to
                      // `maxWidth / childCount`, so a full-width box does not
                      // overflow — it silently *clips* the labels, and
                      // "Comments" is one unbreakable word that already
                      // exceeds its ~78 px share on a 320 px sheet at
                      // `kTextScaleMax` (worse in de/fr). Scrolling keeps the
                      // labels whole, which is what `debug_panel_section.dart`
                      // and `segmented_setting_row.dart` both do for their own
                      // three-segment controls.
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<ActivityLens>(
                            segments: [
                              ButtonSegment(
                                value: ActivityLens.all,
                                label: Text(context.tr('all')),
                              ),
                              ButtonSegment(
                                value: ActivityLens.comments,
                                label: Text(context.tr('comments')),
                              ),
                              ButtonSegment(
                                value: ActivityLens.calls,
                                label: Text(context.tr('calls')),
                              ),
                            ],
                            selected: {f.lens},
                            showSelectedIcon: false,
                            onSelectionChanged: (v) => vm.setLens(v.first),
                          ),
                        ),
                      ),
                      SizedBox(height: InSpacing.md(context)),
                      _RecordTypePicker(vm: vm),
                      SizedBox(height: InSpacing.md(context)),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: f.lens != ActivityLens.all ? 0.4 : 1,
                        // All three, not just `IgnorePointer`: that blocks
                        // pointer events only, leaving the greyed-out picker
                        // reachable by Tab and announced to a screen reader as
                        // an enabled control that silently does nothing.
                        child: IgnorePointer(
                          ignoring: f.lens != ActivityLens.all,
                          child: ExcludeFocus(
                            excluding: f.lens != ActivityLens.all,
                            child: ExcludeSemantics(
                              excluding: f.lens != ActivityLens.all,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MultiEntityPicker<ActivityTypeOption>(
                                    labelKey: 'type',
                                    selectedIds: f.typeIds
                                        .map((e) => '$e')
                                        .toList(growable: false),
                                    items: typeOptions,
                                    idOf: (o) => o.id,
                                    displayString: (o) => o.name,
                                    onChanged: (ids) => vm.setTypeIds(
                                      ids
                                          .map(int.tryParse)
                                          .whereType<int>()
                                          .toSet(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: InSpacing.md(context)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: f.isActive ? vm.clearFilters : null,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: Text(context.tr('clear_filters')),
                ),
              ),
            ],
          );
        },
      ),
    );
    return widget.inline ? panel : SafeArea(top: false, child: panel);
  }
}

/// The quick ranges the date filter offers as a 2 × 2 grid of toggles.
enum ActivityQuickRange {
  today('today'),
  last7('last_7_days'),
  last30('last_30_days'),
  allTime('all_time');

  const ActivityQuickRange(this.labelKey);

  final String labelKey;
}

/// The `[from, until)` [q] stands for on [today] (default: the device's), or
/// null for All Time, which is how the filter says "no range". Whole local
/// days, the same shape a calendar pick or a day bar writes; the "Last N
/// days" ranges end today and resolve through the dashboard's presets, so
/// "Last 30 days" means the same thing on both screens.
(DateTime, DateTime)? activityQuickRange(ActivityQuickRange q, {Date? today}) {
  final t = today ?? Date.today();
  final (Date start, Date end) = switch (q) {
    ActivityQuickRange.today => (t, t),
    ActivityQuickRange.last7 => const DashboardPresetRange(
      DashboardDatePreset.last7,
    ).resolve(today: t),
    ActivityQuickRange.last30 => const DashboardPresetRange(
      DashboardDatePreset.last30,
    ).resolve(today: t),
    ActivityQuickRange.allTime => (t, t),
  };
  if (q == ActivityQuickRange.allTime) return null;
  return (start.toDateTime(), end.addDays(1).toDateTime());
}

/// The quick range [f] holds exactly, or null for a custom one (a bar, a
/// drag, a calendar pick, or a quick range picked on an earlier day — it is
/// stored as the dates it covered then).
ActivityQuickRange? activityQuickRangeOf(ActivityFilters f, {Date? today}) {
  if (!f.hasRange) return ActivityQuickRange.allTime;
  for (final q in ActivityQuickRange.values) {
    final r = activityQuickRange(q, today: today);
    if (r != null && r.$1 == f.from && r.$2 == f.until) return q;
  }
  return null;
}

/// The range control: four quick ranges as a 2 × 2 grid of toggles, and a
/// calendar button for any other — the dashboard's period picker, presets
/// and all. A range from a timeline bar or a drag lands here too: no toggle
/// is lit, and the calendar button carries the dates with a ✕ to drop them.
///
/// A quick range is resolved to dates **when it is picked** and stored as a
/// fixed range, the same shape a timeline bar writes — the filter has one
/// representation, and its chip prints the dates it is actually applying.
class _DateRangeRow extends StatelessWidget {
  const _DateRangeRow({required this.vm, required this.formatter});

  final ActivityViewModel vm;
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    final f = vm.filters;
    final quick = activityQuickRangeOf(f);
    final custom = f.hasRange && quick == null;
    Widget toggle(ActivityQuickRange q) => Expanded(
      child: _RangeToggle(
        label: context.tr(q.labelKey),
        selected: quick == q,
        onPressed: () {
          final r = activityQuickRange(q);
          vm.setRange(r?.$1, r?.$2);
        },
      ),
    );
    final gap = SizedBox(width: InSpacing.sm, height: InSpacing.sm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionLabel(context.tr('date_range')),
        const SizedBox(height: InSpacing.xs),
        // `inMutuallyExclusiveGroup` on each toggle reads the four as one
        // choice; the grid is two rows so the labels never squeeze.
        Row(
          children: [
            toggle(ActivityQuickRange.today),
            gap,
            toggle(ActivityQuickRange.last7),
          ],
        ),
        gap,
        Row(
          children: [
            toggle(ActivityQuickRange.last30),
            gap,
            toggle(ActivityQuickRange.allTime),
          ],
        ),
        gap,
        Row(
          children: [
            Flexible(
              child: Builder(
                // Its own context, so the popover anchors to this button.
                builder: (anchor) => TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: Size(
                      0,
                      Env.isTouchPrimary ? InSizes.touchTarget : 36,
                    ),
                    foregroundColor: custom
                        ? context.inTheme.ink
                        : context.inTheme.ink2,
                  ),
                  icon: const Icon(Icons.calendar_today_outlined, size: 14),
                  label: Text(
                    custom
                        ? activityRangeLabel(
                            context,
                            from: f.from,
                            until: f.until,
                            formatter: formatter,
                          )
                        : context.tr('custom_range'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => openDateRangePicker(
                    anchor,
                    current: _currentRange(f),
                    formatter: formatter,
                    onChange: (r) {
                      if (r is DashboardPresetRange &&
                          r.preset == DashboardDatePreset.allTime) {
                        vm.setRange(null, null);
                        return;
                      }
                      final (start, end) = r.resolve(
                        firstMonthOfYear:
                            formatter?.settings.firstMonthOfYear ?? 1,
                      );
                      vm.setRange(
                        start.toDateTime(),
                        end.addDays(1).toDateTime(),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (custom)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: context.tr('clear'),
                onPressed: () => vm.setRange(null, null),
              ),
          ],
        ),
      ],
    );
  }

  /// The picker's view of the active range: whole days, inclusive. An hour
  /// bar's range shows as its day — the chip above the feed carries the
  /// hours.
  static DashboardDateRange _currentRange(ActivityFilters f) {
    if (!f.hasRange) {
      return const DashboardPresetRange(DashboardDatePreset.allTime);
    }
    final from = f.from;
    final until = f.until;
    final start = from == null ? null : Date(from.year, from.month, from.day);
    // `until` is exclusive: a midnight bound ends the day before.
    final endInstant = until?.subtract(const Duration(milliseconds: 1));
    final end = endInstant == null
        ? null
        : Date(endInstant.year, endInstant.month, endInstant.day);
    final today = Date.today();
    return DashboardCustomRange(
      start: start ?? end ?? today,
      end: end ?? today,
    );
  }
}

/// One quick-range toggle: a rounded rectangle, filled when on.
class _RangeToggle extends StatelessWidget {
  const _RangeToggle({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          // In a `Row`: the theme's infinite minimum width would crash it
          // (`docs/buttons-and-spacing.md`).
          minimumSize: Size(64, Env.isTouchPrimary ? InSizes.touchTarget : 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: selected ? tokens.ink : tokens.ink2,
          backgroundColor: selected ? tokens.surfaceAlt : null,
          side: BorderSide(
            color: selected ? tokens.borderStrong : tokens.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InRadii.r2),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Single-select record type, offering only the types the window holds under
/// every other filter (`ActivityViewModel.recordTypeCounts`), each with its
/// count — the facet rule, so no option can only empty the feed.
class _RecordTypePicker extends StatelessWidget {
  const _RecordTypePicker({required this.vm});

  final ActivityViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final counts = vm.recordTypeCounts;
    final selected = vm.filters.recordType;
    final options = [
      for (final t in ActivityRecordType.values)
        if ((counts[t] ?? 0) > 0 || t == selected) t,
    ];
    return SearchableDropdownField<ActivityRecordType>(
      label: context.tr('record_type'),
      // No type picked keeps every record.
      hintText: context.tr('all_records'),
      items: options,
      initialValue: selected,
      displayString: (t) => context.tr(t.labelKey),
      idOf: (t) => t.name,
      // Loading until the window has arrived; empty after that is real.
      emptyHintKey: vm.section.data == null ? null : 'no_records_found',
      optionTrailingBuilder: (context, t) => Text(
        '${counts[t] ?? 0}',
        style: TextStyle(
          fontSize: 12,
          color: tokens.ink3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onChanged: vm.setRecordType,
    );
  }
}

/// One chip per category, each with what it would keep under the other
/// filters (`ActivityViewModel.categoryCounts`). A zero chip that isn't
/// already on is disabled — ticking it could only empty the feed.
///
/// In the filter panel, or (with [showLabel] false) under the `/activity`
/// chart on a pane ≥ 600 px, where ticking one visibly redraws the bars.
class ActivityCategoryChips extends StatelessWidget {
  const ActivityCategoryChips({
    super.key,
    required this.vm,
    this.showLabel = true,
  });

  final ActivityViewModel vm;

  /// The "Category" caption above the chips — dropped under the chart.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final selected = vm.filters.categories;
    final counts = vm.categoryCounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          _SectionLabel(context.tr('category')),
          const SizedBox(height: InSpacing.xs),
        ],
        Wrap(
          spacing: InSpacing.sm,
          runSpacing: InSpacing.xs,
          children: [
            for (final c in ActivityCategory.values)
              Builder(
                builder: (context) {
                  final n = counts[c] ?? 0;
                  final on = selected.contains(c);
                  final (_, fg) = activityToneColors(
                    tokens,
                    toneForCategory(c),
                  );
                  return FilterChip(
                    selected: on,
                    showCheckmark: false,
                    // Denser on a pointer only — on touch the chip keeps its
                    // padded target (CLAUDE.md § Design system, touch targets).
                    visualDensity: Env.isTouchPrimary
                        ? null
                        : VisualDensity.compact,
                    avatar: Icon(activityCategoryIcon(c), size: 16, color: fg),
                    label: Text.rich(
                      TextSpan(
                        text: activityCategoryLabel(context, c),
                        children: [
                          TextSpan(
                            text: '  $n',
                            style: TextStyle(color: tokens.ink3),
                          ),
                        ],
                      ),
                    ),
                    onSelected: n == 0 && !on
                        ? null
                        : (_) => vm.toggleCategory(c),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: context.inTheme.ink3),
  );
}
