import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/router.dart';
import 'package:admin/app/services.dart';
import 'package:admin/domain/dashboard/billing_status_tabs.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/list_status_tabs.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/list/deep_link_filter_intent.dart';
import 'package:admin/ui/core/list/entity_list_status_tabs.dart';
import 'package:admin/ui/features/dashboard/helpers/converted_hint.dart';
import 'package:admin/ui/features/dashboard/helpers/when_text.dart';
import 'package:admin/ui/features/dashboard/view_models/billing_pipeline_view_model.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/ui/core/widgets/client_name_label.dart';
import 'package:admin/ui/core/widgets/party_money_cell.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_panel_grid.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_record_row.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_status_pill.dart';
import 'package:admin/ui/features/quotes/widgets/quote_status_pill.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';
import 'package:admin/ui/features/dashboard/widgets/list_card_skeleton.dart';
import 'package:admin/utils/formatting.dart';

/// Rows shown on a phone — the same three as every other phone panel.
const int kBillingPipelineNarrowRows = 3;

/// Rows shown on a wide screen: the dashboard's list-panel count, five, or
/// [kDensePanelRows] under Compact — so the card is as tall as the panel
/// paired beside it.
int billingPipelineWideRows(BuildContext context) =>
    dashboardDense(context) ? kDensePanelRows : 5;

/// The Invoices or the Quotes panel: [entity]'s most recent documents behind a
/// status strip with live counts (invoiceninja/flutter#155).
///
/// It was one Invoices & Quotes card across the whole dashboard, drawn as a
/// six-column table — and a short row stretched over ~1,100 px put all the
/// slack between the client's name and the status. As two half-width cards
/// each row is the shared [DashboardRecordRow], like every panel beside it.
///
/// Drift-backed, so — like the task calendar — several things here are
/// load-bearing and invisible at the call site.
///
/// **It must keep itself alive.** Both dashboard bodies are lazily-collected
/// `ListView`s, so a plain `StatefulWidget` is garbage-collected past the cache
/// extent, taking its view model, its Drift subscriptions, the selected tab and
/// the fetch latches with it.
///
/// **Nothing under it may be a `LayoutBuilder`** — the wide grid wraps each row
/// in `IntrinsicHeight`, which throws on an intrinsic query against one in
/// debug and silently answers 0 in release. That is why [narrow] is a
/// parameter: each host already knows which it is. (The strip's `Wrap` is fine
/// — `RenderWrap` answers intrinsics via `getDryLayout`.)
///
/// **It is gated on `view_invoice` / `view_quote`**, unlike the six
/// server-backed panels: those render data the API has already
/// permission-scoped, so an empty card honestly means "nothing to show", while
/// this one reads the local tables — a user without the permission has no rows
/// in Drift, so an ungated strip would paint seven zeroes as a positive claim.
/// See `enabledPanelKinds`.
class DashboardBillingPipelineCard extends StatefulWidget {
  const DashboardBillingPipelineCard({
    super.key,
    required this.companyId,
    required this.formatter,
    required this.refreshNonce,
    required this.narrow,
    required this.entity,
    required this.initialTabId,
    required this.onTabChanged,
  });

  final String companyId;
  final Formatter formatter;

  /// The dashboard's last completed refresh. `refreshAll` iterates the
  /// *cache-backed* kinds only, so without this the one gesture a user makes on
  /// a stale dashboard would refresh every panel except this one.
  final DateTime? refreshNonce;

  /// Stacked rows instead of the wide table. A parameter, never a
  /// `LayoutBuilder` — see the class doc.
  final bool narrow;

  /// [EntityType.invoice] or [EntityType.quote]. Whether this company may
  /// show it at all is `enabledPanelKinds`' decision, made by the host.
  final EntityType entity;

  bool get _invoices => entity == EntityType.invoice;

  /// The tab id restored from `nav_state`, or null for `All`. Persisted by the
  /// host (it owns the dashboard's per-company blob), healed here — a stored id
  /// this company can no longer use degrades to `All`.
  final String? initialTabId;

  /// Fired on a user tap only. Writing on hydrate would rewrite `nav_state` on
  /// every cold start.
  final ValueChanged<String?> onTabChanged;

  @override
  State<DashboardBillingPipelineCard> createState() =>
      _DashboardBillingPipelineCardState();
}

