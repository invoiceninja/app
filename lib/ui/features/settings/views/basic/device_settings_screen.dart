import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/default_items_tab_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/list_density_controller.dart';
import 'package:admin/app/resync_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/show_seconds_controller.dart';
import 'package:admin/app/spell_check_controller.dart';
import 'package:admin/app/text_scale_controller.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/in_segmented.dart';
import 'package:admin/ui/core/widgets/spell_check.dart';
import 'package:admin/ui/core/widgets/watch_builder.dart';
import 'package:admin/ui/features/settings/settings_actions.dart';
import 'package:admin/ui/features/settings/views/advanced/e_invoice/e_invoice_constants.dart';
import 'package:admin/ui/features/settings/widgets/assigned_users_section.dart';
import 'package:admin/ui/features/settings/widgets/biometric_toggle_tile.dart';
import 'package:admin/ui/features/settings/widgets/confirm_actions_tile.dart';
import 'package:admin/ui/features/settings/widgets/card_reader_section.dart';
import 'package:admin/ui/features/settings/widgets/contacts_sync_section.dart';
import 'package:admin/ui/features/settings/widgets/customize_colors_section.dart';
import 'package:admin/ui/features/settings/widgets/dashboard_panels_section.dart';
import 'package:admin/ui/features/settings/widgets/downloads_folder_section.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/home_widgets_section.dart';
import 'package:admin/ui/features/settings/widgets/list_status_tabs_section.dart';
import 'package:admin/ui/features/settings/widgets/local_data_copies.dart';
import 'package:admin/ui/features/settings/widgets/desktop_app_section.dart';
import 'package:admin/ui/features/settings/widgets/mobile_app_section.dart';
import 'package:admin/ui/features/settings/widgets/phone_actions_section.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_screen_scaffold.dart';
import 'package:admin/ui/features/settings/widgets/sidebar_counters_section.dart';
import 'package:admin/ui/features/settings/widgets/sidebar_menu_section.dart';
import 'package:admin/ui/features/settings/widgets/theme_tile.dart';
import 'package:admin/ui/features/settings/widgets/trusted_certificates_section.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/utils/router_state.dart';
import 'package:admin/ui/features/settings/widgets/settings_tab_strip.dart';
import 'package:admin/app/after_saving_controller.dart';
import 'package:admin/ui/core/edit/after_saving.dart';

// Search keys for the settings search, one list per tab. Colocated with the
// screen so adding / renaming a field updates both ends in one place (see
// `search_catalog_consistency_test`). A tab's own label (`appearance`,
// `security`, …) is its `SettingsSearchTab.titleKey`, so it is not repeated
// here.

/// Appearance tab (the bare URL): theme, what a list shows, the dashboard and
/// the rail.
const kDeviceSettingsAppearanceSearchKeys = <String>[
  'appearance_help',
  'theme',
  'palette',
  'font_size',
  'display_density',
  'customize_colors',
  'lists_and_dashboard',
  'lists_and_dashboard_help',
  ...kListStatusTabsSearchKeys,
  'show_seconds',
  'hide_peppol_sent_status',
  ...kDashboardPanelsSearchKeys,
  ...kSidebarMenuSearchKeys,
  ...kSidebarCountersSearchKeys,
  ...kSidebarBadgeModeSearchKeys,
];

/// Security tab: the guard rails, and the certificates trusted past a refusal.
const kDeviceSettingsSecuritySearchKeys = <String>[
  'safeguards',
  'safeguards_help',
  'confirm_actions',
  'confirm_actions_help',
  'biometric_authentication',
  ...kTrustedCertificatesSearchKeys,
];

/// Phone tab: outgoing calls, incoming calls, the home screen, and — away from
/// a phone — the way to the phone app.
const kDeviceSettingsPhoneSearchKeys = <String>[
  ...kPhoneActionsSearchKeys,
  ...kContactsSyncSearchKeys,
  ...kHomeWidgetsSearchKeys,
  ...kCardReaderSearchKeys,
  ...kMobileAppSearchKeys,
  ...kDesktopAppSearchKeys,
];

/// Forms tab: what an edit screen offers.
const kDeviceSettingsFormsSearchKeys = <String>[
  'after_saving',
  'after_saving_help',
  'edit_record',
  'view_record',
  'items_section_help',
  'default_tab',
  'spell_check',
  ...kAssignedUsersSearchKeys,
];

