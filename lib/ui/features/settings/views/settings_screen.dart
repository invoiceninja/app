import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/search_focus_registry.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/plan_gate.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/widgets/watch_builder.dart';
import 'package:admin/ui/features/settings/settings_search_catalog.dart';
import 'package:admin/ui/features/settings/widgets/card_reader_section.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/state/settings_search_controller.dart';
import 'package:admin/ui/features/settings/view_models/settings_home_summary_view_model.dart';
import 'package:admin/ui/features/settings/views/settings_shell.dart'
    show hideSettingsListSidebar;
import 'package:admin/ui/features/settings/widgets/settings_search_result.dart';
import 'package:admin/ui/features/settings/widgets/settings_tab_strip.dart';
import 'package:admin/ui/features/settings/widgets/settings_two_pane_scope.dart';
import 'package:admin/ui/features/shell/widgets/app_drawer.dart';
import 'package:admin/ui/features/shell/widgets/company_avatar.dart';
import 'package:admin/ui/features/shell/widgets/show_company_picker.dart';
import 'package:admin/ui/core/utils/router_state.dart';
import 'package:admin/ui/features/settings/views/basic/account_management/plan_screen.dart';

// `PlanTier` (the tier surfaced on a locked sidebar row / search hit) now
// comes from `package:admin/domain/plan_gate.dart` — imported above.

/// The rule under the wide settings nav's title + search block — keyed so a
/// test can measure it against the rule under a page's tab strip.
const kSettingsNavRuleKey = ValueKey('settings-nav-rule');

/// Master list of settings sections — pure list, no `Scaffold`. Used as the
/// left pane on wide screens (mounted by `SettingsShell`) and as the body of
/// `SettingsScreen` on narrow screens. Reads the current go_router location
/// to highlight whichever top-level section is active.
///
/// Tapping the search affordance swaps the section list for a flat list of
/// matching fields drawn from `kSettingsSearchCatalog`. **Where that
/// affordance lives depends on who owns the state** — see [searchController].
class SettingsListSidebar extends StatefulWidget {
  const SettingsListSidebar({super.key, this.searchController, this.summary});

  /// Search state owned by the **host** — non-null only when that host also
  /// renders the trigger and the text field. Today that is [SettingsScreen],
  /// which pins both in its AppBar so they can't scroll away (issue #42), and
  /// this widget renders only the section list / results.
  ///
  /// Leave null — the wide 280 px pane, which has no AppBar of its own — and
  /// this widget owns the state *and* the affordance: a "Settings" title row
  /// carrying the search icon, pinned above the scroll area, plus the field row
  /// that replaces the pane while searching. Those go together on purpose: the
  /// controller is the ownership token, so there is exactly one trigger and
  /// exactly one field at any width.
  final SettingsSearchController? searchController;

  /// The phone home's current values (R1) — passed only by [SettingsScreen].
  /// The wide pane is a nav beside the page that shows the values itself, so
  /// it never draws them, and neither do search hits.
  final SettingsHomeSummaryViewModel? summary;

  @override
  State<SettingsListSidebar> createState() => _SettingsListSidebarState();
}

class _SettingsListSidebarState extends State<SettingsListSidebar> {
  /// Non-null only when no host supplied one. Never dispose the host's.
  SettingsSearchController? _own;

  SettingsSearchController get _search => widget.searchController ?? _own!;
  bool get _hostOwned => widget.searchController != null;

  /// Held only while this pane owns its search — see [didChangeDependencies].
  SearchFocusRegistry? _searchFocus;

  @override
  void initState() {
    super.initState();
    if (widget.searchController == null) {
      // The wide pane's field is always on screen, so focusing it — a click,
      // Tab, `/` — is what opens the search.
      _own = SettingsSearchController()..focus.addListener(_onOwnFocus);
      // And typing into it after Esc / ✕ closed it (focus never left).
      _own!.query.addListener(_onOwnFocus);
    }
    _search.onSubmit = _openSelected;
  }