class _DashboardBillingPipelineCardState
    extends State<DashboardBillingPipelineCard>
    with AutomaticKeepAliveClientMixin {
  late Services _services;
  late BillingPipelineViewModel _vm;
  List<BillingStatusTab> _tabs = const [];

  /// True once the user has tapped a tab.
  ///
  /// Gates the late-restore below. [DashboardViewModel._hydrate] is an async
  /// Drift read that does not notify, so the restored tab usually arrives
  /// AFTER this card has mounted — and without the latch a slow `nav_state`
  /// read would yank the user off a tab they had already chosen.
  bool _userPicked = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    _vm = _buildVm();
  }

  /// Rows the view model watches: the most any density shows, so a density
  /// change needs no new view model — [_shown] slices.
  int get _rowLimit =>
      widget.narrow ? kBillingPipelineNarrowRows : kDensePanelRows;

  /// Rows on screen.
  int _shown(BuildContext context) => widget.narrow
      ? kBillingPipelineNarrowRows
      : billingPipelineWideRows(context);

  BillingPipelineViewModel _buildVm() {
    final registry = _services.entityRegistry;
    _tabs = billingStatusTabsFor(
      invoiceModes:
          registry[EntityType.invoice]?.badgeModes ?? kDefaultBadgeModes,
      quoteModes: registry[EntityType.quote]?.badgeModes ?? kDefaultBadgeModes,
      includeInvoices: widget._invoices,
      includeQuotes: !widget._invoices,
    );
    _watchOccasionalTabs();
    // A stored tab this company can no longer use — quotes module switched off,
    // `view_quote` revoked, a mode retired — degrades to `All`. Without the
    // heal the strip shows nothing selected and the view model subscribes to a
    // tab with no participating halves.
    final initial = billingStatusTabById(_tabs, widget.initialTabId);
    return BillingPipelineViewModel(
      invoices: _services.invoices,
      quotes: _services.quotes,
      companyId: widget.companyId,
      includeInvoices: widget._invoices,
      includeQuotes: !widget._invoices,
      tabs: _tabs,
      rowLimit: _rowLimit,
      initialTab: initial,
      // Read lazily, and only for a paid invoice row: "Paid Nov 16".
      paidOnLookup: !widget._invoices
          ? null
          : (id) => latestPaymentDate(
              _services.payments,
              companyId: widget.companyId,
              invoiceId: id,
            ),
    );
  }

  /// Live counts of the tabs in [kOccasionalBillingTabs], which the strip
  /// shows only while they hold something.
  final Map<String, int> _occasionalCounts = {};
  final List<StreamSubscription<int>> _occasionalSubs = [];

  void _watchOccasionalTabs() {
    for (final sub in _occasionalSubs) {
      unawaited(sub.cancel());
    }
    _occasionalSubs.clear();
    _occasionalCounts.clear();
    for (final tab in _tabs) {
      if (!kOccasionalBillingTabs.contains(tab.id)) continue;
      _occasionalSubs.add(
        _countStream(tab).listen((n) {
          if (!mounted || _occasionalCounts[tab.id] == n) return;
          setState(() => _occasionalCounts[tab.id] = n);
        }, onError: (Object _) {}),
      );
    }
  }

  /// The strip's tabs: every tab but an occasional one with nothing in it —
  /// unless it is the selected tab, which never vanishes from under the user
  /// (a restored `expired`, or the count dropping to zero while it is open).
  List<BillingStatusTab> _visibleTabs() {
    final selected = _vm.tab?.id;
    return [
      for (final t in _tabs)
        if (!kOccasionalBillingTabs.contains(t.id) ||
            t.id == selected ||
            (_occasionalCounts[t.id] ?? 0) > 0)
          t,
    ];
  }

  @override
  void didUpdateWidget(covariant DashboardBillingPipelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.formatter != widget.formatter ||
        oldWidget.entity != widget.entity ||
        oldWidget.narrow != widget.narrow) {
      // A company switch usually tears this subtree down, but not when the new
      // company's formatter is already cached — then only this runs. (The wide
      // grid's `GlobalKey`s also carry this State between cells.) The tap
      // latch belongs to the company it was made in: left set, it would skip
      // the new company's late-restored tab below.
      if (oldWidget.companyId != widget.companyId) _userPicked = false;
      _vm.dispose();
      _vm = _buildVm();
    } else if (oldWidget.initialTabId == null &&
        widget.initialTabId != null &&
        !_userPicked) {
      // The restored tab arriving late, which is the ONLY ordering production
      // produces: the dashboard body mounts as soon as its formatter resolves
      // — a microtask on a warm navigation — while the `nav_state` read that
      // fills the saved tab is still in flight and never notifies on its own.
      // Reading `initialTabId` in `initState` alone therefore drops it every
      // time, making the persisted tab write-only.
      final restored = billingStatusTabById(_tabs, widget.initialTabId);
      if (restored != null) _vm.selectTab(restored);
    } else if (oldWidget.refreshNonce != null &&
        oldWidget.refreshNonce != widget.refreshNonce) {
      // `null` → the first stamp is the dashboard's initial load completing,
      // not a refresh, and it carries no invoice/quote data. Re-arming on it
      // would make every cold start fetch twice.
      _vm.invalidateLoadedTabs();
      unawaited(_vm.ensureTabLoaded());
    }
  }

  @override
  void dispose() {
    for (final sub in _occasionalSubs) {
      unawaited(sub.cancel());
    }
    _vm.dispose();
    super.dispose();
  }

  // Both destinations are spelled once, here, rather than handed down from two
  // hosts as callbacks — the same choice `DashboardTaskCalendarCard` makes.
  void _openRecord(BillingPipelineRow row) =>
      goEntityRecord(context, row.type, row.id);

  /// Open a list on the same bucket the panel is showing.
  ///
  /// `badge_mode` is the list's own local-first filter key, and
  /// `GenericListViewModel._applyIntentState` already sanitizes an unknown one
  /// — it was written anticipating this producer.
  void _openList(String? modeId) {
    final path = widget._invoices ? '/invoices' : '/quotes';
    final narrowed = modeId != null && modeId != kBadgeModeTotal;
    context.go(
      path,
      extra: narrowed
          ? ListFilterIntent(
              extraFilters: {
                kBadgeModeFilterKey: {modeId},
              },
            )
          : ListFilterIntent(),
    );
  }

  void _onTapTab(BillingStatusTab tab) {
    _userPicked = true;
    _vm.selectTab(tab);
    // Only a user gesture persists — see [onTabChanged].
    widget.onTabChanged(tab.isAll ? null : tab.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    if (_tabs.isEmpty) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final tab = _vm.tab;
    final modeId = widget._invoices ? tab?.invoiceModeId : tab?.quoteModeId;
    final centred =
        DashboardPanelCell.stretchedOf(context) &&
        _vm.firstLoadResolved &&
        _vm.rows.isEmpty;
    return DashboardCardShell(
      title: context.tr(widget._invoices ? 'invoices' : 'quotes'),
      // One destination — the list, on the tab the strip shows.
      trailing: DashboardCardFooterLink(
        label: context.tr('view_all'),
        onTap: () => _openList(modeId),
      ),
      onHeaderTap: Env.isTouchPrimary ? () => _openList(modeId) : null,
      // Edge-flush, like `DashboardListCard`: the strip's bottom rule and the
      // rows' hairlines reach both borders.
      padding: EdgeInsets.zero,
      // Beside a taller neighbour the card is stretched to its height; an
      // empty or failed tab then centres its line in the space below the
      // strip instead of leaving a hollow box under it.
      bodyFills: centred,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _strip(context),
          if (centred)
            Expanded(child: _body(context, tab))
          else
            _body(context, tab),
        ],
      ),
    );
  }

  Widget _strip(BuildContext context) {
    final selected = _vm.tab;
    final tabs = _visibleTabs();
    final index = selected == null
        ? 0
        : tabs.indexWhere((t) => t.id == selected.id);
    // The strip speaks `ResolvedStatusTab`; the panel speaks
    // `BillingStatusTab`. The adapter is keyed on `countModeId` — NOT
    // `listModeId`, which is null for `All` — and resolving back through it is
    // what keeps a merged tab's per-entity ids explicit.
    final byCountMode = <String, BillingStatusTab>{
      for (final t in _tabs) t.mode?.id ?? kBadgeModeTotal: t,
    };
    final resolved = [
      for (final t in tabs)
        ResolvedStatusTab(t.mode, const <String, Set<String>>{}),
    ];
    return EntityListStatusTabs(
      tabs: resolved,
      selectedIndex: index,
      // Badges wait for the first fetch: a Drift watch emits within a frame, so
      // without this the panel's opening frame is seven confident zeroes.
      showCounts: _vm.firstLoadResolved,
      // Encodes which halves participate — the strip caches one stream per tab
      // on this key alone, so a module change must not reuse stale counts.
      streamKey: 'pipeline:${widget.entity.name}:${widget.companyId}',
      countStream: (modeId) => _countStream(byCountMode[modeId]),
      onTap: (t) {
        final match = byCountMode[t.countModeId];
        if (match != null) _onTapTab(match);
      },
      wrap: true,
      // Compact takes the list strip's own dense form, and the padding
      // around it closes up to match (`docs/list-density.md` § The dashboard).
      dense: dashboardDense(context),
      contentPadding: EdgeInsetsDirectional.fromSTEB(
        InSpacing.lg(context),
        dashboardDense(context) ? InSpacing.sm : InSpacing.md(context),
        InSpacing.lg(context),
        dashboardDense(context) ? InSpacing.sm : InSpacing.md(context),
      ),
    );
  }

  /// One tab's count.
  ///
  /// **Never forwards a mode this entity doesn't declare.** `watchBadgeCount`
  /// does `if (extra != null) q.where(extra)`, so a mode a DAO does not
  /// recognise skips the WHERE and counts *every active row*; a tab's
  /// per-entity id is null exactly when the entity has no such mode.
  Stream<int> _countStream(BillingStatusTab? tab) {
    final modeId = widget._invoices ? tab?.invoiceModeId : tab?.quoteModeId;
    if (modeId == null) return Stream<int>.value(0);
    return _services.watchEntityCount(
      widget.entity,
      widget.companyId,
      modeId: modeId,
    );
  }

  Widget _body(BuildContext context, BillingStatusTab? tab) {
    final shown = _shown(context);
    final rows = _vm.rows.take(shown).toList();
    // A floor, never a fixed height: a fixed one clamps the line box and slices
    // Inter Tight's descenders past ~1.14x text scale. Sized for a FULL tab so
    // the card is stable in both directions — in the wide grid a growing body
    // resizes the card beside it, and on mobile everything below it slides.
    final floor =
        shown *
        dashboardRecordRowExtent(
          compact: widget.narrow,
          dense: dashboardDense(context),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: floor),
      child: _bodyContent(context, rows, tab),
    );
  }

  Widget _bodyContent(
    BuildContext context,
    List<BillingPipelineRow> rows,
    BillingStatusTab? tab,
  ) {
    if (!_vm.firstLoadResolved && rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(InSpacing.lg(context)),
        child: ListCardSkeleton(rowCount: _shown(context)),
      );
    }
    if (rows.isEmpty && _vm.tabLoadFailed) return _failed(context);
    if (rows.isEmpty) return _empty(context);
    // On a status tab every row has that status, so a pill on each would
    // repeat the selected tab; `All` mixes them and needs it.
    final pills = tab?.isAll ?? true;
    // The device's own day: "due in 3 days" is about the day the user is in.
    final today = Date.today();
    return DashboardRecordRows(
      rows: [
        for (final row in rows)
          _PipelineRow(
            key: ValueKey('${row.type.name}:${row.id}'),
            row: row,
            formatter: widget.formatter,
            compact: widget.narrow,
            pill: pills,
            today: today,
            paidOn: row.isPaid ? _vm.paidOn(row.id) : null,
            onTap: () => _openRecord(row),
          ),
      ],
    );
  }

  /// The tab's fetch failed and nothing is cached for it: unknown, not empty.
  Widget _failed(BuildContext context) {
    final tokens = context.inTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: InSpacing.lg(context)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 18, color: tokens.overdue),
          const SizedBox(width: InSpacing.sm),
          Flexible(
            child: Text(
              context.tr('could_not_load_label'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.ink2, fontSize: 13),
            ),
          ),
          const SizedBox(width: InSpacing.sm),
          TextButton(onPressed: _vm.retry, child: Text(context.tr('retry'))),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final tokens = context.inTheme;
    final tab = _vm.tab;
    // `Rejected` is local-only until the server grows a `client_status=rejected`
    // branch (BACKEND.md § F1), so its empty state must not claim absence — the
    // caveat and the sentence both render, because "Rejected 0 over nothing" is
    // exactly the state the caveat exists for.
    final isLocalOnly = tab?.isLocalOnly ?? false;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: InSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // `_body` reserves `rowLimit * rowHeight` so the card cannot resize on
        // a tab switch, and `RenderFlex` honours that `minHeight` whatever the
        // `mainAxisSize` — so without this the message sits at the top of a
        // ~190 px box with the rest of the reserved space empty beneath it.
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.tr(isLocalOnly ? 'none_synced_yet' : 'no_records_found'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: tokens.ink2),
          ),
          if (isLocalOnly) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('counted_from_local_data'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: tokens.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

/// One document as a [DashboardRecordRow]: number, client, its date with how
/// near its deadline is, its status pill (on `All`), and the amount in the
/// client's currency with the company-currency estimate under a foreign one.
class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    super.key,
    required this.row,
    required this.formatter,
    required this.compact,
    required this.pill,
    required this.today,
    required this.onTap,
    this.paidOn,
  });

  final BillingPipelineRow row;
  final Formatter formatter;
  final bool compact;
  final bool pill;
  final Date today;
  final VoidCallback onTap;

  /// When a paid invoice was paid, if the device knows.
  final Date? paidOn;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final pillStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: tokens.ink,
    );
    final date = row.date;
    // Near or late only, and nothing on a closed document — `openDeadline` is
    // null for a draft, a paid invoice or a quote no longer out.
    final when = row.type == EntityType.invoice
        ? invoiceRowWhen(due: row.openDeadline, today: today)
        : quoteRowWhen(validUntil: row.openDeadline, today: today);
    return PartyCurrencyBuilder(
      clientId: row.clientId,
      builder: (context, currencyId) => DashboardRecordRow(
        number: row.number,
        client: '',
        // `link: false` is the default: the whole row is one destination.
        clientLabel: ClientNameLabel(clientId: row.clientId),
        badge: !pill
            ? null
            : row.type == EntityType.invoice
            ? InvoiceStatusPill(
                statusId: row.statusId,
                dotSize: 6,
                textStyle: pillStyle,
                hasBounce: row.hasBounce,
              )
            : QuoteStatusPill(
                statusId: row.statusId,
                dotSize: 6,
                textStyle: pillStyle,
                hasBounce: row.hasBounce,
              ),
        lead: pipelineRowLead(
          context,
          formatter: formatter,
          type: row.type,
          date: date is Date ? date : null,
          openDeadline: row.openDeadline,
          paidOn: row.isPaid ? paidOn : null,
          today: today,
        ),
        subline: when == null ? null : rowWhenText(context, when),
        sublineIsLate: when?.isLate ?? false,
        amount: formatter.money(
          row.amount as Decimal,
          clientCurrencyId: currencyId,
        ),
        amountNote: compact
            ? null
            : approxInBaseCurrency(
                formatter: formatter,
                amount: row.amount as Decimal,
                documentCurrencyId: currencyId,
                exchangeRate: row.exchangeRate ?? Decimal.zero,
              ),
        onTap: onTap,
        compact: compact,
      ),
    );
  }
}