/// Data tab: Sync, the kept copies, and where a download is written.
const kDeviceSettingsDataSearchKeys = <String>[
  'sync',
  // Absorbed from Account Management → Overview, which used to carry its own
  // Data card firing the same action (invoiceninja/flutter#71). Kept
  // searchable under the old name so "force full sync" still finds it.
  'force_full_sync',
  ...kLocalDataCopiesSearchKeys,
  ...kDownloadsFolderSearchKeys,
];

/// The tab slugs below the bare URL, in display order — the `:tab(…)`
/// alternation `settings_routes.dart` registers. The first tab (Appearance)
/// is the bare `/settings/device_settings`.
const kDeviceSettingsTabSlugs = <String>['security', 'phone', 'forms', 'data'];

/// Whether [company] sends by PEPPOL — the one case the Hide Peppol Sent
/// Status row renders, and so the one case settings search offers it.
bool peppolStatusSectionShown(Company? company) =>
    company?.settings.eInvoiceType == kEInvoiceTypePEPPOL;

const String _kBasePath = '/settings/device_settings';

class _TabDef {
  const _TabDef({required this.slug, required this.labelKey});
  final String slug;
  final String labelKey;
}

const _kTabs = <_TabDef>[
  _TabDef(slug: '', labelKey: 'appearance'),
  _TabDef(slug: 'security', labelKey: 'security'),
  _TabDef(slug: 'phone', labelKey: 'phone'),
  _TabDef(slug: 'forms', labelKey: 'forms'),
  _TabDef(slug: 'data', labelKey: 'data'),
];

/// Settings → Device Settings: the device-local, no-save controls. Unlike most
/// settings screens it has no cascade and no save bar — every control writes
/// immediately to a device-local store (`DevicePrefsStore`). The theme,
/// palette and custom colours also follow the user to their other devices
/// (`AppearanceSyncController`); the accent colour is server-synced per
/// company and lives on User Details → Preferences with the save bar.
///
/// Five URL-driven tabs (`docs/settings-screens.md` § Device Settings is
/// tabbed, and every tab opens with a card that always renders):
///
/// * `/settings/device_settings` → Appearance (default).
/// * `/settings/device_settings/security` → Security.
/// * `/settings/device_settings/phone` → Phone.
/// * `/settings/device_settings/forms` → Forms.
/// * `/settings/device_settings/data` → Data.
///
/// Pairs with `tabbedSettingsRoutePair(...)` in `settings_routes.dart`, so the
/// tab is the route — restored on restart like every tabbed settings screen's.
/// No VM, because no tab has a draft to save (`AccountManagementShell` is the
/// same shape).
class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key, this.initialTab});

  /// The `:tab` path-parameter from the route, or null on the bare URL
  /// (defaults to Appearance).
  final String? initialTab;

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: _kTabs.length,
      vsync: this,
      initialIndex: _indexForSlug(widget.initialTab),
    );
    _controller.addListener(_onTabSettled);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabSettled);
    _controller.dispose();
    super.dispose();
  }

  void _onTabSettled() {
    if (_controller.indexIsChanging) return;
    final tab = _kTabs[_controller.index];
    final desired = tab.slug.isEmpty ? _kBasePath : '$_kBasePath/${tab.slug}';
    final current = routerStateOf(context).uri.path;
    if (current == desired) return;
    context.go(desired);
  }

  int _indexForSlug(String? slug) {
    if (slug == null || slug.isEmpty) return 0;
    for (var i = 0; i < _kTabs.length; i++) {
      if (_kTabs[i].slug == slug) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the controller in sync if the URL changed externally (back
    // button, deep link, settings search). The `!=` guard prevents the
    // controller listener (which pushes URL updates) from looping back.
    final currentTab = routerStateOf(context).pathParameters['tab'];
    final urlIndex = _indexForSlug(currentTab);
    if (urlIndex != _controller.index && !_controller.indexIsChanging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (urlIndex != _controller.index) _controller.animateTo(urlIndex);
      });
    }

    final tokens = context.inTheme;
    return SettingsScreenScaffold(
      titleKey: 'device_settings',
      bottom: SettingsTabStrip(
        tabBar: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // No start inset, unlike the other settings strips: the five tabs
          // fit a 360 px phone with 4 px to spare, and the inset that would
          // line the first label up with the content costs 12.
          // 12 a side, not Material's 16: five tabs at 16 ran 6 px past a 390 px
          // phone, so the strip scrolled to hide a sliver of "Data". At 12 they
          // fit down to a 360 px phone in English (docs/pane-width-and-overflow.md
          // § A tab strip is a width budget); longer translations still scroll.
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelColor: tokens.ink,
          unselectedLabelColor: tokens.ink3,
          indicatorColor: tokens.accent,
          indicatorWeight: 2,
          tabs: [for (final tab in _kTabs) Tab(text: context.tr(tab.labelKey))],
        ),
      ),
      // Every tab opens with a card that renders on every platform, so none
      // is ever empty when the platform-gated cards hide themselves.
      body: TabBarView(
        controller: _controller,
        children: const [
          _AppearanceTab(),
          _SecurityTab(),
          _PhoneTab(),
          _FormsTab(),
          _DataTab(),
        ],
      ),
    );
  }
}