  void _onOwnFocus() {
    final own = _own;
    if (own == null || own.isActive) return;
    if (own.focus.hasFocus || own.query.text.isNotEmpty) own.open();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The wide pane owns its search, so it answers `/` too. Claimed only while
    // on stage — go_router keeps the settings branch mounted behind every
    // other one — exactly as `TokenSearchField` claims (see
    // `SearchFocusRegistry`). A host-owned controller is claimed by its host.
    final own = _own;
    if (own == null) return;
    _searchFocus ??= context.read<Services>().searchFocus;
    // A fallback: a list's own search field in the pane beside this one
    // (Payment Links) is what `/` should reach while it is on screen.
    if (TickerMode.valuesOf(context).enabled) {
      _searchFocus!.claim(
        own.focus,
        onActivate: _activateOwnSearch,
        fallback: true,
      );
    } else {
      _searchFocus!.release(own.focus);
    }
  }

  void _activateOwnSearch() {
    // The custom-design editor slides this pane off to zero width; opening a
    // search nobody can see would only steal the keyboard.
    if (hideSettingsListSidebar.value) return;
    _search.activate();
  }

  @override
  void dispose() {
    final own = _own;
    if (own != null) _searchFocus?.release(own.focus);
    if (_search.onSubmit == _openSelected) _search.onSubmit = null;
    own?.focus.removeListener(_onOwnFocus);
    own?.query.removeListener(_onOwnFocus);
    // Only what we created — the host disposes what it created, matching how
    // `TextField` treats a passed-in controller.
    own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final body = ListenableBuilder(
      // The summary only notifies when a value it reads changed (a stream
      // answered), never per keystroke.
      listenable: summary == null
          ? _search
          : Listenable.merge([_search, summary]),
      builder: (context, _) =>
          _search.isActive ? _buildSearch(context) : _buildSectionList(context),
    );
    if (_hostOwned) return body;
    // Self-owned (the wide pane): the field itself is pinned above the scroll
    // area, always visible — a search box people can see is one they use, and
    // pinned it stays reachable at any scroll position (issue #42 in the
    // layout that has no AppBar to host it). It is built once, outside the
    // builder that swaps the list for results, so typing never re-mounts it
    // and focus stays put.
    //
    // The screen title rides along, in the AppBar's title style — so both
    // widths open on the same "Settings" heading. A *group* label would not
    // belong up here: the strip is pinned, so hoisting "Basic Settings" would
    // leave it claiming that half while the user has scrolled into Advanced.
    // Every group header stays inside the list, exactly as on narrow.
    //
    // The block is exactly as tall as a page's header beside it — title row
    // = the page's toolbar, search row = its tab strip — so this rule and the
    // one under the page's tabs are one line across the window, and the two
    // titles share a centre line. Both come from `kSettingsHeaderHeight`; a
    // padding tweak here would drift again. The page's AppBar also takes the
    // top inset (a tablet's status bar), so this block does too.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top),
        SizedBox(
          height: kSettingsTitleBarHeight,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.tr('settings'),
                style: Theme.of(context).appBarTheme.titleTextStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        SizedBox(
          // The strip's height includes its hairline; here the hairline is
          // the divider below.
          height: kSettingsTabStripHeight - 1,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: SettingsSearchField(
                    controller: _search,
                    fitsRow: true,
                  ),
                ),
                ListenableBuilder(
                  listenable: _search,
                  // Close only while searching; the slot is kept so the field
                  // doesn't change width as the search opens.
                  builder: (context, _) => _search.isActive
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: context.tr('cancel'),
                          onPressed: _search.close,
                        )
                      : const SizedBox(width: 8),
                ),
              ],
            ),
          ),
        ),
        const Divider(key: kSettingsNavRuleKey, height: 1),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildSectionList(BuildContext context) {
    final activeSlug = _activeSlug(routerStateOf(context).uri.path);
    // Group and client are both non-company cascade levels — they show the
    // same overridable (cascade-aware) sections, hiding company-only ones.
    final settingsLevel = context.watch<SettingsLevelController>();
    final isCascade = settingsLevel.isClient || settingsLevel.isGroup;
    // Listen to session so the lock icons appear / disappear when a fresh
    // refresh lands (e.g. after the user upgrades in the portal and lands
    // back in the app), and so module-gated sections drop out reactively
    // when the company toggles a module. Only the list body wraps — search
    // state lives above this builder.
    return ValueListenableBuilder<AuthSession?>(
      valueListenable: context.read<Services>().auth.session,
      builder: (context, session, _) {
        final modules = session?.currentCompany?.enabledModules ?? 0;
        final me = session?.currentCompany;
        final isAdminOrOwner = me?.isAdmin == true || me?.isOwner == true;
        bool inScope(SettingsSectionDef s) =>
            (!isCascade || s.clientEditable) &&
            s.isVisibleFor(modules) &&
            (!s.adminOnly || isAdminOrOwner);
        // Basic / Advanced, as in the React app, each listing its sections in
        // catalog order. A group whose every section is out of scope draws no
        // header at all.
        final groups = [
          for (final g in SettingsGroup.values)
            (
              group: g,
              sections: [
                for (final s in kSettingsSections)
                  if (s.group == g && inScope(s)) s,
              ],
            ),
        ].where((g) => g.sections.isNotEmpty).toList();
        // Values only on the phone home, only at company scope: at client or
        // group scope a row's value would be the company's, not the one the
        // page opens on.
        final summary = _hostOwned && settingsLevel.isCompany
            ? widget.summary
            : null;
        return ListView(
          addAutomaticKeepAlives: false,
          children: [
            // The narrow index only (the wide layout has the rail's switcher
            // beside it): which company — and, scoped, which client or group
            // — these settings belong to, and the way to another one. Not
            // while searching: the results own the list then.
            if (_hostOwned && !_search.isActive && me != null)
              _CompanyCard(
                companyId: me.id,
                name: me.displayName,
                logoUrl: me.logoUrl,
                level: settingsLevel,
              ),
            // No `trailing:` at either width — the trigger is pinned in the
            // chrome above (the AppBar on narrow, a strip on the wide pane).
            // An in-list copy would be a second trigger that scrolls away, and
            // that IS issue #42.
            //
            // The phone home draws each group as one inset card under a muted
            // label (R of the settings pass); the wide nav keeps flat rows,
            // the selected one tinted, beside the page they open.
            for (final (i, g) in groups.indexed)
              if (_hostOwned)
                _SettingsHomeGroup(
                  label: context.tr(g.group.labelKey),
                  rows: [
                    for (final s in g.sections)
                      _homeRow(context, s, session, summary: summary),
                  ],
                )
              else ...[
                if (i > 0) const Divider(height: 1),
                _GroupHeader(context.tr(g.group.labelKey)),
                for (final s in g.sections)
                  _tile(context, s, activeSlug, session),
              ],
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Widget _buildSearch(BuildContext context) {
    // Rebuild results on company switch so a now-disabled section drops
    // out of an open search without the user having to retype.
    final services = context.read<Services>();
    final results = ValueListenableBuilder<AuthSession?>(
      valueListenable: services.auth.session,
      // The active company's record, for the one gate the session can't
      // answer (Hide Peppol Sent Status) — see [_company].
      builder: (context, session, _) => WatchBuilder<Company?>(
        cacheKey: session?.currentCompanyId,
        create: () =>
            services.company.watchCompany(session?.currentCompanyId ?? ''),
        builder: (context, companySnap) {
          _company = companySnap.data;
          // The active gateway count, which decides the Payment Settings
          // row's label (Company Gateways or Add Payment Gateway).
          return WatchBuilder<int>(
            cacheKey: session?.currentCompanyId,
            create: () =>
                (Provider.of<SettingsHomeSources?>(context, listen: false) ??
                        SettingsHomeSources.of(services))
                    .gatewayCount(session?.currentCompanyId ?? ''),
            builder: (context, gatewaySnap) {
              _activeGateways = gatewaySnap.data;
              return ListenableBuilder(
                // The query is its own `Listenable`, so a keystroke rebuilds
                // the hit list and nothing else. The old `onChanged:
                // setState` rebuilt this whole pane — host-side it would have
                // rebuilt the AppBar per character.
                listenable: _search.query,
                builder: (context, _) =>
                    _buildResults(context, Localization.of(context)),
              );
            },
          );
        },
      ),
    );
    // Whoever owns the field (the host's AppBar, or this pane's pinned
    // header) renders it, so results are all that's left for the body.
    return results;
  }

  /// The rows for the current query, filtered to what this user can open.
  List<SettingsSearchHit> _hitsFor(Localization l10n) => searchSettings(
    _search.query.text,
    l10n,
    scope: SettingsSearchScope.from(
      context.read<Services>().auth.session.value,
      context.read<SettingsLevelController>(),
      company: _company,
      serverVersion: context.read<Services>().serverVersion.value,
      activeGatewayCount: _activeGateways,
      showsChangePlan: changePlanCardShown(
        context,
        context.read<Services>().auth.session.value,
      ),
      showsCardReaders: cardReaderSectionAnswered(context.read<Services>()),
    ),
  );

  /// The active company's latest record, kept by [_buildSearch] so Enter
  /// ([_openSelected]) ranks the same rows the list shows. Null until it
  /// loads, which the scope reads as "fail open".
  Company? _company;

  /// The active company's active gateways, kept beside [_company]; null until
  /// Drift answers.
  int? _activeGateways;

  Widget _buildResults(BuildContext context, Localization? l10n) {
    if (l10n == null) return const SizedBox.shrink();
    // Nothing typed yet: the sections themselves are the most useful list —
    // the old resting state was every field in the catalog, hundreds of rows.
    if (_search.query.text.trim().isEmpty) {
      _search.resultCount = 0;
      return _buildSectionList(context);
    }
    final session = context.read<Services>().auth.session.value;
    // Filtered at query time — not by trimming the catalog — so a gated
    // section or tab never surfaces as a dead link, while
    // `kSettingsSearchCatalog` stays complete for the consistency tests.
    // `SettingsSearchScope` is the one copy of that rule; the command palette
    // reads the same one.
    final hits = _hitsFor(l10n);
    _search.resultCount = hits.length;
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('no_results'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    final tokens = context.inTheme;
    final query = _search.query.text;
    return ValueListenableBuilder<int>(
      valueListenable: _search.selected,
      builder: (context, selected, _) {
        final sel = selected.clamp(0, hits.length - 1);
        _revealSelectedRow();
        return ListView.builder(
          addAutomaticKeepAlives: false,
          itemCount: hits.length,
          itemBuilder: (context, i) {
            final hit = hits[i];
            final gate = _gateLevelFor(hit.section.slug, session);
            return ListTile(
              key: i == sel ? _selectedRowKey : null,
              leading: Icon(hit.section.icon),
              title: Text.rich(
                // No base style: the span inherits the tile's own text style
                // and colour, so the selected row's title turns `accentInk`
                // with its icon.
                highlightedMatch(l10n.lookup(hit.fieldKey), query),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                settingsHitSubtitle(hit, l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Same compact gate affordance the sidebar `_tile` uses — a wide
              // "Pro"/"Enterprise" text chip here overflows the ~232 px
              // settings sidebar (RenderFlex overflowed on the right).
              trailing: gate == null ? null : _PlanLock(gate),
              // The keyboard selection. Enter opens this row; on touch it is
              // only ever the first row, which Enter on the soft keyboard
              // opens too.
              selected: i == sel,
              selectedTileColor: tokens.accentSoft,
              selectedColor: tokens.accentInk,
              iconColor: tokens.ink3,
              textColor: tokens.ink2,
              onTap: () => _openHit(hit),
            );
          },
        );
      },
    );
  }

  /// On the selected row only, so ↑ / ↓ can follow it off-screen.
  final GlobalKey _selectedRowKey = GlobalKey();

  void _revealSelectedRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _selectedRowKey.currentContext;
      if (row == null) return;
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 120),
      );
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: const Duration(milliseconds: 120),
      );
    });
  }

  /// Enter in the field: the keyboard-selected row, which is the first one
  /// until ↑ / ↓ moves it.
  void _openSelected() {
    final l10n = Localization.of(context);
    if (l10n == null || _search.query.text.trim().isEmpty) return;
    final hits = _hitsFor(l10n);
    if (hits.isEmpty) return;
    unawaited(_openHit(hits[_search.selected.value.clamp(0, hits.length - 1)]));
  }

  Future<void> _openHit(SettingsSearchHit hit) async {
    if (!await _confirmIfDirty(context)) return;
    if (!mounted) return;
    openSettingsSearchHit(context, hit);
    _search.close();
  }

  Future<bool> _confirmIfDirty(BuildContext context) {
    return context.read<Services>().unsavedChangesGuard.confirmIfDirty(context);
  }

  /// A row of the wide settings nav: the main sidebar's row size, the open
  /// section tinted.
  Widget _tile(
    BuildContext context,
    SettingsSectionDef section,
    String? activeSlug,
    AuthSession? session,
  ) {
    final tokens = context.inTheme;
    final selected = section.slug == activeSlug;
    final gate = _gateLevelFor(section.slug, session);
    return ListTile(
      // The size of the main sidebar's rows: 14 px, 20 px icons and, with a
      // pointer, a dense row. At 16 px in 56 px rows the settings list read
      // as another app beside the sidebar it opens from. Touch keeps the
      // full row for the finger.
      dense: !Env.isTouchPrimary,
      visualDensity: Env.isTouchPrimary ? null : VisualDensity.compact,
      minLeadingWidth: 24,
      titleTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      leading: Icon(section.icon, size: 20),
      title: Text(context.tr(section.titleKey)),
      trailing: gate == null ? null : _PlanLock(gate),
      selected: selected,
      selectedTileColor: tokens.accentSoft,
      // Drives both leading icon + title color when `selected` is true.
      // Matches the SidebarNavItem active-state pattern.
      selectedColor: tokens.accentInk,
      iconColor: tokens.ink3,
      textColor: tokens.ink2,
      onTap: () => unawaited(_openSection(context, section)),
    );
  }

  /// A row of the phone settings home's grouped cards, carrying the
  /// section's current value (R1) when [summary] is given.
  Widget _homeRow(
    BuildContext context,
    SettingsSectionDef section,
    AuthSession? session, {
    SettingsHomeSummaryViewModel? summary,
  }) {
    final gate = _gateLevelFor(section.slug, session);
    // The plan-gate lock wins: a locked page's value is not one the user can
    // act on.
    final value = gate != null || summary == null
        ? null
        : summary.valueFor(
            section.slug,
            tr: context.tr,
            session: session,
            rtl: Directionality.of(context) == TextDirection.rtl,
          );
    return _SettingsHomeRow(
      key: ValueKey('settings-home-row-${section.slug}'),
      icon: section.icon,
      title: context.tr(section.titleKey),
      subtitle: value?.text,
      trailing: gate != null
          ? _PlanLock(gate)
          : _SettingsHomeTrailing.maybe(value),
      onTap: () => unawaited(_openSection(context, section)),
    );
  }

  Future<void> _openSection(
    BuildContext context,
    SettingsSectionDef section,
  ) async {
    if (!await _confirmIfDirty(context)) return;
    if (!context.mounted) return;
    context.go(section.route);
    // An open search with nothing typed lists the sections too; picking
    // one is the end of that search.
    _search.close();
  }

  /// Decides whether to render a trailing lock icon on a sidebar / search row.
  /// Returns the gate tier when the active session lacks access, null when
  /// the section is ungated or the user already qualifies (incl. self-hosted).
  static PlanTier? _gateLevelFor(String slug, AuthSession? session) =>
      planGateFor(session, settingsSlug: slug);

  /// Extract the top-level section slug from a path like
  /// `/settings/user_details/preferences` → `user_details`. Returns null when
  /// the user is on `/settings` itself (no section selected).
  static String? _activeSlug(String path) {
    if (!path.startsWith('/settings')) return null;
    final rest = path.substring('/settings'.length);
    if (rest.isEmpty || rest == '/') return null;
    final segments = rest.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? null : segments.first;
  }
}

/// The settings search input. Shared so the AppBar-hosted (narrow) copy and
/// the in-pane (wide) copy can't drift apart.
class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.controller,
    this.fitsRow = false,
  });

  final SettingsSearchController controller;

  /// The wide pane's copy, which sits in a row one hairline short of a tab
  /// strip ([kSettingsTabStripHeight]): its prefix icon is capped so the field
  /// is 40 px with a pointer and [InSizes.touchTarget] on touch, never the
  /// 48 px the icon's minimum otherwise forces at standard density.
  final bool fitsRow;

  @override
  Widget build(BuildContext context) {
    // A floor, not a fixed height. The `prefixIcon` alone gives this field a
    // 48 px intrinsic height (icon minimums don't shrink with
    // `contentPadding: vertical: 0`), so pinning the box to 40 clipped it
    // silently at every text scale. Same reason the narrow copy hangs in the
    // AppBar's 56 px `bottom:` rather than its `title:` slot, which clamps to
    // `kToolbarHeight` and would re-create exactly that clipping.
    // ↑ / ↓ walk the results and Esc closes, as in the command palette.
    // Bound on the field itself, so they only act while it has focus — a bare
    // arrow anywhere else on the page stays the page's.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            controller.moveSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            controller.moveSelection(-1),
        const SingleActivator(LogicalKeyboardKey.escape): controller.close,
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: TextField(
          controller: controller.query,
          focusNode: controller.focus,
          // Search queries are names and numbers, not prose — iOS
          // autocorrecting "Acme" to "Acne" mid-search is the failure.
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.search,
          // Enter opens the selected row. Keep focus here rather than take the
          // default blur: the hit navigates and closes the search, and a blur
          // first would park focus on the scope (docs/keyboard.md).
          onSubmitted: (_) => controller.submit(),
          onEditingComplete: () {},
          decoration: InputDecoration(
            hintText: context.tr('search_settings'),
            prefixIcon: const Icon(Icons.search, size: 20),
            prefixIconConstraints: fitsRow
                ? BoxConstraints(
                    minWidth: 40,
                    minHeight: Env.isTouchPrimary ? InSizes.touchTarget : 40,
                  )
                : null,
            filled: true,
            border: InFieldOutlineBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Narrow-only route target for `/settings`. On wide screens the shell shows
/// `SettingsListSidebar` directly in the left pane, so this screen never gets
/// rendered — but it remains the route's `builder` so the back-button on
/// narrow lands on the list cleanly.
///
/// Owns the search chrome: the field, always visible, in the AppBar's 56 px
/// `bottom:` strip — the same shape as `EntityListAppBar`'s narrow layout, a
/// toolbar over a 56 px search row — and the close button in `actions:` while
/// a search is open. Neither may live in the scrolling body — that was issue
/// #42. Focusing the field (a tap, `/`) or typing into it opens the search,
/// exactly as on the wide pane.
///
/// Also owns the home's [SettingsHomeSummaryViewModel], keyed on the active
/// company, so each row can show its current value.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsSearchController _search = SettingsSearchController();
  SearchFocusRegistry? _searchFocus;

  ValueListenable<AuthSession?>? _session;
  SettingsHomeSources? _sources;
  SettingsHomeSummaryViewModel? _summary;

  @override
  void initState() {
    super.initState();
    // The field is always on screen, so focusing it is what opens the search
    // — and typing into it after ✕ closed it.
    _search.focus.addListener(_onFieldActivity);
    _search.query.addListener(_onFieldActivity);
  }

  void _onFieldActivity() {
    if (_search.isActive) return;
    if (_search.focus.hasFocus || _search.query.text.isNotEmpty) {
      _search.open();
    }
  }

  void _closeSearch() {
    _search.close();
    // Drop the caret too: on a phone that is what puts the keyboard away.
    _search.focus.unfocus();
  }

  /// One summary per company: a switch disposes the old one's streams.
  void _syncSummary() {
    final id = _session?.value?.currentCompanyId ?? '';
    if (id == (_summary?.companyId ?? '')) return;
    _summary?.dispose();
    _summary = id.isEmpty
        ? null
        : SettingsHomeSummaryViewModel(companyId: id, sources: _sources!);
  }

  void _onSession() {
    if (!mounted) return;
    setState(_syncSummary);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      final services = context.read<Services>();
      // A test supplies its own sources; production reads Services.
      _sources =
          Provider.of<SettingsHomeSources?>(context, listen: false) ??
          SettingsHomeSources.of(services);
      _session = services.auth.session..addListener(_onSession);
      _syncSummary();
    }
    // This screen owns the search chrome, so it answers `/`. On stage only:
    // a covered route (a section pushed over the index) and an inactive
    // branch both mute `TickerMode`, and a resize to two panes leaves this
    // screen mounted behind the wide pane, which then answers `/` itself.
    _searchFocus ??= context.read<Services>().searchFocus;
    if (TickerMode.valuesOf(context).enabled &&
        !SettingsTwoPaneScope.of(context)) {
      _searchFocus!.claim(
        _search.focus,
        onActivate: _search.activate,
        fallback: true,
      );
    } else {
      _searchFocus!.release(_search.focus);
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _summary?.dispose();
    _searchFocus?.release(_search.focus);
    _search.focus.removeListener(_onFieldActivity);
    _search.query.removeListener(_onFieldActivity);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final globalNav = Breakpoints.isGlobalNavVisible(context);
    // A resize past `Breakpoints.settingsTwoPane` leaves this screen mounted
    // but `Offstage` inside `SettingsShell`'s wide branch
    // (`HiddenShellNavigator`) — `settingsIndexRedirect` only runs on
    // *navigation*. Never intercept back from there: the pane's own sidebar is
    // what the user is looking at, and an invisible open search would swallow
    // the press.
    final twoPane = SettingsTwoPaneScope.of(context);
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) => PopScope(
        // Android convention: back collapses an open search before leaving the
        // screen. `canPop` is read at build time, which is safe here because
        // the flag is this screen's own state — a rebuild always precedes the
        // next press, unlike the navigation-lag cases `SystemBackGate` warns
        // about. When true, `Route.popDisposition` returns `bubble` (this
        // route is `isFirst` in the settings shell's navigator) and back falls
        // through to `SystemBackGate` exactly as it does today.
        //
        // This out-ranks an open `AppDrawer`'s `LocalHistoryEntry`:
        // `ModalRoute.popDisposition` checks `PopScope` entries before
        // `LocalHistoryRoute`'s. So back with both open closes search and
        // leaves the drawer up — contrived, and the drawer still has its scrim
        // and swipe, so it isn't worth an `onDrawerChanged` rebuild to chase.
        canPop: !(_search.isActive && !twoPane),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeSearch();
        },
        child: Scaffold(
          drawer: globalNav ? null : const AppDrawer(),
          appBar: AppBar(
            title: Text(context.tr('settings')),
            leading: globalNav ? null : const DrawerHamburger(),
            automaticallyImplyLeading: !globalNav,
            // The same shape as `EntityListAppBar`'s narrow chrome: the field
            // pinned in a 56 px row under the toolbar — always, because a
            // search box people can see is one they use (the wide pane's
            // rule). No `preferredSize` to keep in sync — this is a real
            // `AppBar`, so it derives `kToolbarHeight + 56` from `bottom`
            // itself. Don't wrap it in a custom `PreferredSizeWidget` unless,
            // like the list header, the row has to GROW: a settings search
            // field is one line, always.
            actions: [
              if (_search.isActive)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: context.tr('cancel'),
                  onPressed: _closeSearch,
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: SettingsSearchField(controller: _search),
              ),
            ),
          ),
          body: SettingsListSidebar(
            searchController: _search,
            summary: _summary,
          ),
        ),
      ),
    );
  }
}

