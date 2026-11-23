import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/semantics.dart' show SemanticsBinding, SemanticsService;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/entity_links.dart';
import 'package:admin/app/router.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/review_prompt_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/shortcuts/key_binding.dart';
import 'package:admin/app/shortcuts/shortcut_catalog.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/models/domain/recent_record.dart';
import 'package:admin/data/models/domain/search_result.dart';
import 'package:admin/domain/entity_registry.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/utils/platform_modifier.dart';
import 'package:admin/ui/core/widgets/key_cap.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/reports/helpers/report_access.dart';
import 'package:admin/ui/features/reports/views/reports_gallery_screen.dart';
import 'package:admin/ui/features/settings/settings_search_catalog.dart';
import 'package:admin/ui/features/settings/widgets/settings_search_result.dart';
import 'package:admin/ui/features/review_prompt/review_listing.dart';
import 'package:admin/ui/features/welcome/welcome_dialog.dart';
import 'package:admin/ui/features/whats_new/whats_new_dialog.dart';
import 'package:admin/utils/search_fold.dart';
import 'package:admin/ui/core/utils/external_url.dart';
import 'package:admin/ui/features/feedback/contact_us_dialog.dart';
import 'package:admin/ui/features/shell/widgets/sidebar_footer_actions.dart';
import 'package:admin/ui/features/shell/widgets/show_company_picker.dart';
import 'package:admin/ui/features/shell/widgets/switch_company_guarded.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/app/native_window.dart';
import 'package:admin/ui/core/list/deep_link_filter_intent.dart';
import 'package:admin/ui/features/shell/widgets/search_palette_results.dart';
import 'package:admin/ui/features/shell/widgets/search_palette_scope_bar.dart';
import 'package:admin/ui/features/settings/views/basic/account_management/plan_screen.dart';

export 'package:admin/ui/features/shell/widgets/search_palette_results.dart'
    show entityTypeForSearchGroup, recordIdForSearchHit;

/// Search-result group key for a pasted record deep link. Renders as its own
/// header via `context.tr` — `link` is an existing translated key.
const String kDeepLinkSearchGroup = 'link';

/// A record deep link the user pasted into the palette, as a single hit — or
/// null when [query] isn't one.
///
/// Accepts both shapes a shared link can take — the https form Copy/Share
/// emits and the older `invoiceninja://` one. It is the only way to follow
/// either on **web and Linux**, where the OS never hands the app a link at all,
/// and the way in anywhere the OS declined to claim one: an unverified host,
/// a messenger's in-app browser, or a link someone pasted as text.
/// Pure + unit-tested.
SearchResult? deepLinkSearchHit(String query, EntityRegistry registry) {
  final raw = query.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  final target = parseAppDeepLink(uri, registry);
  if (target == null) return null;
  // `path` carries the ORIGINAL uri, not the resolved route: activation hands
  // it back to `DeepLinkRouter` so a cross-company link still switches company
  // (the resolved route alone has no company on it).
  return SearchResult(
    group: kDeepLinkSearchGroup,
    name: target.path,
    id: '',
    path: raw,
  );
}

/// The key of the spoken result count once a query settles — "23 results in
/// 4 categories", "1 result in 1 category", "At least 90 results in 1
/// category". One and many only; a language with more plural forms words its
/// translation around the number.
String searchResultsAnnouncementKey(
  int count,
  int categories, {
  required bool atLeast,
}) {
  if (count == 1) {
    return atLeast
        ? 'search_at_least_one_result_announcement'
        : 'search_one_result_announcement';
  }
  if (categories == 1) {
    return atLeast
        ? 'search_results_at_least_one_category_announcement'
        : 'search_results_one_category_announcement';
  }
  return atLeast
      ? 'search_results_at_least_announcement'
      : 'search_results_announcement';
}

/// The group of the palette's own report hits. Also the localization key of
/// its heading ("Reports").
const String kReportsSearchGroup = 'reports';

/// The group of the palette's What's New hit — also its heading's key
/// ("Release Notes").
const String kWhatsNewSearchGroup = 'release_notes';

/// The group of the palette's first-run Welcome hit — also its heading's key
/// ("Getting Started").
const String kWelcomeSearchGroup = 'getting_started';

/// What someone looking for the Welcome types (docs/first-run-welcome.md).
/// English, beside the translated label.
const _kWelcomeTerms = [
  'welcome',
  'getting started',
  'get started',
  'old app',
  'previous app',
  "what's changed",
  'whats changed',
  'what changed',
  'tour',
  'help',
];

/// What someone looking for the release notes types. English, beside the
/// translated label and heading: "changelog" has no key of its own.
const _kWhatsNewTerms = [
  "what's new",
  'whats new',
  'release notes',
  'changelog',
  'change log',
  'version',
  'update',
];

/// The group of the palette's "Rate the app" hit — also its heading's key.
const String kRateAppSearchGroup = 'rate_the_app';

/// What someone looking to leave a review types, beside the translated label.
const _kRateAppTerms = ['rate', 'rating', 'review', 'star', 'feedback'];

/// The group of the palette's Help hits — Contact Us, User Guide, Support
/// Forum — and its heading's key. A desktop user with the sidebar collapsed
/// found no way to send feedback (invoiceninja/flutter#191); typing it is the
/// other way in.
const String kHelpSearchGroup = 'help';

/// [SearchResult.id]s of the [kHelpSearchGroup] hits.
const String _kHelpContactUs = 'contact_us';
const String _kHelpUserGuide = 'user_guide';
const String _kHelpForum = 'support_forum';

/// What someone wanting to reach a person types, beside the translated label.
/// English, like the other term lists.
const _kContactUsTerms = [
  'contact',
  'feedback',
  'bug',
  'message',
  'support',
  'problem',
  'report a problem',
  'email us',
];

/// What someone after help in general types: every Help hit answers it.
const _kHelpTerms = [
  'help',
  'support',
  'docs',
  'documentation',
  'guide',
  'manual',
  'forum',
];

/// The group of the palette's company hits — "Switch Company" (opens the
/// picker) and the user's other companies by name (switches straight to one).
/// Also its heading's key ("Company"). ⌘K belongs to the palette, so this is
/// how the keyboard reaches the switcher (docs/keyboard.md).
const String kCompanySearchGroup = 'company';

/// What someone after the company switcher types, beside the translated
/// labels. English, like the other term lists.
const _kSwitchCompanyTerms = [
  'switch company',
  'change company',
  'company',
  'companies',
  'account',
  'workspace',
  'organization',
  'organisation',
];

/// Most companies the palette lists for one query; the picker lists them all.
const _kMaxCompanyHits = 8;

/// Most settings rows the palette lists for one query — see
/// `_CommandPaletteState._localSettingsHits`.
const _kMaxSettingsHits = 8;

/// Below this window height the palette is a page: the card sits 120 px
/// down and caps itself at 520, which leaves a short window a field and a
/// row or two.
const double kPalettePageBelowHeight = 480;

/// Whether the palette opens as a full-screen page rather than the floating
/// card — a phone, or **any window too narrow or too short for the card**.
///
/// `Breakpoints.isPhone` alone asks about the device, so a desktop browser or
/// a desktop window at phone width still got the card, hung 120 px down over
/// the screen behind it. The page is what a narrow screen does everywhere
/// else in the app. Resolved per build, never hoisted — see
/// [showCommandPalette].
bool paletteUsesPage(BuildContext context) {
  if (Breakpoints.isPhone(context)) return true;
  final size = MediaQuery.sizeOf(context);
  return size.width < Breakpoints.wide || size.height < kPalettePageBelowHeight;
}

/// The height macOS's floating traffic lights take at the top of the window,
/// or 0. A full-screen page on a narrow macOS window would otherwise put its
/// back arrow under them — the shell reserves the band itself
/// (`WindowCaptionStrip`), but a dialog route sits above the shell.
double _macCaptionInset() {
  if (!hostsMacCaptionRow()) return 0;
  final chrome = NativeWindow.instance.chrome.value;
  return chrome.hasWindowButtons ? chrome.captionHeight : 0;
}

