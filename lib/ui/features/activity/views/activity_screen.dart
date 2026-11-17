import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/search_focus_registry.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/shortcuts/shortcut_catalog.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/activity/activity_timeline.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/utils/calendar_week_start.dart';
import 'package:admin/ui/core/utils/platform_modifier.dart';
import 'package:admin/ui/core/widgets/app_selection_area.dart';
import 'package:admin/ui/core/widgets/content_panel.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';
import 'package:admin/ui/core/widgets/error_view.dart';
import 'package:admin/ui/core/widgets/filter_icon_button.dart';
import 'package:admin/ui/core/widgets/key_cap.dart';
import 'package:admin/ui/features/reports/helpers/report_access.dart';
import 'package:admin/ui/features/activity/activity_deep_link.dart';
import 'package:admin/ui/features/activity/view_models/activity_view_model.dart';
import 'package:admin/ui/features/activity/widgets/activity_feed_row.dart';
import 'package:admin/ui/features/activity/widgets/activity_filter_sheet.dart';
import 'package:admin/ui/features/activity/widgets/activity_period_labels.dart';
import 'package:admin/ui/features/activity/widgets/activity_timeline_chart.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';
import 'package:admin/ui/features/dashboard/widgets/activity_card.dart'
    as card
    show activityDayLabel;
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/dashboard/widgets/freshness.dart';
import 'package:admin/ui/features/shell/widgets/app_drawer.dart';
import 'package:admin/utils/formatting.dart';

/// Pane width at which the filters leave their sheet for a side rail.
const double kActivityRailMinWidth = 1000;

/// Width of that rail.
const double kActivityRailWidth = 300;

/// Content cap on a wide pane: past it the feed's chevron drifts so far from
/// its sentence that the eye can't join them.
const double kActivityBodyMaxWidth = 1200;

/// Below this body height the timeline strip is dropped: a landscape phone
/// already spends half its height on the app bar, search and chips.
const double kActivityTimelineMinBodyHeight = 420;

/// Pane width from which the search sits in the title row, beside refresh,
/// rather than on a full-width row of its own under it.
const double kActivitySearchInTitleMinWidth = 720;

/// The search box's width in the title row.
const double kActivityTitleSearchWidth = 340;

/// Pane width from which the category chips sit under the chart — they
/// redraw it — instead of in the filters.
const double kActivityChipsUnderChartMinWidth = 600;