/// The phone settings home's first row: the active company, opening the
/// existing [showCompanyPicker] (whose "New company" row is the only one —
/// this card adds none). At client / group scope its second line names that
/// scope instead of offering the switch, so the user sees whose settings the
/// list below will open.
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.companyId,
    required this.name,
    required this.logoUrl,
    required this.level,
  });

  final String companyId;
  final String name;
  final String? logoUrl;
  final SettingsLevelController level;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final scoped = !level.isCompany;
    final subtitle = scoped
        ? '${context.tr(level.isGroup ? 'group_settings' : 'client_settings')}'
              ': ${level.targetName ?? ''}'
        : context.tr('switch_company');
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(InRadii.r3),
      side: BorderSide(color: tokens.border),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      // `Ink` is banned: the surface is a local Material, the ripple on it.
      child: Material(
        key: const ValueKey('settings-company-card'),
        color: tokens.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: () => unawaited(showCompanyPicker(context)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: InSizes.touchTarget),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CompanyAvatar(
                    name: name,
                    seed: companyId,
                    size: 40,
                    logoUrl: logoUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: tokens.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scoped ? tokens.accentInk : tokens.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: tokens.ink3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing half of a phone settings-home value: a neutral count, or a
/// warning icon whose sentence is what a screen reader hears (and a long press
/// shows). Text values ride in the tile's subtitle instead.
class _SettingsHomeTrailing extends StatelessWidget {
  const _SettingsHomeTrailing._(this.value);

  final SettingsHomeValue value;

  static Widget? maybe(SettingsHomeValue? value) =>
      value == null || (value.count == null && value.warning == null)
      ? null
      : _SettingsHomeTrailing._(value);

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final warning = value.warning;
    if (warning != null) {
      return Tooltip(
        message: warning,
        excludeFromSemantics: true,
        child: Semantics(
          label: warning,
          child: ExcludeSemantics(
            child: Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: tokens.warning,
            ),
          ),
        ),
      );
    }
    return Text(
      '${value.count}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: tokens.ink3,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// The trailing lock on a plan-gated settings row or search hit, naming the
/// plan it needs. An icon, not a "Pro" / "Enterprise" chip: a chip overflowed
/// the ~232 px wide nav.
class _PlanLock extends StatelessWidget {
  const _PlanLock(this.tier);

  final PlanTier tier;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.tr(
        tier == PlanTier.enterprise ? 'enterprise_plan' : 'pro_plan',
      ),
      child: Icon(Icons.lock_outline, size: 16, color: context.inTheme.ink3),
    );
  }
}

/// One group of the phone settings home: a small muted label (a heading to a
/// screen reader) over one rounded card holding the group's rows, hairlines
/// between them inset past the icon. Labelled inset groups instead of one
/// flat list (R of the settings pass).
class _SettingsHomeGroup extends StatelessWidget {
  const _SettingsHomeGroup({required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  /// Where a row's title starts: its padding, the icon and the gap after it.
  /// The hairlines start here too.
  static const double rowTextInset =
      _SettingsHomeRow.hPad + _SettingsHomeRow.iconSize + _SettingsHomeRow.gap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(InRadii.r3),
      side: BorderSide(color: tokens.border),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
            child: Semantics(
              header: true,
              headingLevel: 2,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tokens.ink3,
                ),
              ),
            ),
          ),
          // `Ink` is banned: a local Material carries the surface, the rows'
          // ripples paint on it, and the clip keeps them inside the corners.
          Material(
            color: tokens.surface,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: rowTextInset,
                      color: tokens.border,
                    ),
                  row,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A phone settings-home row: icon, name, the section's value as a one-line
/// muted subtitle, the trailing count / warning / lock, and a chevron (which
/// mirrors in RTL). 56 px with a subtitle, 48 without — a floor, so a large
/// text scale grows the row instead of clipping it. One button to a screen
/// reader.
class _SettingsHomeRow extends StatelessWidget {
  const _SettingsHomeRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  static const double hPad = 16;
  static const double iconSize = 20;
  static const double gap = 16;

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final sub = subtitle;
    final tail = trailing;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: sub == null ? 48 : 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(hPad, 6, 12, 6),
              child: Row(
                children: [
                  Icon(icon, size: iconSize, color: tokens.ink3),
                  const SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: tokens.ink,
                          ),
                        ),
                        if (sub != null)
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tokens.ink3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (tail != null) ...[const SizedBox(width: 8), tail],
                  const SizedBox(width: 4),
                  // `chevron_right` matches the text direction, so it points
                  // inward-to-outward in RTL too.
                  Icon(Icons.chevron_right, size: 20, color: tokens.ink3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A wide-nav group label (Basic / Advanced Settings). Deliberately
/// label-only: the search trigger used to ride in a `trailing:` slot here,
/// which is what made it scroll away (issue #42). It now lives in the pinned
/// chrome, so both groups render identically.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Semantics(
        header: true,
        headingLevel: 2,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