/// What an Invoices / Quotes panel row's date slot says.
///
/// * An open invoice — sent with something still owed — its deadline: "Due Dec
///   17" (the deposit's due date while one is asked for, the date the late
///   sub-line counts from).
/// * A paid invoice whose payment date is on the device: "Paid Nov 16".
/// * A quote out with the client: "Valid until Dec 14" (`valid_until_date_label`,
///   the quotes list's own wording).
/// * Anything else — a draft, a cancelled invoice, an open one with no due
///   date, a paid one whose payments the device has not synced — the
///   document's date, as before.
///
/// The date is short ("Dec 17", the company's locale) within the current year
/// and the company's full format outside it, where a bare "Dec 17" would not
/// say which December.
@visibleForTesting
String pipelineRowLead(
  BuildContext context, {
  required Formatter formatter,
  required EntityType type,
  required Date? date,
  required Date? openDeadline,
  required Date? paidOn,
  required Date today,
}) {
  String fmt(Date d) => d.year == today.year
      ? formatter.dateShort(d.toIso())
      : formatter.date(d.toIso());
  if (openDeadline != null) {
    return context.tr(
      type == EntityType.invoice
          ? 'due_on_date_label'
          : 'valid_until_date_label',
      {'date': fmt(openDeadline)},
    );
  }
  if (paidOn != null) {
    return context.tr('paid_on_date_label', {'date': fmt(paidOn)});
  }
  return date == null ? '' : formatter.date(date.toIso());
}