/// The company-wide activity feed at `/activity` (invoiceninja/flutter#53).
///
/// Reads the same Drift cache row as the dashboard's Activity card, so it
/// paints from cache immediately and refreshing either surface updates both.
/// Unlike the card it renders every row in the window, day-grouped like the
/// card with the time on each row, under a bar chart of the window that
/// doubles as the date filter, and narrowable by date / category / user /
/// source / record type / activity type / text. A wide pane shows the filters
/// as a rail instead of a sheet.
///
/// Owns the [Formatter] and the [ActivityViewModel] — both rebuilt on
/// company-switch via the auth session listener (not via `build`, which would
/// dispose a notifier mid-rebuild). Mirrors `ReportsHost`.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late Services _services;
  late ActivityViewModel _vm;
  late String _companyId;
  Formatter? _formatter;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'activity search');

  /// Where `/` finds the search box. Stashed in `initState` so `dispose` can
  /// release the claim without reading a detaching context.
  SearchFocusRegistry? _searchRegistry;

  /// Whether the body drew the category chips under the chart on its last
  /// build — read when the filter button opens the sheet, so the sheet leaves
  /// them out. A plain field: nothing rebuilds on it.
  bool _chipsUnderChart = false;

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    _searchRegistry = _services.searchFocus;
    _companyId = _services.auth.session.value?.currentCompanyId ?? '';
    _vm = _buildVm();
    _services.auth.session.addListener(_onSessionChanged);
    if (_companyId.isNotEmpty) _loadFormatter();
  }

  ActivityViewModel _buildVm() {
    final vm = ActivityViewModel(
      repo: _services.dashboard,
      companyId: _companyId,
      navStateDao: _services.db.navStateDao,
    );
    vm.addListener(_syncSearchField);
    return vm;
  }

  /// Keeps the search box showing whatever the VM is actually filtering by.
  ///
  /// The two drift apart in three ways otherwise, all of them leaving a
  /// filtered list above an empty-looking box: filters are **restored
  /// asynchronously** on launch, "Clear filters" in the sheet resets them from
  /// outside this widget, and a company switch rehydrates a different set.
  /// Guarded on inequality, so this never fights the user mid-keystroke (they
  /// are equal while typing) or moves the caret.
  void _syncSearchField() {
    final wanted = _vm.filters.search;
    if (_searchController.text == wanted) return;
    _searchController.text = wanted;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Assigned here, not in `build`: `ActivityFormatter` reads `Localization`,
    // so this is the hook that re-fires when the locale changes.
    //
    // It also fires for every *other* dependency this State's `build` reads —
    // `Theme.of`, `MediaQuery.sizeOf` — i.e. on a theme toggle, a rotation and
    // every frame of a desktop window drag. `setTitleResolver` is written to be
    // cheap and phase-safe for exactly that reason; don't move work in here.
    _attachTitleResolver();
    // `/` focuses this box while the screen is on stage. Claimed here, under
    // the `TickerMode` gate, and released offstage — the same rule, for the
    // same reason, as `TokenSearchField` (`SearchFocusRegistry`): go_router
    // keeps every visited branch mounted.
    if (TickerMode.valuesOf(context).enabled) {
      _searchRegistry?.claim(_searchFocus);
    } else {
      _searchRegistry?.release(_searchFocus);
    }
  }

  /// Wires the sentence renderer the VM's text filter matches against. Called
  /// on every dependency change **and** after a company switch swaps the VM —
  /// `didChangeDependencies` does not re-fire for that, and a VM without a
  /// resolver silently stops matching rendered text.
  void _attachTitleResolver() {
    final formatter = ActivityFormatter(context);
    _vm.setTitleResolver((a) => formatter.format(a).title);
    _attachWeekStart();
  }

  /// Week-wide timeline bars start on the company's first day of week, else
  /// the locale's. `calendarFirstDayOfWeek` counts from Sunday = 0; the
  /// bucketing uses `DateTime.weekday` (Monday = 1 … Sunday = 7).
  void _attachWeekStart() {
    final sundayZero = calendarFirstDayOfWeek(context, _formatter);
    _vm.setFirstDayOfWeek(sundayZero == 0 ? DateTime.sunday : sundayZero);
  }

  void _loadFormatter() {
    final loadingFor = _companyId;
    _services.formatterFor(loadingFor).then((f) {
      if (!mounted || loadingFor != _companyId) return;
      setState(() => _formatter = f);
      _attachWeekStart();
    });
  }

  void _onSessionChanged() {
    final nextId = _services.auth.session.value?.currentCompanyId ?? '';
    if (nextId == _companyId) return;
    final oldVm = _vm;
    setState(() {
      _companyId = nextId;
      _formatter = null;
      _vm = _buildVm();
    });
    oldVm
      ..removeListener(_syncSearchField)
      ..dispose();
    _attachTitleResolver();
    _syncSearchField();
    if (_companyId.isNotEmpty) _loadFormatter();
  }

  @override
  void dispose() {
    _services.auth.session.removeListener(_onSessionChanged);
    _searchRegistry?.release(_searchFocus);
    _searchFocus.dispose();
    // Listener first: `_syncSearchField` writes to the controller below.
    _vm
      ..removeListener(_syncSearchField)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onRowTap(DashboardActivity a) {
    final target = activityDeepLinkTarget(a);
    if (target == null) return;
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    // The pane, not the window: the sidebar takes part of a desktop window,
    // and the app bar's filter button has to agree with the body's rail.
    return LayoutBuilder(
      builder: (context, c) => _scaffold(
        context,
        rail: c.maxWidth >= kActivityRailMinWidth,
        searchInTitle: c.maxWidth >= kActivitySearchInTitleMinWidth,
      ),
    );
  }

  Widget _scaffold(
    BuildContext context, {
    required bool rail,
    required bool searchInTitle,
  }) {
    final globalNav = Breakpoints.isGlobalNavVisible(context);
    return Scaffold(
      drawer: globalNav ? null : const AppDrawer(),
      appBar: AppBar(
        title: Text(context.tr('activity')),
        leading: globalNav ? null : const DrawerHamburger(),
        automaticallyImplyLeading: !globalNav,
        actions: [
          // A wide pane has the room to keep the search in the title row,
          // beside refresh, and to give the feed the row it took.
          if (searchInTitle)
            Center(
              child: SizedBox(
                width: kActivityTitleSearchWidth,
                child: _searchField(context),
              ),
            ),
          ListenableBuilder(
            listenable: _vm,
            builder: (context, _) => IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: context.tr('refresh'),
              onPressed: _vm.isRefreshing ? null : _vm.refresh,
            ),
          ),
          // The rail *is* the filter surface on a wide pane — a button opening
          // a second copy of it would be two controls for one state.
          if (!rail)
            ListenableBuilder(
              listenable: _vm,
              builder: (context, _) => FilterIconButton(
                activeCount: _vm.filters.activeCount,
                onPressed: () => openActivityFilters(
                  context,
                  vm: _vm,
                  companyId: _companyId,
                  formatter: _formatter,
                  showCategories: !_chipsUnderChart,
                ),
              ),
            ),
        ],
        bottom: searchInTitle
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _capped(_searchField(context)),
                ),
              ),
      ),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) => _body(context, rail: rail),
      ),
    );
  }

  /// The search box: in the title row on a wide pane, a row of its own under
  /// it otherwise. `/` focuses it ([SearchFocusRegistry]), and with a pointer
  /// its empty, unfocused box shows that key as a cap.
  Widget _searchField(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_searchController, _searchFocus]),
      builder: (context, _) {
        final empty = _searchController.text.isEmpty;
        final glyphs =
            empty &&
                !Env.isTouchPrimary &&
                !_searchFocus.hasFocus &&
                identical(_searchRegistry?.current, _searchFocus)
            ? _focusSearchGlyphs(context)
            : null;
        return TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          // Search queries are names and numbers, not prose — iOS
          // autocorrecting "Acme" to "Acne" mid-search is the failure.
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: context.tr('search'),
            suffixIcon: !empty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: context.tr('clear'),
                    onPressed: () => _vm.setSearch(''),
                  )
                : (glyphs == null || glyphs.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: IgnorePointer(
                            child: KeyCapRow(
                              keys: glyphs,
                              dense: true,
                              keyColor: context.inTheme.ink3,
                            ),
                          ),
                        )),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
          ),
          onChanged: _vm.setSearch,
        );
      },
    );
  }

  /// The glyphs of the shortcut that focuses the search (`/` unless rebound),
  /// or null when it is unbound — as `TokenSearchField` reads them.
  List<String>? _focusSearchGlyphs(BuildContext context) {
    try {
      return _services.keyboardShortcuts
          .resolvedBinding(ShortcutActionIds.focusSearch)
          ?.displayGlyphs(platformModifierLabel());
    } catch (_) {
      // A host with no shortcut controller (a preview, a bare test tree):
      // the hint is decoration, never a reason to fail the field.
      return null;
    }
  }

  /// At most [kActivityBodyMaxWidth] wide, centred — the same shape as the
  /// settings and record screens' capped columns under a start-aligned title.
  static Widget _capped(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kActivityBodyMaxWidth),
      child: child,
    ),
  );

  Widget _body(BuildContext context, {required bool rail}) {
    final tokens = context.inTheme;
    final section = _vm.section;

    Widget content;
    if (section.hasError && !section.hasData) {
      content = ErrorView(
        message: context.tr('couldnt_load_tap_to_retry', {
          'section': context.tr('activity').toLowerCase(),
        }),
        onRetry: _vm.refresh,
      );
    } else if (section.data == null) {
      content = ListView(
        padding: EdgeInsets.all(InSpacing.lg(context)),
        children: const [
          ActivityFeedSkeleton(count: 8, density: ActivityRowDensity.page),
        ],
      );
    } else if (_vm.entries.isEmpty) {
      // Over-filtering a *bounded* window is easy, so the filtered flavour of
      // this state has to offer a way back out rather than dead-end.
      content = _vm.filters.isActive
          ? EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: context.tr('no_records_found'),
              action: TextButton.icon(
                onPressed: _vm.clearFilters,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(context.tr('clear_filters')),
              ),
            )
          : EmptyState(
              icon: Icons.notifications_none_outlined,
              title: context.tr('no_activity_yet'),
            );
    } else {
      content = _list(context);
    }

    final scrollable = RefreshIndicator(
      onRefresh: _vm.refresh,
      child: content is ListView
          ? content
          : ListView(
              // Wrapped so `RefreshIndicator` has a Scrollable to attach to
              // at all — `EmptyState` is a plain Column and would leave the
              // pull gesture inert. The physics need no help: `ScrollView`
              // already gives a controller-less vertical list
              // `AlwaysScrollableScrollPhysics` on every platform, so short
              // content stays draggable here and in the feed below.
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.5,
                  child: content,
                ),
              ],
            ),
    );

    // Outside the `SelectionArea` on purpose: a mouse drag across the bars is
    // a range pick, and inside the region it would race text selection.
    final feed = AppSelectionArea(child: scrollable);
    final hasTimeline = _vm.timeline.buckets.isNotEmpty;
    // The feed sits in the white panel a standalone list draws its rows in
    // (docs/activity-timeline.md § The feed sits in a white panel) — while it
    // loads too, so the skeleton rows do not jump into a card when the data
    // lands. An error or an empty window keeps its bare state on the page, as
    // an empty list does: a card around nothing reads as a broken one.
    final paneled =
        !(section.hasError && !section.hasData) &&
        (section.data == null || _vm.entries.isNotEmpty);
    final gutter = InSpacing.lg(context);

    if (rail) {
      // A rail pane is past every width gate and never drops the chart.
      _chipsUnderChart = hasTimeline;
      return Column(
        children: [
          _capped(
            _HeaderStrip(
              vm: _vm,
              formatter: _formatter,
              chipsUnderChart: _chipsUnderChart,
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Expanded(
            child: _capped(
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        if (hasTimeline)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              InSpacing.lg(context),
                              InSpacing.lg(context),
                              InSpacing.lg(context),
                              0,
                            ),
                            child: DashboardCardShell(
                              child: _timelineWithChips(
                                compact: false,
                                chips: true,
                              ),
                            ),
                          ),
                        Expanded(
                          child: paneled
                              ? ContentPanel(
                                  wide: true,
                                  // The chart card's gutter, so the two cards'
                                  // edges line up.
                                  side: gutter,
                                  top: gutter,
                                  bottom:
                                      gutter +
                                      MediaQuery.paddingOf(context).bottom,
                                  child: feed,
                                )
                              : feed,
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: tokens.border),
                      ),
                    ),
                    child: SizedBox(
                      width: kActivityRailWidth,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ActivityFilterPanel(
                          vm: _vm,
                          companyId: _companyId,
                          formatter: _formatter,
                          inline: true,
                          showCategories: !_chipsUnderChart,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, outer) {
        final wideEnough = outer.maxWidth >= kActivityChipsUnderChartMinWidth;
        return Column(
          children: [
            // The header strip is above the body's own `LayoutBuilder`, so it
            // reads the decision that builder made — through the field. No
            // rule under it: it is the caption over the panel below, the way a
            // list's count sits over its rows.
            _HeaderStrip(
              vm: _vm,
              formatter: _formatter,
              chipsUnderChart: _chipsUnderChart,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final showChart =
                      hasTimeline &&
                      c.maxHeight >= kActivityTimelineMinBodyHeight;
                  _chipsUnderChart = showChart && wideEnough;
                  // One panel holds the chart and the feed it draws: two
                  // stacked cards would spend a phone's height on a second
                  // pair of margins.
                  final body = Column(
                    children: [
                      if (showChart) ...[
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            gutter,
                            InSpacing.md(context),
                            gutter,
                            InSpacing.sm,
                          ),
                          child: _timelineWithChips(
                            compact: true,
                            chips: _chipsUnderChart,
                          ),
                        ),
                        Divider(height: 1, color: tokens.border),
                      ],
                      Expanded(child: feed),
                    ],
                  );
                  if (!paneled && !showChart) return body;
                  return ContentPanel(
                    wide: false,
                    side: gutter,
                    top: 0,
                    child: body,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// The chart, and on a pane wide enough the category chips under it — they
  /// redraw its bars, so that is where they are read.
  Widget _timelineWithChips({required bool compact, required bool chips}) {
    if (!chips) return _timeline(compact: compact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _timeline(compact: compact),
        SizedBox(height: InSpacing.md(context)),
        ActivityCategoryChips(vm: _vm, showLabel: false),
      ],
    );
  }

  Widget _timeline({required bool compact}) => ActivityTimelineChart(
    timeline: _vm.timeline,
    onLoadMore: _vm.canLoadMore ? _vm.loadMore : null,
    loadingMore: _vm.isLoadingMore,
    from: _vm.filters.from,
    until: _vm.filters.until,
    oldestAt: _vm.oldestAt,
    selectionCount: _vm.matchCount,
    formatter: _formatter,
    compact: compact,
    onSelect: _vm.setRange,
    onClear: () => _vm.setRange(null, null),
  );

  Widget _list(BuildContext context) {
    final entries = _vm.entries;
    // Only when the server actually capped us. Below the cap nothing is hidden,
    // so the footer would assert a truncation that isn't happening — and on a
    // filtered list it reads as "there should be more rows here". A fetch that
    // came back short (`canLoadMore` false, under the max) is the same case.
    final showFooter = _vm.canLoadMore || _vm.atWindowMax;
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: InSpacing.sm,
      ),
      // +1 for the window footer, but only when there is one to show.
      itemCount: entries.length + (showFooter ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == entries.length) {
          return _WindowFooter(
            vm: _vm,
            canOpenReport:
                openableReport(
                  'activity',
                  _services.auth.session.value?.currentCompany,
                ) !=
                null,
          );
        }
        final entry = entries[i];
        return switch (entry) {
          ActivityDayHeader() => _DayHeader(
            day: entry.day,
            count: entry.count,
            formatter: _formatter,
            first: i == 0,
          ),
          ActivityFeedItem() => _row(
            context,
            entry.activity,
            followUpEdits: entry.followUpEdits,
          ),
          ActivityRunToggle() => _RunToggle(
            entry: entry,
            onPressed: () => _vm.toggleRun(entry.runId),
          ),
        };
      },
    );
  }

  Widget _row(
    BuildContext context,
    DashboardActivity a, {
    int followUpEdits = 0,
  }) {
    final render = ActivityFormatter(context).format(a);
    final formatter = _formatter;
    return ActivityFeedRow(
      render: render,
      // The day header above already names the date; the time is the row's
      // own column (or the head of its meta line on a narrow pane). Until
      // the company `Formatter` loads, the relative time stands in.
      time: formatter == null ? null : activityTimeLabel(a, formatter),
      meta: activityAuditMeta(
        a,
        render: render,
        formatter: formatter,
        showDate: false,
        showTime: false,
        // The edits that followed within minutes are not rows of their own.
        note: followUpEdits > 0 ? context.tr('activity_also_updated') : null,
      ),
      onTap: activityDeepLinkTarget(a) == null ? null : () => _onRowTap(a),
    );
  }
}

/// Freshness stamp plus, when narrowed, the surviving-row count and removable
/// filter chips. Renders no chips at all in the default (unfiltered) view so
/// the screen carries no extra chrome for the common case.
class _HeaderStrip extends StatelessWidget {
  const _HeaderStrip({
    required this.vm,
    required this.formatter,
    required this.chipsUnderChart,
  });

  final ActivityViewModel vm;
  final Formatter? formatter;

  /// The category chips are under the chart, lit — a second, removable chip
  /// here would be the same state twice.
  final bool chipsUnderChart;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final f = vm.filters;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        InSpacing.lg(context),
        InSpacing.sm,
        InSpacing.lg(context),
        InSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FreshnessTicker(
                  builder: (context) => Text(
                    freshnessText(
                      context,
                      lastRefreshed: vm.lastRefreshed,
                      isRefreshing: vm.isRefreshing,
                    ),
                    style: TextStyle(fontSize: 11, color: tokens.ink3),
                  ),
                ),
              ),
              if (f.isActive)
                Text(
                  '${vm.matchCount}',
                  style: TextStyle(fontSize: 11, color: tokens.ink3),
                ),
            ],
          ),
          if (f.isActive) ...[
            SizedBox(height: InSpacing.sm),
            Wrap(
              spacing: InSpacing.sm,
              runSpacing: InSpacing.xs,
              children: [
                if (f.hasRange)
                  _Chip(
                    label: activityRangeLabel(
                      context,
                      from: f.from,
                      until: f.until,
                      formatter: formatter,
                    ),
                    onRemove: () => vm.setRange(null, null),
                  ),
                if (f.categories.isNotEmpty && !chipsUnderChart)
                  _Chip(
                    label: _categoriesLabel(context, f.categories),
                    onRemove: vm.clearCategories,
                  ),
                if (f.search.trim().isNotEmpty)
                  _Chip(
                    label: f.search.trim(),
                    onRemove: () => vm.setSearch(''),
                  ),
                if (f.userId != null)
                  _Chip(
                    label: context.tr('user'),
                    onRemove: () => vm.setUser(null),
                  ),
                if (f.lens != ActivityLens.all)
                  _Chip(
                    label: context.tr(
                      f.lens == ActivityLens.calls ? 'calls' : 'comments',
                    ),
                    onRemove: () => vm.setLens(ActivityLens.all),
                  ),
                if (f.recordType case final t?)
                  _Chip(
                    label: context.tr(t.labelKey),
                    onRemove: () => vm.setRecordType(null),
                  ),
                if (f.lens == ActivityLens.all && f.typeIds.isNotEmpty)
                  _Chip(
                    label: '${context.tr('type')} (${f.typeIds.length})',
                    onRemove: () => vm.setTypeIds(const <int>{}),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Sent, Paid" — or "Category (3)" once naming them all would crowd the
/// strip.
String _categoriesLabel(BuildContext context, Set<ActivityCategory> cats) {
  if (cats.length <= 2) {
    // Enum order, not tap order, so the chip doesn't reshuffle as you tick.
    return [
      for (final c in ActivityCategory.values)
        if (cats.contains(c)) activityCategoryLabel(context, c),
    ].join(', ');
  }
  return '${context.tr('category')} (${cats.length})';
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Default density on purpose. `shrinkWrap` opts out of the
    // `kMinInteractiveDimension` inflation `padded` gives on iOS/Android, which
    // put the ✕ well under `InSizes.touchTarget` — and this chip is the only
    // way to drop its filter from the header strip. Every other `InputChip` in
    // the app (`multi_entity_picker`, `multi_product_picker`, `report_control_bar`)
    // uses the defaults too.
    //
    // Body *and* ✕ both clear, mirroring the reports drill-down breadcrumb: the
    // whole control is the affordance, so make all of it a target.
    return InputChip(
      label: Text(label),
      onPressed: onRemove,
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }
}

/// A day's header, as the dashboard's activity card draws it — "Today",
/// "Yesterday", then the company date (`activityDayLabel`) — with how many
/// events the day holds, folded runs and absorbed edits included.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.count,
    required this.formatter,
    required this.first,
  });

  final DateTime day;
  final int count;
  final Formatter? formatter;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: first ? InSpacing.sm : InSpacing.lg(context),
        bottom: InSpacing.xs,
      ),
      child: Semantics(
        header: true,
        headingLevel: 2,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: dayHeaderLabel(context, day, formatter),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: tokens.ink2,
                ),
              ),
              TextSpan(text: '  ${activityEventCount(context, count)}'),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: tokens.ink3),
        ),
      ),
    );
  }
}