/// Cmd/Ctrl+K global command palette. Server-backed search
/// (`SearchApi`) across all entities + settings, filtered and ranked on the
/// device (`search_palette_results.dart`, docs/search-palette.md); a category
/// bar, arrow/enter/escape keyboard nav; selection routes via the entity
/// registry (or the server path for settings).
///
/// Two presentations, split on [paletteUsesPage]:
///
///  * **A full-screen page** on a phone and in any narrow or short window.
///    The floating card left the screen behind it legible through a 0.18
///    scrim, and on a phone that screen is almost always an entity list whose
///    *own* search box is pinned in the app bar (`entity_list_app_bar.dart`,
///    a permanent 56-px `PreferredSize`). At rest the card shrink-wrapped to
///    just its field, so the two landed ~20 px apart and read as one control:
///    users thought they were searching the page behind
///    (invoiceninja/flutter#102). The page reuses the `Dialog.fullscreen` +
///    `Scaffold` + `AppBar` shape the app already gives every other
///    phone-width modal (`ClientCreateDialog._fullscreen`,
///    `DesignEditScreen`) and narrow *list* search
///    (`TokenSearchField._openSheet` -> `FilterEntrySheet`).
///  * **Everything else — the Spotlight card.**
///
/// `useSafeArea: false` is deliberate and each branch then owns its insets.
/// The page paints edge-to-edge so its `AppBar` supplies the status-bar
/// padding and posts the `SystemUiOverlayStyle` (nothing else in `lib/` does);
/// left to the default, the strips outside the safe area would stay bare
/// `ModalBarrier` — which, being `barrierDismissible`, would also let a tap
/// beside the gesture bar close the page. The card re-wraps itself in the
/// `SafeArea` it has always had, so nothing changes there.
///
/// Neither `MediaQuery` nor `Theme` may be read from the **caller's** context
/// here, which is why the presentation is resolved in the builder rather than
/// hoisted into an argument: the phone entry point is `SidebarSearchBox`,
/// which pops the drawer in the statement before this call, and `AppDrawer`
/// documents that the drawer's `BuildContext` does not survive that pop.
/// Resolving it per build also keeps the palette adapting to a live resize
/// (Android split-screen, iPad Slide Over, a desktop window dragged narrow).
Future<void> showCommandPalette(BuildContext context) {
  // One key for both presentations: a foldable opening or closing while the
  // palette is up — or a window resized across the gate — swaps the page and
  // the card, and without it that remounted the palette, losing the query and
  // its results (docs/foldables.md).
  final paletteKey = GlobalKey(debugLabel: 'CommandPalette');
  return showDialog<void>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    // A tablet reaches the card from the same sidebar Search box and had the
    // same two-fields-at-once problem, just less acutely — the 0.18 Spotlight
    // scrim was tuned for a small popover anchored on a big desktop window.
    // Gated on the device, not the window, exactly like
    // `DateRangePickerButton`'s. Invisible behind the page.
    barrierColor: Env.isTouchPrimary
        ? Colors.black54
        : Colors.black.withValues(alpha: 0.18),
    useSafeArea: false,
    builder: (ctx) {
      if (paletteUsesPage(ctx)) {
        final mq = MediaQuery.of(ctx);
        final caption = _macCaptionInset();
        return MediaQuery(
          // The AppBar pads itself by `padding.top`, so raising it to the
          // caption band moves the back arrow out from under the traffic
          // lights and keeps the bar's colour behind them.
          data: caption > mq.padding.top
              ? mq.copyWith(padding: mq.padding.copyWith(top: caption))
              : mq,
          child: Dialog.fullscreen(child: _CommandPalette(key: paletteKey)),
        );
      }
      final tokens = ctx.inTheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return SafeArea(
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          alignment: Alignment.topCenter,
          // A tablet's soft keyboard takes the bottom half of the screen, and
          // `Dialog` already insets by it — 120 px off the top as well left
          // the card a field and a row. Desktop keeps its Spotlight drop.
          insetPadding: EdgeInsets.only(
            top: Env.isTouchPrimary ? 32 : 120,
            left: 24,
            right: 24,
            bottom: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 520),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(InRadii.r4),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surface.withValues(
                      alpha: isDark ? 0.86 : 0.92,
                    ),
                    border: Border.all(
                      color: tokens.border.withValues(alpha: 0.6),
                    ),
                    borderRadius: BorderRadius.circular(InRadii.r4),
                    boxShadow: tokens.shadow2,
                  ),
                  child: _CommandPalette(key: paletteKey),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({super.key});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _selRowKey = GlobalKey();

  /// Shared by the field and the category bar, so a tap on a category is not
  /// a tap *outside* the field — which on a phone dismisses the keyboard.
  final _tapGroup = Object();
  Timer? _debounce;
  Timer? _announceTimer;

  /// The query [_view] was built for.
  String _query = '';

  /// The server's entity hits for [_query] (settings stripped — see
  /// [_localSettingsHits]).
  List<SearchResult> _serverHits = const [];

  /// False when [_serverHits] is the fallback answer, which ignores the query
  /// and must be filtered on the device (`SearchResponse.serverFiltered`).
  bool _serverFiltered = true;

  /// Categories the fallback answer cut short at its limits
  /// (`fallbackCappedScopes`) — their counts are floors.
  Set<String> _cappedScopes = const {};

  /// The fallback answer once fetched. It ignores the query, so asking again
  /// per keystroke would fetch the same thousands of rows each time: it is
  /// fetched once per open and every later keystroke filters it here, with
  /// no debounce and no network.
  List<SearchResult>? _fallbackHits;

  /// The palette's own hits for [_query]: reports, app, settings.
  List<SearchResult> _localHits = const [];

  /// A pasted record link, which resolves locally and is the only hit.
  SearchResult? _link;

  /// The category shown in full, or null for All.
  String? _scope;

  /// [_query]'s rows, ranked and grouped for [_scope].
  PaletteResults _view = PaletteResults.empty;

  /// The selected row, by identity rather than index, so a re-rank, a scope
  /// switch or a refresh cannot move it to a different record.
  String? _selectedKey;

  /// The category bar, once shown, stays until the field is cleared: one
  /// that appeared with the first results and vanished when a narrower query
  /// hit one category moved the list under the user's thumb on every key.
  bool _barShown = false;

  /// Set by the arrow keys. On touch the highlight is drawn only after one —
  /// a highlighted first row means "Enter opens this", which says nothing to
  /// a finger and reads as a stuck press.
  bool _keyboardNav = false;

  /// Enter pressed while a query was still on its way and nothing was up:
  /// the first result opens when it lands.
  bool _enterPending = false;

  /// The query whose result count was last announced to a screen reader.
  String _announced = '';

  /// The settings hit behind each settings row in [_view], for its icon,
  /// its "Section › Tab" line and its field reveal. Kept beside the row
  /// rather than on [SearchResult], which is a data-layer model and must not
  /// import the settings UI.
  final Expando<SettingsSearchHit> _settingsHitOf = Expando<SettingsSearchHit>(
    'settings hit',
  );
  bool _loading = false;

  /// The selected Recent row (the at-rest list has no keys of its own).
  int _selected = 0;
  int _reqSeq = 0;

  /// Snapshot of the recently-viewed list, read once per build. Surfaced as
  /// the "Recent" group while the query is empty — the same Cmd+K surface,
  /// no separate drawer to discover.
  List<RecentRecord> _recents = const [];

  /// True when the palette is at rest (no query, no results) and there are
  /// recents to show — keyboard nav + Enter then operate on [_recents].
  bool get _recentMode =>
      !_loading &&
      _view.isEmpty &&
      _controller.text.trim().isEmpty &&
      _recents.isNotEmpty;

  /// The active company's record, for the one settings gate the session
  /// can't answer (Hide Peppol Sent Status). Null until it loads, which the
  /// search scope reads as "fail open".
  Company? _company;
  StreamSubscription<Company?>? _companySub;

  @override
  void initState() {
    super.initState();
    final services = context.read<Services>();
    _recents = services.recentlyViewed.items;
    final companyId = services.auth.session.value?.currentCompanyId;
    if (companyId != null && companyId.isNotEmpty) {
      _companySub = services.company
          .watchCompany(companyId)
          .listen((c) => _company = c);
    }
  }

  @override
  void dispose() {
    unawaited(_companySub?.cancel());
    _debounce?.cancel();
    _announceTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Keeps the keyboard/hover selection visible after [_move] or a
  /// fresh result set. Runs post-frame so [_selRowKey] is attached.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selRowKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: InMotion.of(context)(const Duration(milliseconds: 120)),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      // Back to Recents, never `_run('')`: `SearchApi.search` omits the
      // `search` param for a blank query and the server answers unfiltered.
      _toRest();
      return;
    }
    // An Enter pressed for the previous text is withdrawn by this edit.
    _enterPending = false;
    final registry = context.read<Services>().entityRegistry;
    if (deepLinkSearchHit(q, registry) != null) {
      // A pasted link is the answer — no reason to wait.
      unawaited(_run(q));
      return;
    }
    // A query answered from the cached fallback costs no request, but it does
    // re-rank thousands of rows, so a burst of keys still settles first —
    // just not for as long as a round-trip's debounce.
    final wait = _fallbackHits != null
        ? const Duration(milliseconds: 40)
        : const Duration(milliseconds: 150);
    _debounce = Timer(wait, () => _run(q));
    // `_loading` from the first key, not from when the debounce fires:
    // between the two the field held text while `_view` was still empty, and
    // `build` took that for "No records found" — flashed on every search
    // started from rest. The progress bar says the truth: one is coming.
    setState(() => _loading = true);
  }

  /// Empties the field and returns the palette to its at-rest (Recents)
  /// state, without touching the network.
  ///
  /// Bumps [_reqSeq]. Cancelling [_debounce] alone is not enough: a request
  /// that has already left is only discarded by [_run]'s `seq != _reqSeq`
  /// check, so without the bump a response landing after the tap repopulates
  /// the list under an empty field, with nothing on screen to explain it.
  ///
  /// It also deliberately does not route through [_onChanged]'s debounce —
  /// `SearchApi.search` omits the `search` param for a blank query, so the
  /// server answers with an unfiltered page.
  void _reset() {
    _debounce?.cancel();
    _reqSeq++;
    _controller.clear();
    _toRest();
  }

  /// The at-rest state: no query, no results, All, no category bar.
  void _toRest() {
    _debounce?.cancel();
    _reqSeq++;
    setState(() {
      _query = '';
      _link = null;
      _scope = null;
      _barShown = false;
      _serverHits = const [];
      _localHits = const [];
      _view = PaletteResults.empty;
      _selectedKey = null;
      _selected = 0;
      _loading = false;
      _enterPending = false;
    });
  }

  Future<void> _run(String q) async {
    final seq = ++_reqSeq;
    final services = context.read<Services>();
    // A pasted deep link resolves locally — no round-trip, and no other hit
    // could be what the user meant.
    final link = deepLinkSearchHit(q, services.entityRegistry);
    if (link != null) {
      setState(() {
        _query = q;
        _link = link;
        // A link has no categories; one left open would keep taking Tab and
        // the first Esc behind a bar that is no longer drawn.
        _scope = null;
        _barShown = false;
        _loading = false;
        _rebuildView(resetSelection: true);
      });
      _afterResults();
      return;
    }
    _link = null;
    final local = _allLocalHits(q);
    final cached = _fallbackHits;
    if (cached != null) {
      setState(() {
        _query = q;
        _serverHits = cached;
        _serverFiltered = false;
        _cappedScopes = fallbackCappedScopes(cached);
        _localHits = local;
        _loading = false;
        _rebuildView(resetSelection: true);
      });
      _afterResults();
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await services.search.search(q);
      if (!mounted) return;
      // Server `settings` hits are dropped in favour of the local catalog —
      // see [_localSettingsHits].
      final hits = [
        for (final hit in response.hits)
          if (!hit.isSettings) hit,
      ];
      // Kept only when it is provably the query-blind fallback: no `quotes`
      // key, every query word missing from some record, and MORE rows than
      // Elasticsearch ever sends — an ES server from late 2024 answered
      // without the key, and its fuzzy hits would pass the other two tests.
      final cache =
          _fallbackHits == null &&
          !response.serverFiltered &&
          hits.length > kServerSearchHitCap &&
          answerIgnoresQuery(hits, q);
      if (cache) {
        _fallbackHits = hits;
        // Set with the cache, not only below: a cached answer that lands
        // superseded is re-run from the cache, which skips that assignment,
        // and the floor was lost for the rest of the open.
        _cappedScopes = fallbackCappedScopes(hits);
      }
      if (seq != _reqSeq) {
        // Superseded by a newer keystroke — but a query-blind answer serves
        // that one too. Dropping it here meant a steady typist fetched the
        // whole company once per pause and never kept any of it.
        final current = _controller.text;
        if (cache && current.trim().isNotEmpty) unawaited(_run(current));
        return;
      }
      setState(() {
        _query = q;
        _serverHits = hits;
        _serverFiltered = response.serverFiltered;
        _cappedScopes = response.serverFiltered
            ? const {}
            : fallbackCappedScopes(hits);
        _localHits = local;
        _loading = false;
        _rebuildView(resetSelection: true);
      });
    } catch (_) {
      if (!mounted || seq != _reqSeq) return;
      // An Enter pressed while waiting meant a record the server never sent;
      // opening the first local row instead (a settings page) would be a
      // guess.
      _enterPending = false;
      // The server could not be asked (offline, most often). What the app
      // can answer by itself it still does — a report or a settings page is
      // found in its own catalog, not on the server.
      setState(() {
        _query = q;
        _serverHits = const [];
        _localHits = local;
        _loading = false;
        _rebuildView(resetSelection: true);
      });
    }
    _afterResults();
  }

  /// The lists offered as "Search Clients for '…'" when nothing matched — the
  /// server's answer stops at its caps, the paged list does not. Only those
  /// this company can open.
  List<String> _listScopes() {
    final registry = context.read<Services>().entityRegistry;
    return [
      for (final scope in const ['clients', 'invoices'])
        if (entityTypeForSearchGroup(scope) case final type?)
          if (registry[type] case final h?)
            if (!h.disabled && h.routePath.isNotEmpty) scope,
    ];
  }

  /// Every hit the palette answers itself, in its fixed group order.
  List<SearchResult> _allLocalHits(String q) => [
    ..._localReportHits(q),
    ..._localWelcomeHits(q),
    ..._localWhatsNewHits(q),
    ..._localRateAppHits(q),
    ..._localHelpHits(q),
    ..._localCompanyHits(q),
    ..._localSettingsHits(q),
  ];

  /// Recomputes [_view] from the current hits, query and scope. Inside a
  /// `setState`.
  ///
  /// A new query selects its first row; a scope switch or a refresh keeps
  /// the selected record when it is still there.
  void _rebuildView({bool resetSelection = false}) {
    final link = _link;
    if (link != null) {
      _view = PaletteResults(
        items: [
          const PaletteHeader(kDeepLinkSearchGroup),
          PaletteRow(
            PaletteHit(
              source: link,
              scope: kDeepLinkSearchGroup,
              title: link.name,
              key: kDeepLinkSearchGroup,
              tier: MatchTier.exact,
            ),
          ),
        ],
        scopes: const [],
        total: 1,
        totalAtLeast: false,
      );
    } else if (_query.trim().isEmpty) {
      _view = PaletteResults.empty;
    } else {
      _view = buildPaletteResults(
        query: _query,
        hits: _serverHits,
        serverFiltered: _serverFiltered,
        localHits: _localHits,
        serverHitCount: _serverHits.length,
        recents: [for (final r in _recents) (r.type, r.id)],
        cappedScopes: _serverFiltered ? const {} : _cappedScopes,
        listScopes: _listScopes(),
        scope: _scope,
      );
    }
    if (_view.scopes.length >= 2) _barShown = true;
    final selectable = _view.selectable;
    if (selectable.isEmpty) {
      _selectedKey = null;
    } else if (resetSelection ||
        _selectedKey == null ||
        !selectable.any((i) => i.key == _selectedKey)) {
      _selectedKey = selectable.first.key;
    }
  }

  /// Once a result set lands: keep the selection in view, run an Enter that
  /// was waiting for it, and tell a screen reader what came back.
  void _afterResults() {
    if (!mounted) return;
    _revealSelected();
    if (_enterPending) {
      _enterPending = false;
      // Only a record: on no match the first row is "Search Clients for …",
      // and Enter pressed before the answer was not a request for a list.
      final selectable = _view.selectable;
      if (selectable.isNotEmpty && selectable.first is PaletteRow) {
        unawaited(_select());
      }
    }
    _announceTimer?.cancel();
    // Only with assistive technology on — nothing else hears it, so nothing
    // else should pay for the timer.
    if (!SemanticsBinding.instance.semanticsEnabled) return;
    // Once the typing settles — never per keystroke, which the on-device
    // filter now answers.
    _announceTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _query == _announced || _query.trim().isEmpty) return;
      _announced = _query;
      _announce(_resultsAnnouncement());
    });
  }

  String _resultsAnnouncement() {
    if (_view.total == 0) return context.tr('no_records_found');
    return context.tr(
      searchResultsAnnouncementKey(
        _view.total,
        _view.scopes.length,
        atLeast: _view.totalAtLeast,
      ),
      {'count': '${_view.total}', 'categories': '${_view.scopes.length}'},
    );
  }

  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  /// Reports, by name — so "aging" or "invoices" typed here opens the report
  /// without a trip through the gallery. The server's search knows nothing
  /// of them. Filtered by [availableReports], the same rule the gallery and
  /// the route apply, so a report this user may not open is not offered.
  List<SearchResult> _localReportHits(String query) {
    final words = foldedSearchWords(query);
    if (words.isEmpty) return const [];
    final l10n = Localization.of(context);
    if (l10n == null) return const [];
    final company = context.read<Services>().auth.session.value?.currentCompany;
    return [
      for (final definition in reportsInGalleryOrder(availableReports(company)))
        if (fieldsMatchEveryWord(words, [l10n.lookup(definition.labelKey)]))
          SearchResult(
            group: kReportsSearchGroup,
            name: l10n.lookup(definition.labelKey),
            id: '',
            path: reportRoutePath(definition.identifier),
          ),
    ];
  }

  /// The first-run Welcome (docs/first-run-welcome.md), for "welcome",
  /// "getting started", "old app" and the like. Selecting it opens the
  /// Welcome over the current screen.
  List<SearchResult> _localWelcomeHits(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.length < 3 || !welcomeAvailable(context)) return const [];
    final label = context.tr('getting_started');
    final terms = [..._kWelcomeTerms, label.toLowerCase()];
    if (!terms.any((t) => t.startsWith(needle) || t.contains(' $needle'))) {
      return const [];
    }
    return [
      SearchResult(group: kWelcomeSearchGroup, name: label, id: '', path: ''),
    ];
  }

  /// The release notes (docs/whats-new-dialog.md), for "what's new",
  /// "changelog", "version" and the like. Selecting it opens the dialog over
  /// the current screen.
  List<SearchResult> _localWhatsNewHits(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.length < 3) return const [];
    final releases = whatsNewOnRequest(context);
    if (releases == null) return const [];
    final label = context.tr('see_whats_new', {
      'version': releases.first.version,
    });
    final terms = [
      ..._kWhatsNewTerms,
      label.toLowerCase(),
      context.tr('release_notes').toLowerCase(),
    ];
    // From the start of a word: "date" is someone after a date format, not
    // "update".
    if (!terms.any((t) => t.startsWith(needle) || t.contains(' $needle'))) {
      return const [];
    }
    return [
      SearchResult(group: kWhatsNewSearchGroup, name: label, id: '', path: ''),
    ];
  }

  /// Contact Us, User Guide and Support Forum. "feedback", "bug", "contact"
  /// and the like go to Contact Us; "help" and its kin list all three.
  List<SearchResult> _localHelpHits(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.length < 3) return const [];
    bool matches(List<String> terms) =>
        terms.any((t) => t.startsWith(needle) || t.contains(' $needle'));
    final contact = context.tr('contact_us');
    final wantsContact = matches([..._kContactUsTerms, contact.toLowerCase()]);
    final wantsHelp = matches([
      ..._kHelpTerms,
      context.tr('user_guide').toLowerCase(),
      context.tr('support_forum').toLowerCase(),
    ]);
    if (!wantsContact && !wantsHelp) return const [];
    SearchResult hit(String id, String name) =>
        SearchResult(group: kHelpSearchGroup, name: name, id: id, path: '');
    return [
      hit(_kHelpContactUs, contact),
      if (wantsHelp) ...[
        hit(_kHelpUserGuide, context.tr('user_guide')),
        hit(_kHelpForum, context.tr('support_forum')),
      ],
    ];
  }

  /// "Switch Company" for "company", "switch", "account" and the like, and
  /// every other company of this login whose name matches every word typed.
  /// The current company is never offered: switching to it does nothing.
  List<SearchResult> _localCompanyHits(String query) {
    final session = context.read<Services>().auth.session.value;
    if (session == null) return const [];
    final needle = query.trim().toLowerCase();
    final label = context.tr('switch_company');
    final terms = [
      ..._kSwitchCompanyTerms,
      label.toLowerCase(),
      context.tr('company').toLowerCase(),
    ];
    final wantsSwitcher =
        needle.length >= 3 &&
        terms.any((t) => t.startsWith(needle) || t.contains(' $needle'));
    final words = foldedSearchWords(query);
    final companies = words.isEmpty
        ? const <AuthCompany>[]
        : session.companies
              .where(
                (c) =>
                    c.id != session.currentCompanyId &&
                    fieldsMatchEveryWord(words, [c.displayName]),
              )
              .take(_kMaxCompanyHits)
              .toList();
    return [
      if (wantsSwitcher)
        SearchResult(group: kCompanySearchGroup, name: label, id: '', path: ''),
      for (final c in companies)
        SearchResult(
          group: kCompanySearchGroup,
          name: c.displayName,
          id: c.id,
          path: '',
        ),
    ];
  }

  /// Switches to company [id] the way a pick in the company picker does
  /// (`CompanyPicker._pick`): the same guards, the same "stay on this page"
  /// landing (`companySafeLocation`), and the palette held open — its progress
  /// bar running — until the switch resolves. A switch into a company whose
  /// token is missing waits on a full `/refresh`; closing first left an
  /// unchanged shell on screen for that long before any toast arrived.
  Future<void> _switchToCompany(String id, String name) async {
    // One switch at a time: a second Enter or click while the first is still
    // resolving would otherwise run its guards and switch again.
    if (_switchingCompany) return;
    _switchingCompany = true;
    try {
      await _runCompanySwitch(id, name);
    } finally {
      _switchingCompany = false;
    }
  }

  bool _switchingCompany = false;

  Future<void> _runCompanySwitch(String id, String name) async {
    final services = context.read<Services>();
    final router = GoRouter.maybeOf(context);
    final currentLocation =
        router?.routerDelegate.currentConfiguration.uri.toString() ??
        '/clients';
    final routePaths = services.entityRegistry.uiRoutePaths;
    final nav = Navigator.of(context);
    final outcome = await switchCompanyGuarded(
      context,
      id,
      companyName: name,
      onSwitchStart: () {
        if (mounted) setState(() => _loading = true);
      },
      onSwitchEnd: () {
        if (mounted) setState(() => _loading = false);
      },
    );
    // Cancelled at a guard: the palette stays open and the user stays put.
    if (outcome == null) return;
    // Only pop what is still ours — a 401 during a healing refresh replaces
    // the stack (the same reason `CompanyPicker._pick` checks).
    if (mounted) unawaited(nav.maybePop());
    if (outcome == SwitchCompanyResult.ok) {
      router?.go(companySafeLocation(currentLocation, routePaths));
    }
  }

  /// "Rate the app" (docs/review-prompt.md) — a static link to the review
  /// page, hidden wherever About hides it (beta, the demo, Apple before the
  /// listing's id is known).
  List<SearchResult> _localRateAppHits(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.length < 3) return const [];
    final reviewPrompt = context.read<ReviewPromptController?>();
    final session = context.read<Services>().auth.session.value;
    if (reviewPrompt == null || !reviewPrompt.offersManualRatingTo(session)) {
      return const [];
    }
    final label = context.tr('rate_the_app');
    final terms = [..._kRateAppTerms, label.toLowerCase()];
    if (!terms.any((t) => t.startsWith(needle) || t.contains(' $needle'))) {
      return const [];
    }
    return [
      SearchResult(group: kRateAppSearchGroup, name: label, id: '', path: ''),
    ];
  }

  /// Settings hits, served from the app's own catalog instead of the server's.
  ///
  /// `POST /api/v1/search` builds its `settings` group from `settingsMap($user)`,
  /// which never sees the query — it returns the WHOLE catalogue (~92 rows) on
  /// every request and expects the client to filter. Worse, those rows carry
  /// React web routes (`/settings/subscriptions`, `…/create`,
  /// `/settings/user_details/accent_color`, …); ~19 of them match no route
  /// here, and `errorBuilder` is registered at the ROOT, so selecting one
  /// replaced the entire app — sidebar included — with the route-error screen.
  ///
  /// `kSettingsSearchCatalog` is route-correct by construction (a test resolves
  /// every hit through the router), so this filters properly, never
  /// dead-ends, and works offline. Gating and ranking are the settings
  /// screen's own (`SettingsSearchScope`, `searchSettings`), so a
  /// module-disabled or admin-only page can't surface as a dead link here
  /// either.
  ///
  /// Capped at [_kMaxSettingsHits]: a one-letter query matches a few hundred
  /// labels, and this group sits below the records the user more likely came
  /// for. The settings screen's own search lists them all.
  List<SearchResult> _localSettingsHits(String query) {
    final l10n = Localization.of(context);
    if (l10n == null) return const [];
    final services = context.read<Services>();
    final hits = searchSettings(
      query,
      l10n,
      scope: SettingsSearchScope.from(
        services.auth.session.value,
        services.settingsLevel,
        company: _company,
        serverVersion: services.serverVersion.value,
        showsChangePlan: changePlanCardShown(
          context,
          services.auth.session.value,
        ),
      ),
    ).take(_kMaxSettingsHits);
    return [for (final hit in hits) _settingsRowFor(hit, l10n)];
  }

  SearchResult _settingsRowFor(SettingsSearchHit hit, Localization l10n) {
    final row = SearchResult(
      group: 'settings',
      name: l10n.lookup(hit.fieldKey),
      id: '',
      path: hit.route,
    );
    _settingsHitOf[row] = hit;
    return row;
  }

  void _move(int delta) {
    // On touch the selection is not painted until an arrow key is pressed
    // ([_tile]), so the first press only shows it: moving as well put the
    // first ↓ on the second row and wrapped the first ↑ to the last — the
    // user never saw the row they skipped.
    if (Env.isTouchPrimary && !_keyboardNav) {
      setState(() => _keyboardNav = true);
      _revealSelected();
      return;
    }
    _keyboardNav = true;
    if (_recentMode) {
      final n = _recents.length;
      setState(() {
        _selected = (_selected + delta) % n;
        if (_selected < 0) _selected += n;
      });
      _revealSelected();
      return;
    }
    final items = _view.selectable;
    if (items.isEmpty) return;
    final at = items.indexWhere((i) => i.key == _selectedKey);
    var next = at < 0 ? 0 : (at + delta) % items.length;
    if (next < 0) next += items.length;
    setState(() => _selectedKey = items[next].key);
    _revealSelected();
  }

  /// ⌘↓ / ⌘↑ (Ctrl elsewhere): the first row of the next / previous group in
  /// All — Spotlight's category jump, so "not a client" is one key, not a
  /// dozen arrows. Stops at either end rather than wrapping.
  void _jumpGroup(int direction) {
    final items = _view.items;
    final headers = [
      for (var i = 0; i < items.length; i++)
        if (items[i] is PaletteHeader) i,
    ];
    if (headers.length < 2) return;
    final at = items.indexWhere((i) => i.key != null && i.key == _selectedKey);
    final group = headers.lastIndexWhere((h) => h <= at);
    final target = group + direction;
    if (target < 0 || target >= headers.length) return;
    for (var i = headers[target] + 1; i < items.length; i++) {
      final item = items[i];
      if (item is PaletteHeader) break;
      if (item.key != null) {
        _keyboardNav = true;
        setState(() => _selectedKey = item.key);
        _revealSelected();
        return;
      }
    }
  }

  /// The categories the bar shows: every one with hits, plus the one in view
  /// when a re-query left it empty — it stays, at 0, rather than vanishing
  /// with the user still inside it.
  List<PaletteScope> get _barScopes {
    final scopes = _view.scopes;
    final scope = _scope;
    if (scope == null || scopes.any((s) => s.id == scope)) return scopes;
    return [...scopes, PaletteScope(scope, 0)];
  }

  /// Whether Tab moves between categories. Not while a screen reader drives
  /// the app: there Tab is how its user reaches the page's buttons.
  bool _tabCyclesScopes(BuildContext context) =>
      _barShown &&
      _link == null &&
      _barScopes.isNotEmpty &&
      !MediaQuery.accessibleNavigationOf(context);

  void _cycleScope(int direction) {
    final ids = <String?>[null, for (final s in _barScopes) s.id];
    var at = ids.indexOf(_scope);
    if (at < 0) at = 0;
    var next = (at + direction) % ids.length;
    if (next < 0) next += ids.length;
    _setScope(ids[next], announce: true);
  }

  /// Shows [scope] in full (null: All), keeping the selected record when it
  /// is still in view — or selecting [selectKey] (the first row "Show all"
  /// had hidden).
  void _setScope(String? scope, {String? selectKey, bool announce = false}) {
    final keep = selectKey ?? _selectedKey;
    setState(() {
      _scope = scope;
      _rebuildView();
      if (keep != null && _view.selectable.any((i) => i.key == keep)) {
        _selectedKey = keep;
      }
    });
    _revealSelected();
    if (!announce) return;
    if (scope == null) {
      _announce(_resultsAnnouncement());
      return;
    }
    final entry = _barScopes.firstWhere(
      (s) => s.id == scope,
      orElse: () => PaletteScope(scope, 0),
    );
    _announce(
      context.tr(
        searchScopeAnnouncementKey(entry.count, atLeast: entry.atLeast),
        {'scope': context.tr(scope), 'count': '${entry.count}'},
      ),
    );
  }

  /// The palette's keys, ahead of the field's own. Each returns `ignored`
  /// when it has nothing to do, so the field keeps the key: ⌘↓ still moves
  /// the caret on the Recents list, Tab still traverses with a screen reader.
  ///
  /// No Backspace-on-empty-field back to All (the Slack / GitHub gesture):
  /// emptying the field already returns the palette to rest, category and
  /// all, so there is never an empty field inside a category to press it in.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final modifier = apple ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final direction = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      if (modifier) {
        if (_recentMode || _scope != null) return KeyEventResult.ignored;
        _jumpGroup(direction);
        return KeyEventResult.handled;
      }
      if (keyboard.isShiftPressed || keyboard.isAltPressed) {
        return KeyEventResult.ignored;
      }
      _move(direction);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    // Enter from a hardware keyboard opens the selection — an iPad with a
    // keyboard included, where the field's submit only runs the search (see
    // [_submit]). Not mid-composition: an IME's Enter confirms its text.
    // Not on web, touch or not: the browser submits the field on Enter
    // whether or not a key handler took it, so the field's own `onSubmitted`
    // is the one path there and [_submit] decides what it does — taking it
    // here as well selected twice.
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        !kIsWeb) {
      final composing = _controller.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      _keyboardNav = true;
      unawaited(_select());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && _tabCyclesScopes(context)) {
      _cycleScope(keyboard.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      // Out of a category first, then out of the palette.
      if (_scope != null) {
        _setScope(null, announce: true);
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether the field currently holds a followable link, i.e. whether Enter
  /// does something even with no results up. Same resolution [_select] uses,
  /// so the hint and the key cannot disagree.
  bool _fieldHoldsLink(BuildContext context) =>
      deepLinkSearchHit(
        _controller.text,
        context.read<Services>().entityRegistry,
      ) !=
      null;

  /// The soft keyboard's Search key, on touch. It runs the search now and
  /// lowers the keyboard so the results can be seen; it opens nothing — on a
  /// phone there is no visible selection to say what it would open. A pasted
  /// link is the exception: the link IS the result.
  void _onImeSubmit() {
    if (_fieldHoldsLink(context)) {
      unawaited(_select());
      return;
    }
    _debounce?.cancel();
    final q = _controller.text;
    if (q.trim().isNotEmpty && q != _query) {
      unawaited(_run(q));
    } else {
      // The results on screen already answer this text: end the wait the
      // keystroke started (and drop any request for an in-between text), or
      // the progress bar spins with nothing coming.
      _reqSeq++;
      setState(() => _loading = false);
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// A select in progress: a second one (a double Enter, or the web's own
  /// submit beside the key) must not pop the route under the palette.
  bool _selecting = false;

  /// Opens the selected row. [tapped]: the user picked a row they can see,
  /// which opens even while a newer text's search is on its way — only a key
  /// waits for the rows that text will bring.
  Future<void> _select({bool tapped = false}) async {
    if (_selecting) return;
    _selecting = true;
    try {
      await _selectNow(tapped: tapped);
    } finally {
      _selecting = false;
    }
  }

  Future<void> _selectNow({required bool tapped}) async {
    // The palette navigates away from whatever is on screen, so it owes the
    // same unsaved-changes prompt the sidebar / branch switcher gives. Without
    // it, a dirty editor was left behind unprompted and then tripped the guard
    // later, on an unrelated (clean) screen.
    final services = context.read<Services>();
    if (_recentMode) {
      if (_selected < 0 || _selected >= _recents.length) return;
      final r = _recents[_selected];
      if (!await services.unsavedChangesGuard.confirmIfDirty(context)) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      goEntityRecord(context, r.type, r.id);
      return;
    }
    // Resolve a pasted link from the FIELD, before consulting `_view` —
    // `_onChanged` only arms the debounce, it does not clear the old hits, so
    // inside that window `_view` still belongs to the *previous* query.
    // Reading the field is always current, and when the text IS a link there
    // is no other hit the user could have selected. When it is not a link
    // this returns null and the normal path runs.
    final pasted = deepLinkSearchHit(_controller.text, services.entityRegistry);
    if (pasted != null) {
      if (!await services.unsavedChangesGuard.confirmIfDirty(context)) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      unawaited(services.deepLinks.open(Uri.parse(pasted.path)));
      return;
    }
    final selectable = _view.selectable;
    final searchPending = _debounce?.isActive == true || _loading;
    // Nothing up yet, or what is up answers an older text (the debounce or
    // the round trip is still running): open the first result of THIS text
    // when it lands, rather than swallowing the key or opening the previous
    // query's selected row.
    if (searchPending &&
        (selectable.isEmpty || (!tapped && _controller.text != _query))) {
      _enterPending = true;
      return;
    }
    if (selectable.isEmpty) return;
    final item = selectable.firstWhere(
      (i) => i.key == _selectedKey,
      orElse: () => selectable.first,
    );
    switch (item) {
      case PaletteShowAll():
        _setScope(item.scope, selectKey: item.firstHiddenKey, announce: true);
      case PaletteBackToAll():
        _setScope(null, announce: true);
      case PaletteSearchList():
        await _openList(item);
      case PaletteRow():
        await _openHit(item.hit.source);
      case PaletteHeader():
      case PaletteNoMatches():
        break;
    }
  }

  /// "Search Clients for 'Pro'": the entity's own list, searched — paged and
  /// complete, where the palette shows at most what the server sent.
  Future<void> _openList(PaletteSearchList item) async {
    final services = context.read<Services>();
    final handlers = services.entityRegistry[item.type];
    if (handlers == null || handlers.routePath.isEmpty) return;
    if (!await services.unsavedChangesGuard.confirmIfDirty(context)) return;
    if (!mounted) return;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(
      handlers.routePath,
      extra: ListFilterIntent(search: _query.trim()),
    );
  }

  Future<void> _openHit(SearchResult r) async {
    final services = context.read<Services>();
    if (r.group == kRateAppSearchGroup) {
      // Nothing navigates, so no unsaved-changes prompt; and the launch runs
      // first, inside the key press or tap, before any await.
      final reviewPrompt = context.read<ReviewPromptController?>();
      if (reviewPrompt == null) return;
      rateAppManually(context, reviewPrompt);
      Navigator.of(context).pop();
      return;
    }
    if (r.group == kHelpSearchGroup) {
      // Nothing navigates: a dialog over the current screen, or a browser.
      // The link opens first, inside the key press or tap, before any await.
      final host = Navigator.of(context, rootNavigator: true).context;
      // The palette is a dialog route, outside any GoRoute's state.
      final location =
          GoRouter.maybeOf(
            context,
          )?.routerDelegate.currentConfiguration.uri.path ??
          '';
      switch (r.id) {
        case _kHelpUserGuide:
          unawaited(openExternalUrl(host, userGuideUrl(location)));
        case _kHelpForum:
          unawaited(openExternalUrl(host, kSupportForumUrl));
      }
      // The palette's own exit, so it isn't in Contact Us's screenshot.
      final closing = (ModalRoute.of(context) as TransitionRoute?)?.completed;
      Navigator.of(context).pop();
      if (r.id == _kHelpContactUs) {
        unawaited(showContactUsDialog(host, afterClosing: closing));
      }
      return;
    }
    if (r.group == kCompanySearchGroup) {
      // The picker opens from the root navigator's context, which outlives
      // this palette; a company row switches with the picker's own guards
      // (unsaved form, unsynced outbox) while the palette stays up.
      if (r.id.isEmpty) {
        final host = Navigator.of(context, rootNavigator: true).context;
        Navigator.of(context).pop();
        unawaited(showCompanyPicker(host));
      } else {
        await _switchToCompany(r.id, r.name);
      }
      return;
    }
    if (r.group == kWelcomeSearchGroup) {
      // Over the current screen, like the release notes below.
      final host = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      unawaited(openWelcomeOnRequest(host));
      return;
    }
    if (r.group == kWhatsNewSearchGroup) {
      // A dialog over the current screen, which nothing navigates away from
      // — so no unsaved-changes prompt. Opened from the root navigator's
      // context, which outlives this palette.
      final host = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      unawaited(openWhatsNewOnRequest(host));
      return;
    }
    if (!await services.unsavedChangesGuard.confirmIfDirty(context)) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    if (r.group == kDeepLinkSearchGroup) {
      // Back through the same choreography an OS-delivered link gets, so a
      // pasted cross-company link switches company before it navigates.
      unawaited(services.deepLinks.open(Uri.parse(r.path)));
      return;
    }
    final settingsHit = _settingsHitOf[r];
    if (settingsHit != null) {
      // Opens the hit's tab and asks the page to flash the field.
      openSettingsSearchHit(context, settingsHit);
      return;
    }
    final type = entityTypeForSearchGroup(r.group);
    final recordId = recordIdForSearchHit(r);
    if (type != null && recordId.isNotEmpty) {
      goEntityRecord(context, type, recordId);
    } else if (r.path.isNotEmpty) {
      context.go(r.path);
    }
  }

  /// The palette's own shortcut as display glyphs, or null when it is unbound
  /// (or the tree has no shortcut controller, as in a bare widget test).
  List<String>? _paletteGlyphs(BuildContext context) {
    KeyBinding? binding;
    try {
      binding = context.read<Services>().keyboardShortcuts.effectiveBinding(
        ShortcutActionIds.openCommandPalette,
      );
    } catch (_) {
      binding = null;
    }
    return binding?.displayGlyphs(platformModifierLabel());
  }

  /// The keyboard affordance row under the results / recents lists:
  /// `[↑][↓] Navigate  [Enter] Select  [Esc] Close`.
  ///
  /// Every key is a [KeyCapRow] — the same chip the hold-modifier hint bar,
  /// the `?` dialog and this card's own field use. It was flat
  /// `↑↓ · ↵ · esc` text, which put two treatments of one idea ~40 px apart:
  /// this row, and the keycap directly above it
  /// (invoiceninja/flutter#103). The middots went with it — a bordered cap is
  /// already its own visual unit, so the runs separate on space. `Enter` and
  /// `Esc` are spelled out rather than drawn as `↵` / `⎋`, matching the `?`
  /// dialog and what `KeyBinding.displayGlyphs` produces for a rebind.
  ///
  /// The nav runs are gated, because a keycap makes a claim that grey 11-px
  /// text got away with mumbling: [_move] early-returns on an empty list, and
  /// this footer renders in the "No records found" and loading-from-rest
  /// states too, where `↑↓` does nothing at all.
  ///
  /// `Enter` is live in one more state than `↑↓` is: [_select] follows a
  /// pasted link straight off the field, so during the 250 ms debounce — where
  /// `_results` is still empty — it already works. Hence the extra
  /// [_fieldHoldsLink] term; without it the footer said Enter was dead in
  /// exactly the window the paste-a-link flow lives in.
  ///
  /// `Esc` is NOT gated on `Env.isTouchPrimary`, though a tablet reaches this
  /// card (touch, but `shortestSide >= 600`, so not `isPhone`). It stays
  /// registered in `bindings` either way, so an iPad with a keyboard can press
  /// it — hiding a hint that is true, on the same device the card keeps its
  /// arrow hints for, would have been the inconsistency rather than the fix.
  ///
  /// One definition, two spread sites: it shipped as two byte-identical
  /// 26-line blocks 120 lines apart, so a copy edit — a fourth hint, a
  /// relabelled key — would have landed in one state and not the other, with
  /// nothing to catch it.
  ///
  /// Keyboard-only, so the callers hide the whole row on a phone along with
  /// the `⌘ K` chip: a divider plus glyphs nobody can press, in a dialog that
  /// is short on height exactly there. Nothing is stranded — the barrier is
  /// dismissible, Android back pops the route, and the field carries a close
  /// button on every touch device.
  List<Widget> _keyboardHints(BuildContext context) {
    final tokens = context.inTheme;
    final canMove = _recentMode || _view.selectable.isNotEmpty;
    final canSelect = canMove || _fieldHoldsLink(context);
    final runs = <Widget>[
      // Only while Tab actually moves between categories — the same "true
      // claims only" rule as the rest. ⌘↓ / ⌘↑ (next / previous group) is a
      // power-user binding and lives in docs/keyboard.md, not here: four
      // hint pairs is clutter.
      if (_tabCyclesScopes(context))
        KeyCapRow(keys: const ['Tab'], label: context.tr('category')),
      if (canMove)
        KeyCapRow(keys: const ['↑', '↓'], label: context.tr('navigate')),
      if (canSelect)
        KeyCapRow(keys: const ['Enter'], label: context.tr('select')),
      KeyCapRow(keys: const ['Esc'], label: context.tr('close')),
    ];
    return [
      Container(height: 1, color: tokens.border.withValues(alpha: 0.6)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // `Wrap`, not `Row`: the three runs are ~314 px on the 680-px card
        // (German ~344, Spanish ~364) and the caps grow with `textScaler`, so
        // a narrow window at a large text size would overflow a `Row` rather
        // than reflow. Left-aligned to match the card's own content edge —
        // and the design-editor footer, the app's other hint row.
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: InSpacing.lg(context),
          runSpacing: InSpacing.sm,
          children: runs,
        ),
      ),
    ];
  }

  /// Enter in the field. On touch the soft keyboard's Search key only runs
  /// the search ([_onImeSubmit]) — unless the arrow keys have been used, which
  /// means a hardware keyboard and a visible selection for Enter to open.
  void _submit(bool touch) {
    if (touch && !_keyboardNav) {
      _onImeSubmit();
    } else {
      unawaited(_select());
    }
  }

  /// The search field. Two shapes.
  ///
  /// On the **page** (a phone, or a narrow window) it is the `AppBar`'s title: no prefix glyph (the back
  /// arrow owns the leading slot) and no suffix (the clear button is an
  /// `AppBar` action), at the 16-px Material search-bar size — 22 was tuned
  /// for the 680-px card and does not leave room for the placeholder beside a
  /// 44-px arrow on a 412-px screen. Everywhere else it is the card's own
  /// 22-px row, unchanged.
  Widget _buildField(
    BuildContext context, {
    required bool page,
    required bool touch,
  }) {
    final tokens = context.inTheme;
    if (page) {
      return TextField(
        controller: _controller,
        autofocus: true,
        // Search queries are names and numbers, not prose — iOS
        // autocorrecting "Acme" to "Acne" mid-search is the failure.
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.search,
        groupId: _tapGroup,
        onChanged: _onChanged,
        onSubmitted: (_) => _submit(touch),
        style: TextStyle(fontSize: 16, color: tokens.ink),
        decoration: InputDecoration(
          // `search_placeholder` ("Find invoices, clients, and more"), not the
          // bare `search`: saying what this searches is the other half of
          // flutter#102, whose reporter's users read a lone magnifier as
          // "search *this page*". A real Transifex key, so it keeps its
          // translation everywhere the bundle has one.
          hintText: context.tr('search_placeholder'),
          hintStyle: TextStyle(fontSize: 16, color: tokens.ink3),
          // Ellipsize rather than wrap — an `InputDecorator` hint wraps by
          // default and the German string is ~38 characters.
          hintMaxLines: 1,
          filled: false,
          isDense: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          // 12 + line box + 12 is ~44: a real tap target for re-focusing after
          // the keyboard is dismissed, and still inside the 56-px toolbar.
          // `isCollapsed` would shrink it to the text's own ~20 px.
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
    }
    return TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.go,
      groupId: _tapGroup,
      onChanged: _onChanged,
      onSubmitted: (_) => _submit(touch),
      style: TextStyle(fontSize: 22, color: tokens.ink),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search, size: 26, color: tokens.ink3),
        hintText: context.tr('search'),
        hintStyle: TextStyle(fontSize: 22, color: tokens.ink3),
        // Two independent affordances, not an either/or. The `⌘K` chip is
        // keyboard-only; the close button is gated on touch because a
        // **tablet** — touch, but not `isPhone` — reaches this card from the
        // sidebar's Search box (itself mounted on `Env.isTouchPrimary`) and
        // would otherwise have no visible way out of it. A phone never gets
        // here: it gets the full-screen page, whose back arrow closes it. The
        // slot is only ever empty on a hypothetical keyboardless non-touch
        // platform, which does not exist.
        suffixIcon: Padding(
          padding: EdgeInsetsDirectional.only(end: touch ? 4 : 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // One cap per glyph — `[⌘][K]`, not a single `⌘K` cap, which
              // rendered `CtrlK` with no gap on Windows and Linux. Default
              // ink, like every other KeyCap in the app; this chip was the
              // only dimmed one (invoiceninja/flutter#103). The user's own
              // binding, so a rebound palette shows what they set and an
              // unbound one shows nothing.
              if (_paletteGlyphs(context) case final keys?)
                KeyCapRow(keys: keys),
              if (touch)
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  color: tokens.ink3,
                  tooltip: context.tr('close'),
                  // Closes, always — it deliberately does not double as a
                  // clear. One glyph meaning two things left no one-tap exit;
                  // the phone page has room for both, and its clear goes
                  // through `_reset`.
                  onPressed: () => Navigator.of(context).pop(),
                  // Unstyled, M3 resolves `tapTargetSize` from the theme
                  // — `padded` on the only platforms this renders on —
                  // and lays the button out at 48, which the zeroed
                  // `suffixIconConstraints` cannot prevent (they remove a
                  // minimum, not a maximum). Pinned per CLAUDE.md trap 5;
                  // the glyph then sits 4 + (44 − 22) / 2 = 15 px in.
                  style: IconButton.styleFrom(
                    fixedSize: const Size(
                      InSizes.touchTarget,
                      InSizes.touchTarget,
                    ),
                    minimumSize: Size.zero,
                    maximumSize: Size.infinite,
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
      ),
    );
  }

  /// One row of either list — a result, a "Show all", a Recent — sharing the
  /// highlight, hover, tap and screen-reader shape.
  ///
  /// The highlight follows the pointer only when the pointer MOVES
  /// (`onHover`, not `onEnter`): a category bar appearing or a group growing
  /// slides rows under a resting cursor, and `onEnter` then stole the
  /// selection from the keyboard.
  Widget _tile(
    BuildContext context, {
    required bool selected,
    required bool touch,
    required IconData? icon,
    required Widget title,
    required String semanticsLabel,
    required VoidCallback onSelect,
    required VoidCallback onTap,
    String? subtitle,
    bool subtitleIsValue = false,
    String? trailing,
    Color? iconColor,
  }) {
    final tokens = context.inTheme;
    final painted = selected && (!touch || _keyboardNav);
    final subtitleStyle = TextStyle(fontSize: 12, color: tokens.ink3);
    return MouseRegion(
      onHover: (_) {
        if (!selected) onSelect();
      },
      child: Semantics(
        button: true,
        // What is painted, not what Enter would open: on touch nothing is
        // highlighted until an arrow key, and a screen reader saying
        // "selected" over a row that looks like every other one is a claim
        // the screen does not make.
        selected: painted,
        label: semanticsLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: Padding(
          key: selected ? _selRowKey : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: painted ? tokens.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(InRadii.r2),
              ),
              child: ConstrainedBox(
                // A floor, never a fixed height (CLAUDE.md § Design system).
                constraints: BoxConstraints(
                  minHeight: touch ? InSizes.touchTarget : 0,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 20,
                          color:
                              iconColor ??
                              (painted ? tokens.accentInk : tokens.ink2),
                        ),
                        SizedBox(width: InSpacing.md(context)),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            if (subtitle != null && subtitle.isNotEmpty)
                              // An email reads left to right in every
                              // language (CLAUDE.md § Localization).
                              subtitleIsValue
                                  ? LtrText(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: subtitleStyle,
                                    )
                                  : Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: subtitleStyle,
                                    ),
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        SizedBox(width: InSpacing.md(context)),
                        Text(
                          trailing,
                          style: TextStyle(fontSize: 12, color: tokens.ink3),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A row's title, its matched runs bold — without them an Elasticsearch
  /// fuzzy hit (Pouros for "Pro") reads as a random row.
  Widget _title(BuildContext context, PaletteHit hit) {
    final tokens = context.inTheme;
    final base = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: tokens.ink,
    );
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in hit.matches) {
      if (start > at) spans.add(TextSpan(text: hit.title.substring(at, start)));
      spans.add(TextSpan(text: hit.title.substring(start, end), style: bold));
      at = end;
    }
    if (at < hit.title.length) {
      spans.add(TextSpan(text: hit.title.substring(at)));
    }
    // A document number or an email is a value: laid out left to right in
    // every language, as `LtrText` would (CLAUDE.md § Localization) — which
    // takes a plain string, and this title carries its bold runs.
    final ambient = Directionality.of(context);
    final ltrValue = ambient == TextDirection.rtl && _isValueTitle(hit);
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: ltrValue ? TextDirection.ltr : null,
      textAlign: ltrValue ? physicalTextAlign(TextAlign.start, ambient) : null,
    );
  }

  /// Whether [hit]'s title is a value rather than a name: a document's
  /// number, or the email a nameless contact reads as.
  static bool _isValueTitle(PaletteHit hit) =>
      (hit.number != null && hit.title == hit.number) ||
      _kEmailShape.hasMatch(hit.title);

  static final _kEmailShape = RegExp(r'^[^\s@]+@[^\s@]+$');

  IconData _iconFor(SearchResult r, EntityRegistry registry) {
    final type = entityTypeForSearchGroup(r.group);
    final settingsHit = _settingsHitOf[r];
    return r.group == kDeepLinkSearchGroup
        ? Icons.link
        : r.group == kReportsSearchGroup
        ? Icons.bar_chart_outlined
        : r.group == kWelcomeSearchGroup
        ? Icons.waving_hand_outlined
        : r.group == kWhatsNewSearchGroup
        ? Icons.new_releases_outlined
        : r.group == kRateAppSearchGroup
        ? Icons.star_outline
        : r.group == kCompanySearchGroup
        ? (r.id.isEmpty ? Icons.unfold_more : Icons.business_outlined)
        : r.group == kHelpSearchGroup
        ? switch (r.id) {
            _kHelpUserGuide => Icons.help_outline,
            _kHelpForum => Icons.forum_outlined,
            _ => Icons.mail_outline,
          }
        : settingsHit?.section.icon ??
              (type != null ? registry[type]?.effectiveOutlinedIcon : null) ??
              Icons.settings_outlined;
  }

  /// A group heading — a screen-reader heading too, so the list can be
  /// walked group by group.
  Widget _header(BuildContext context, String scope) {
    final tokens = context.inTheme;
    return Semantics(
      header: true,
      headingLevel: 2,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 6),
        child: Text(
          context.tr(scope),
          style: TextStyle(
            // 12.5 / ink2: the 11-px ink3 it was measured under 4.5:1 on the
            // translucent card in some palettes.
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: tokens.ink2,
          ),
        ),
      ),
    );
  }

  Widget _itemWidget(
    BuildContext context,
    PaletteItem item, {
    required bool touch,
    required EntityRegistry registry,
  }) {
    final tokens = context.inTheme;
    void selectThis() => setState(() => _selectedKey = item.key);
    void activate() {
      setState(() => _selectedKey = item.key);
      unawaited(_select(tapped: true));
    }

    switch (item) {
      case PaletteHeader():
        return _header(context, item.scope);
      case PaletteNoMatches():
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Center(
            child: Text(
              context.tr('no_records_found'),
              style: TextStyle(color: tokens.ink3),
            ),
          ),
        );
      case PaletteRow():
        final hit = item.hit;
        final r = hit.source;
        final settingsHit = _settingsHitOf[r];
        final l10n = Localization.of(context);
        // A settings row names its section, or six "Email" rows from six
        // pages would be indistinguishable.
        final subtitle = settingsHit != null && l10n != null
            ? settingsHitSubtitle(settingsHit, l10n)
            : hit.subtitle;
        final scopeLabel = context.tr(hit.scope);
        return _tile(
          context,
          selected: item.key == _selectedKey,
          touch: touch,
          icon: _iconFor(r, registry),
          title: _title(context, hit),
          subtitle: subtitle,
          subtitleIsValue:
              settingsHit == null &&
              subtitle != null &&
              _kEmailShape.hasMatch(subtitle.trim()),
          // A top hit comes from any category, so it says which.
          trailing: item.inTopHits ? scopeLabel : null,
          semanticsLabel: [
            hit.title,
            if (subtitle != null && subtitle.isNotEmpty) subtitle,
            scopeLabel,
          ].join(', '),
          onSelect: selectThis,
          onTap: activate,
        );
      case PaletteShowAll():
        final label = context.tr('show_all_count', {'count': '${item.count}'});
        return _tile(
          context,
          selected: item.key == _selectedKey,
          touch: touch,
          // Material's chevrons mirror themselves in a right-to-left locale.
          icon: Icons.chevron_right,
          iconColor: tokens.accentInk,
          title: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.accentInk,
            ),
          ),
          semanticsLabel: '$label, ${context.tr(item.scope)}',
          onSelect: selectThis,
          onTap: activate,
        );
      case PaletteSearchList():
        final label = context.tr('search_list_for', {
          'list': context.tr(item.scope),
          'query': _query.trim(),
        });
        return _tile(
          context,
          selected: item.key == _selectedKey,
          touch: touch,
          icon: Icons.manage_search,
          iconColor: tokens.accentInk,
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.accentInk,
            ),
          ),
          semanticsLabel: label,
          onSelect: selectThis,
          onTap: activate,
        );
      case PaletteBackToAll():
        final label = context.tr(
          item.count == 1 ? 'show_one_result_in_all' : 'show_results_in_all',
          {'count': '${item.count}'},
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.tr('no_records_found'),
                style: TextStyle(color: tokens.ink3),
              ),
            ),
            _tile(
              context,
              selected: item.key == _selectedKey,
              touch: touch,
              icon: Icons.chevron_left,
              iconColor: tokens.accentInk,
              title: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.accentInk,
                ),
              ),
              semanticsLabel: label,
              onSelect: selectThis,
              onTap: activate,
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    // Same gate `showCommandPalette` uses to pick the presentation, resolved
    // again because that local lives in the dialog builder's scope, not this
    // one. Both reads are per-build on purpose — see the note there about the
    // caller's (popped) drawer context and about live resizes.
    final page = paletteUsesPage(context);
    // Deliberately a *different* question from `page`. `page` asks "is this
    // window too small for the card"; `touch` asks "can this device tap" — it
    // hides the keyboard hints (a narrow DESKTOP window keeps them), gates
    // the card's close button and the soft keyboard's Search behaviour.
    final touch = Env.isTouchPrimary;
    final services = context.read<Services>();
    final registry = services.entityRegistry;
    _recents = services.recentlyViewed.items;
    final hasResults = !_view.isEmpty;
    final resting =
        !_loading && _view.isEmpty && _controller.text.trim().isEmpty;
    final showRecent = resting && _recents.isNotEmpty;
    final items = _view.items;
    final showBar = _barShown && !resting && _link == null;

    // Everything below the field, shared by both presentations: the card
    // stacks it under the field in one `Column`, the page puts it in the
    // `Scaffold` body while the field sits in the `AppBar`.
    final sections = <Widget>[
      if (!resting) ...[
        Container(height: 1, color: tokens.border.withValues(alpha: 0.6)),
        if (showBar)
          SearchPaletteScopeBar(
            scopes: [
              PaletteScope('all', _view.total, atLeast: _view.totalAtLeast),
              ..._barScopes,
            ],
            selectedId: _scope ?? 'all',
            tapGroup: _tapGroup,
            // The page is `Dialog.fullscreen` on `bg`; the card is `surface`.
            fadeColor: page ? tokens.bg : tokens.surface,
            onSelect: (id) =>
                _setScope(id == 'all' ? null : id, announce: true),
          ),
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Flexible(
          child: hasResults
              ? ListView.builder(
                  addAutomaticKeepAlives: false,
                  controller: _scrollController,
                  shrinkWrap: true,
                  keyboardDismissBehavior: touch
                      ? ScrollViewKeyboardDismissBehavior.onDrag
                      : ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  itemCount: items.length,
                  itemBuilder: (context, idx) => _itemWidget(
                    context,
                    items[idx],
                    touch: touch,
                    registry: registry,
                  ),
                )
              // Nothing to report while the request is still out — the
              // progress bar above already says so. `_run` sets `_loading`
              // without clearing the results, so an ungated empty state
              // filled the whole page with "No records found" on every
              // search started from rest, then replaced itself a moment
              // later. Invisible in the 520-px card; not on a 915-px one.
              : _loading
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Center(
                    child: Text(
                      context.tr('no_records_found'),
                      style: TextStyle(color: tokens.ink3),
                    ),
                  ),
                ),
        ),
        if (!touch) ..._keyboardHints(context),
      ],
      if (showRecent) ...[
        Container(height: 1, color: tokens.border.withValues(alpha: 0.6)),
        Flexible(
          child: ListView(
            addAutomaticKeepAlives: false,
            controller: _scrollController,
            shrinkWrap: true,
            keyboardDismissBehavior: touch
                ? ScrollViewKeyboardDismissBehavior.onDrag
                : ScrollViewKeyboardDismissBehavior.manual,
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            children: [
              _header(context, 'recently_viewed'),
              for (var i = 0; i < _recents.length; i++)
                _tile(
                  context,
                  selected: i == _selected,
                  touch: touch,
                  icon:
                      registry[_recents[i].type]?.effectiveOutlinedIcon ??
                      Icons.history,
                  title: Text(
                    _recents[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: tokens.ink,
                    ),
                  ),
                  semanticsLabel: _recents[i].label,
                  onSelect: () => setState(() => _selected = i),
                  onTap: () {
                    setState(() => _selected = i);
                    unawaited(_select(tapped: true));
                  },
                ),
            ],
          ),
        ),
        if (!touch) ..._keyboardHints(context),
      ],
    ];

    if (page) {
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          appBar: AppBar(
            // Structural close, not history back — this is a modal route, so
            // CLAUDE.md's "a close affordance must go() to the URL-parent"
            // rule (which is about in-shell chrome) does not apply. Matches
            // `FilterEntrySheet`, the narrow-list search page.
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: context.tr('close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            titleSpacing: 0,
            title: _buildField(context, page: true, touch: touch),
            actions: [
              // Listens to the controller on its own so a keystroke rebuilds
              // one icon rather than the whole result list.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: context.tr('clear'),
                        onPressed: _reset,
                      ),
              ),
            ],
          ),
          body: SafeArea(top: false, child: Column(children: sections)),
        ),
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField(context, page: false, touch: touch),
          ...sections,
        ],
      ),
    );
  }
}