/// The page's one line: where these settings live. Worded so it stays true of
/// every key on the page — some are forgotten at a sign-out
/// (`PrefScope.account`, docs/device-preferences.md), so it promises where
/// they are kept, never for how long — and names the ones that also follow
/// the account (invoiceninja/app#199), each marked on its own row too.
String deviceSettingsSubtitle(BuildContext context) => context.tr(
  kIsWeb
      ? 'device_settings_subtitle_synced_look_web'
      : 'device_settings_subtitle_synced_look',
);

/// How the app looks and what its screens show, in three sections:
/// Appearance (theme, palette, font size, density, custom colours), Lists &
/// dashboard (the switches about what a list or the dashboard shows), and
/// Main menu (its layout and order, then its counters). Main menu closes the
/// tab — its counters alone can render 14 rows, so anything after them is a
/// long way down on a phone.
class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab();

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    return SettingsFormShell(
      subtitle: deviceSettingsSubtitle(context),
      sections: [
        FormSection(
          title: context.tr('appearance'),
          description: context.tr('appearance_help'),
          flush: true,
          children: [
            ThemeTile(controller: services.theme),
            const SettingRowDivider(),
            _FontSizeRow(controller: services.textScale),
            const SettingRowDivider(),
            _ListDensityRow(controller: services.listDensity),
            const SettingRowDivider(),
            CustomizeColorsSection(controller: services.theme),
          ],
        ),
        const _ListsSection(),
        const SidebarMenuSection(),
        const SidebarCountersSection(),
      ],
    );
  }
}

/// The guard rails, then the certificates trusted past a refusal.
class _SecurityTab extends StatefulWidget {
  const _SecurityTab();

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  // Resolved once on mount so the card shows the biometric row only where it
  // means something. The card itself always renders now that "Confirm
  // actions" lives in it — both are guard rails (one against unintended
  // access, one against unintended changes), and on desktop, where biometrics
  // are unavailable, the tab would otherwise be empty.
  late final Future<bool> _biometricAvailable = context
      .read<Services>()
      .biometric
      .isAvailable();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _biometricAvailable,
      builder: (context, snap) => SettingsFormShell(
        sections: [
          // Not "Security": that would only repeat the tab.
          FormSection(
            title: context.tr('safeguards'),
            description: context.tr('safeguards_help'),
            flush: true,
            children: withSettingDividers([
              const ConfirmActionsTile(),
              if (snap.data == true) const BiometricToggleTile(),
            ]),
          ),
          // Hides itself unless a server certificate has been trusted — and
          // always on web, where the browser owns certificates.
          const TrustedCertificatesSection(),
        ],
      ),
    );
  }
}

/// The phone cards, together: outgoing calls, incoming calls, the home screen,
/// and — everywhere but a phone — the way to the phone app.
class _PhoneTab extends StatelessWidget {
  const _PhoneTab();

  @override
  Widget build(BuildContext context) {
    return const SettingsFormShell(
      sections: [
        // Renders everywhere, so the tab is never empty: a macOS user with
        // FaceTime, or Windows with Phone Link, has a working dialer too.
        PhoneActionsSection(),
        // Native mobile only — hides itself where the app can't write the
        // address book (desktop, web).
        ContactsSyncSection(),
        // iOS, Android and macOS: how to add the home-screen widgets, which
        // nothing else in the app mentions.
        HomeWidgetsSection(),
        // The store build of the mobile app: Tap to Pay and card readers for
        // in-person card payments.
        CardReaderSection(),
        // Everywhere *but* a phone: the way to the phone app that does the
        // cards above.
        MobileAppSection(),
        // And on a phone, the way to the desktop app.
        DesktopAppSection(),
      ],
    );
  }
}