/// "+3 more" under a folded run, "Collapse" under an opened one — aligned
/// with the sentences.
class _RunToggle extends StatelessWidget {
  const _RunToggle({required this.entry, required this.onPressed});

  final ActivityRunToggle entry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final height = Env.isTouchPrimary ? InSizes.touchTarget : 28.0;
    return LayoutBuilder(
      builder: (context, c) {
        // Under the sentence: past the icon, and past the time column where
        // the rows have one.
        var start = 28 + InSpacing.md(context) - 8;
        if (c.maxWidth >= kActivityRowInlineMinWidth) {
          start += MediaQuery.textScalerOf(context).scale(64);
        }
        return Padding(
          padding: EdgeInsetsDirectional.only(start: start),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: Size(0, height),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onPressed,
              icon: Icon(
                entry.expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
              ),
              // Sized on the `Text`, never through `styleFrom(textStyle:)` —
              // that replaces the theme's label style wholesale, font family
              // included.
              label: Text(
                entry.expanded
                    ? context.tr('collapse')
                    : context.tr('plus_n_more', {'count': '${entry.hidden}'}),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `Today` / `Yesterday` / the company-formatted date — the dashboard card's
/// `activityDayLabel`, counted in calendar days through `Date` so a DST
/// change cannot make yesterday today. `day` is the local calendar day
/// `localDayOf` grouped on. Before the company `Formatter` has loaded an
/// older day reads as the locale's medium date.
String dayHeaderLabel(
  BuildContext context,
  DateTime day,
  Formatter? formatter,
) {
  final d = Date(day.year, day.month, day.day);
  final today = Date.today();
  if (formatter != null) {
    return card.activityDayLabel(context, d, today, formatter);
  }
  final delta = today.differenceInDays(d);
  if (delta == 0) return context.tr('today');
  if (delta == 1) return context.tr('yesterday');
  return MaterialLocalizations.of(context).formatMediumDate(day);
}

/// Explains the feed's ceiling at the end of the list — shown only while the
/// window is full, i.e. older activity may exist (`?reactv2` has no cursor, so
/// the window is a hard boundary, not a page) — and offers the way past it:
/// Load more under the window's cap, the Activity report at it.
///
/// Phrased as a statement about the feed's *scope* rather than a row count, so
/// it stays true — and doesn't read as "rows are missing" — while a filter is
/// narrowing the list beneath it. The match count lives in the header strip.
class _WindowFooter extends StatelessWidget {
  const _WindowFooter({required this.vm, required this.canOpenReport});

  final ActivityViewModel vm;

  /// Whether this company may open the Activity report — the link goes only
  /// where the route's own guard would let it.
  final bool canOpenReport;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: InSpacing.lg(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('activity_feed_window', {'count': '${vm.windowCount}'}),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: tokens.ink3),
          ),
          if (vm.canLoadMore) ...[
            SizedBox(height: InSpacing.md(context)),
            OutlinedButton.icon(
              // A centred single button renders edge to edge without its own
              // minimum (docs/buttons-and-spacing.md § Centered single-action
              // buttons must constrain their own width too).
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: vm.isLoadingMore ? null : vm.loadMore,
              icon: vm.isLoadingMore
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: Text(context.tr('load_more')),
            ),
            if (vm.loadMoreFailed) ...[
              const SizedBox(height: InSpacing.xs),
              Text(
                context.tr('couldnt_load_tap_to_retry', {
                  'section': context.tr('activity').toLowerCase(),
                }),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: tokens.overdue),
              ),
            ],
          ] else if (vm.atWindowMax && canOpenReport) ...[
            SizedBox(height: InSpacing.sm),
            TextButton.icon(
              onPressed: () => context.go('/reports/activity'),
              icon: const Icon(Icons.assessment_outlined, size: 16),
              label: Text(context.tr('activity_open_report')),
            ),
          ],
        ],
      ),
    );
  }
}