/// What an edit screen offers: what Save does next, the items table, and
/// who an assignee field lists.
class _FormsTab extends StatelessWidget {
  const _FormsTab();

  @override
  Widget build(BuildContext context) {
    return const SettingsFormShell(
      sections: [
        _AfterSavingSection(),
        _ItemsSection(),
        AssignedUsersSection(),
      ],
    );
  }
}

/// "After Saving": whether Save keeps an edit screen open (Edit Record) or
/// goes to the record (View Record) — docs/after-saving.md,
/// invoiceninja/app#202. Two choices, so both stay in view (CLAUDE.md
/// § Two-choice fields). The selection shown is the effective one, so an
/// untouched setting reads as this device's automatic answer.
class _AfterSavingSection extends StatelessWidget {
  const _AfterSavingSection();

  @override
  Widget build(BuildContext context) {
    final afterSaving = context.read<AfterSavingController?>();
    if (afterSaving == null) return const SizedBox.shrink();
    return FormSection(
      title: context.tr('save'),
      flush: true,
      children: [
        ValueListenableBuilder<bool?>(
          valueListenable: afterSaving,
          builder: (context, _, _) => SettingRow(
            icon: const Icon(Icons.save_outlined),
            title: context.tr('after_saving'),
            subtitle: context.tr('after_saving_help'),
            control: InSegmented<bool>(
              segments: [
                InSegment(value: true, label: context.tr('edit_record')),
                InSegment(value: false, label: context.tr('view_record')),
              ],
              selected: afterSaving.staysIn(context),
              onChanged: (stay) => afterSaving.setIn(context, stay),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sync and the kept copies, then where a desktop download is written.
class _DataTab extends StatelessWidget {
  const _DataTab();

  @override
  Widget build(BuildContext context) {
    return const SettingsFormShell(
      sections: [
        _DataSection(),
        // Desktop only: where a download is written.
        DownloadsFolderSection(),
      ],
    );
  }
}

/// "Items": the two settings about a billing document's items table — which
/// items tab it opens on (React #3355) and whether its line items underline
/// spelling mistakes (docs/spell-check.md). One card, since both act on the
/// same table; they used to be two cards of one control each.
class _ItemsSection extends StatelessWidget {
  const _ItemsSection();

  @override
  Widget build(BuildContext context) {
    final defaultTab = context.read<Services>().defaultItemsTab;
    final spellCheck = context.read<SpellCheckController?>();
    return FormSection(
      title: context.tr('items'),
      description: context.tr('items_section_help'),
      flush: true,
      children: withSettingDividers([
        // "Default tab": which items tab (Products / Tasks) an invoice, quote
        // or recurring invoice opens on when its own lines don't decide. Two
        // choices, so both stay in view (CLAUDE.md § Two-choice fields).
        ValueListenableBuilder<String>(
          valueListenable: defaultTab,
          builder: (context, _, _) => SettingRow(
            icon: const Icon(Icons.tab_outlined),
            title: context.tr('default_tab'),
            subtitle: context.tr('default_tab_help'),
            control: InSegmented<String>(
              segments: [
                InSegment(
                  value: kItemsTabProducts,
                  label: context.tr('products'),
                ),
                InSegment(value: kItemsTabTasks, label: context.tr('tasks')),
              ],
              // Derived from `prefersTasks`, so a stored value this build
              // doesn't know still selects a choice (Products) rather than
              // none.
              selected: defaultTab.prefersTasks
                  ? kItemsTabTasks
                  : kItemsTabProducts,
              onChanged: defaultTab.set,
            ),
          ),
        ),
        // Only where the platform has a checker (not Linux, not web) —
        // elsewhere the switch would toggle nothing.
        if (spellCheck != null && platformSupportsSpellCheck)
          ValueListenableBuilder<bool>(
            valueListenable: spellCheck,
            builder: (context, enabled, _) => SettingRow.toggle(
              icon: const Icon(Icons.spellcheck_outlined),
              title: context.tr('spell_check'),
              subtitle: context.tr('spell_check_help'),
              value: enabled,
              onChanged: spellCheck.set,
            ),
          ),
      ]),
    );
  }
}

/// "Lists & dashboard": the switches about what a list or the dashboard
/// shows — the status tab strip, seconds on the task surfaces, (for a PEPPOL
/// company) the sent mark on the invoice and credit lists, and hiding empty
/// dashboard panels.
///
/// The company is watched here, around the card, rather than inside the
/// PEPPOL row: a row that renders nothing would still cost the card a divider.
class _ListsSection extends StatelessWidget {
  const _ListsSection();

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    if (companyId.isEmpty) return _card(context, peppol: false);
    return WatchBuilder<Company?>(
      cacheKey: companyId,
      create: () => services.company.watchCompany(companyId),
      builder: (context, snapshot) =>
          _card(context, peppol: peppolStatusSectionShown(snapshot.data)),
    );
  }

  Widget _card(BuildContext context, {required bool peppol}) {
    final services = context.read<Services>();
    final showSeconds = context.read<ShowSecondsController?>();
    final hidePeppol = services.hidePeppolStatus;
    return FormSection(
      title: context.tr('lists_and_dashboard'),
      description: context.tr('lists_and_dashboard_help'),
      flush: true,
      children: withSettingDividers([
        const ListStatusTabsTile(),
        // "Show Seconds": add seconds where the Tasks surfaces leave them out
        // — the kanban cards, a timer past a day, a time entry's start and end
        // (docs/tasks-views.md). Running timers tick seconds either way.
        if (showSeconds != null)
          ValueListenableBuilder<bool>(
            valueListenable: showSeconds,
            builder: (context, enabled, _) => SettingRow.toggle(
              icon: const Icon(Icons.timer_outlined),
              title: context.tr('show_seconds'),
              subtitle: context.tr('show_seconds_help'),
              value: enabled,
              onChanged: showSeconds.set,
            ),
          ),
        // "Hide Peppol Sent Status": the sent / failed mark beside the status
        // on the invoice and credit lists (React ui#3410). Only while the
        // active company sends by PEPPOL, the one case where there is a mark
        // to hide.
        if (peppol)
          ValueListenableBuilder<bool>(
            valueListenable: hidePeppol,
            builder: (context, hidden, _) => SettingRow.toggle(
              icon: const Icon(Icons.send_outlined),
              title: context.tr('hide_peppol_sent_status'),
              value: hidden,
              onChanged: hidePeppol.set,
            ),
          ),
        const HideEmptyPanelsTile(),
      ]),
    );
  }
}

/// Device-local UI text-scale picker: four "A"s of increasing size, one per
/// [kTextScaleOptions] step (Small / Normal / Large / Extra Large), each
/// named for a screen reader; the step in effect is the row's subtitle, as
/// the Theme row names its mode.
class _FontSizeRow extends StatelessWidget {
  const _FontSizeRow({required this.controller});

  final TextScaleController controller;

  /// The glyph's size per step, relative to the text around it.
  static const _glyphSizes = <double>[11, 13, 15, 17];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: controller,
      builder: (context, scale, _) {
        final current = nearestTextScaleOption(scale);
        return SettingRow(
          icon: const Icon(Icons.format_size_outlined),
          title: context.tr('font_size'),
          subtitle: context.tr(textScaleLabelKey(current)),
          control: InSegmented<double>(
            segmentWidth: 52,
            segments: [
              for (var i = 0; i < kTextScaleOptions.length; i++)
                InSegment(
                  value: kTextScaleOptions[i],
                  label: context.tr(textScaleLabelKey(kTextScaleOptions[i])),
                  glyph: Text(
                    'A',
                    style: TextStyle(fontSize: _glyphSizes[i], height: 1),
                  ),
                ),
            ],
            // Snapped to the nearest preset, so an off-by-epsilon stored
            // value still selects a step.
            selected: current,
            onChanged: controller.set,
          ),
        );
      },
    );
  }
}

/// Device-local density (Normal / Compact) — how tightly lists, record pages
/// and the dashboard pack their content. Labelled "Density" rather than "List
/// density" since it reaches past lists; the pref key and the `ListDensity*`
/// names are historical. Next to Font Size, the other "how much fits on
/// screen" control, and the same control the first-run Welcome offers. The
/// subtitle says what the setting is for, since the selected segment already
/// says which one is on. See `docs/list-density.md`.
class _ListDensityRow extends StatelessWidget {
  const _ListDensityRow({required this.controller});

  final ListDensityController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: controller,
      builder: (context, _, _) => SettingRow(
        icon: const Icon(Icons.density_medium_outlined),
        title: context.tr('display_density'),
        subtitle: context.tr('display_density_help'),
        control: InSegmented<bool>(
          segments: [
            InSegment(value: false, label: context.tr('normal')),
            InSegment(value: true, label: context.tr('compact')),
          ],
          // Derived from `isCompact`, so a stored value this build doesn't
          // know still selects a segment (Normal) rather than none.
          selected: controller.isCompact,
          onChanged: controller.setCompact,
        ),
      ),
    );
  }
}

/// The [kTextScaleOptions] entry closest to [scale] — guards the picker
/// against a stored value that isn't exactly one of the four presets.
@visibleForTesting
double nearestTextScaleOption(double scale) => kTextScaleOptions.reduce(
  (a, b) => (scale - a).abs() <= (scale - b).abs() ? a : b,
);

class _DataSection extends StatefulWidget {
  const _DataSection();

  @override
  State<_DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<_DataSection> {
  int? _lastSyncAt;
  Timer? _ticker;
  late final ResyncController _resync;
  late bool _wasRunning;

  @override
  void initState() {
    super.initState();
    _loadLastSync();
    _resync = context.read<Services>().resync;
    _wasRunning = _resync.isRunning;
    _resync.addListener(_onResyncChanged);
    // Keep the relative "last updated" label fresh while the screen is open
    // ("just now" → "2m ago") without needing a manual refresh.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _resync.removeListener(_onResyncChanged);
    _ticker?.cancel();
    super.dispose();
  }

  /// Re-read the high-water mark whenever *any* pass ends, not just one this
  /// screen started — the sidebar Sync button can finish a pass while this
  /// screen is open, and a stale "Last Updated" is exactly the staleness it's
  /// there to report.
  void _onResyncChanged() {
    final running = _resync.isRunning;
    if (_wasRunning && !running) unawaited(_loadLastSync());
    _wasRunning = running;
  }

  /// Read the active company's last-sync high-water mark so the user can see
  /// how stale their local cache is. One-shot (re-read after a pass) — the
  /// value only moves on sync.
  Future<void> _loadLastSync() async {
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId;
    if (companyId == null) return;
    final row = await services.db.companiesDao.byId(companyId);
    if (mounted) setState(() => _lastSyncAt = row?.lastSyncAt);
  }

  /// In-flight state and the post-run `lastSyncAt` re-read both come from
  /// [_resync] now, so this is just the trigger.
  Future<void> _run() => SettingsActions.forceResync(context);

  @override
  Widget build(BuildContext context) {
    final lastSync = _lastSyncAt;
    final companyId =
        context.read<Services>().auth.session.value?.currentCompanyId ?? '';
    // Not "Data": that would only repeat the tab. Not flush, either: the kept
    // copies after the row render nothing at all when there are none, and in
    // a flush card they would need padding of their own that an empty list
    // would still cost (§ A card that hides itself still costs a gap).
    return FormSection(
      title: context.tr('sync'),
      // App-local key, not Transifex's `download_data` ("Press button below
      // to download the data."): en.json can't be overridden from
      // `_app_pending.json`, and that wording no longer describes the action,
      // which uploads queued edits first.
      description: context.tr('sync_data_help'),
      spacing: 0,
      children: [
        // Names the action the button performs. Absorbed from the duplicate
        // Data card on Account Management → Overview, which fired the same
        // `forceResync` from a second place (invoiceninja/flutter#71).
        SettingRow(
          icon: const Icon(Icons.cloud_sync_outlined),
          title: context.tr('force_full_sync'),
          subtitle: lastSync != null && lastSync > 0
              ? '${context.tr('last_updated')}: '
                    '${formatRelativeTime(context, DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastSync)))}'
              : null,
          stackWhenNarrow: false,
          control: ValueListenableBuilder<ResyncProgress>(
            valueListenable: _resync,
            builder: (context, p, _) {
              // Shared with the sidebar Sync button, so a pass started there
              // shows here too — and tapping can't start a competing one.
              final running = p.isRunningFor(companyId);
              return FilledButton.icon(
                // Content-sized: the themed `Size.fromHeight(44)` default is
                // an infinite min-width, which a `Row` cannot lay out.
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                onPressed: running ? null : _run,
                icon: running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(
                  running && p.total > 0
                      ? context.tr('syncing_progress', {
                          'count': '${p.completed}',
                          'total': '${p.total}',
                        })
                      : context.tr('sync'),
                ),
              );
            },
          ),
        ),
        // Last, and inside this card: it renders nothing when there are no
        // copies, which as a card of its own would leave a gap.
        const LocalDataCopies(),
      ],
    );
  }
}
