import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/default_items_tab_controller.dart';
import 'package:admin/app/hours_format_controller.dart';
import 'package:admin/app/list_density_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/sign_out_notice.dart';
import 'package:admin/app/shortcuts/key_binding.dart';
import 'package:admin/app/shortcuts/shortcut_catalog.dart';
import 'package:admin/app/text_scale_controller.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/tls/certificate_facts.dart';
import 'package:admin/domain/contacts_sync/contacts_sync_types.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/domain/sidebar_menu.dart';
import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/domain/tasks/tasks_view_mode.dart';

import '../ui/features/shell/_shell_test_helpers.dart';

/// Every device preference moved off its default through the controller that
/// owns it, then the session ends. A deliberate sign-out must leave the
/// device preferences alone and put every account preference back on its
/// default — in memory, where the UI reads it, and on disk, where the next
/// launch does; an end that keeps local data (a 401, or an idle timeout while
/// there is unsynced work) must leave both alone. An idle timeout with nothing
/// unsynced is a sign-out, `LocalDataPolicy.destroy`, like the first case.
///
/// This replaces a source scan that could only check that each controller's
/// `resetInMemory()` was *called* from the wipe hook, and that missed the
/// controllers that had never been given one. Here nothing is wired by hand:
/// the controllers follow `DevicePrefsStore`, and a key added without a probe
/// fails the first test.
class _Probe {
  const _Probe(this.change, this.isDefault);

  /// Moves the preference off its default through its owner.
  final Future<void> Function(Services s) change;

  /// Reads the owner's in-memory value.
  final bool Function(Services s) isDefault;
}

final _customInk = const Color(0xFF445566);
// Not toggle_sidebar's catalog default (⌘B): an override equal to the
// default is no override, so a probe bound to it would read "wiped" already.
final _binding = KeyBinding.logical(
  LogicalKeyboardKey.keyB.keyId,
  usesPrimary: true,
  shift: true,
);

/// In insertion order, which matters once: the light variant is changed
/// before the custom theme, because a new preset clears its side's overrides.
final Map<PrefKey<Object>, _Probe> _probes = {
  DevicePrefKeys.locale: _Probe(
    (s) => s.locale.set(const Locale('de')),
    (s) => s.locale.value == null,
  ),
  DevicePrefKeys.themeMode: _Probe(
    (s) => s.theme.setThemeMode(ThemeMode.dark),
    (s) => s.theme.themeMode == ThemeMode.system,
  ),
  DevicePrefKeys.lightVariant: _Probe(
    (s) => s.theme.setLightVariant(LightVariant.mist),
    (s) => s.theme.lightVariant == LightVariant.sand,
  ),
  DevicePrefKeys.darkVariant: _Probe(
    (s) => s.theme.setDarkVariant(DarkVariant.carbon),
    (s) => s.theme.darkVariant == DarkVariant.espresso,
  ),
  DevicePrefKeys.customTheme: _Probe(
    (s) =>
        s.theme.setCustomOverride(Brightness.dark, CustomToken.ink, _customInk),
    (s) => s.theme.customTheme == defaultCustomTheme,
  ),
  DevicePrefKeys.textScale: _Probe(
    (s) => s.textScale.set(kTextScaleLarge),
    (s) => s.textScale.value == kTextScaleNormal,
  ),
  DevicePrefKeys.keyboardShortcuts: _Probe(
    (s) async => s.keyboardShortcuts.setBinding(
      ShortcutActionIds.toggleSidebar,
      _binding,
    ),
    (s) => !s.keyboardShortcuts.isOverridden(ShortcutActionIds.toggleSidebar),
  ),
  DevicePrefKeys.sidebarBadgeModes: _Probe(
    (s) => s.sidebarBadgeModes.set(EntityType.invoice, kBadgeModeTotal),
    (s) =>
        s.sidebarBadgeModes.modeFor(EntityType.invoice) ==
        defaultBadgeModeFor(EntityType.invoice),
  ),
  DevicePrefKeys.confirmActions: _Probe(
    (s) => s.confirmActions.set(false),
    (s) => s.confirmActions.value,
  ),
  DevicePrefKeys.statusTabs: _Probe(
    (s) => s.statusTabs.set(false),
    (s) => s.statusTabs.value,
  ),
  DevicePrefKeys.contactsSync: _Probe(
    (s) => s.contactsSync.setScope(ContactsSyncScope.assignedToMe),
    (s) => s.contactsSync.scope == ContactsSyncScope.all,
  ),
  DevicePrefKeys.phoneActions: _Probe(
    (s) => s.phoneActions.setConfirmBeforeCall(true),
    (s) => !s.phoneActions.value.confirmBeforeCall,
  ),
  DevicePrefKeys.sidebarMenu: _Probe(
    (s) => s.sidebarMenu.setLayout(SidebarMenuLayout.grid),
    (s) => s.sidebarMenu.layout == SidebarMenuLayout.list,
  ),
  DevicePrefKeys.tasksView: _Probe(
    (s) => s.tasksView.set(TasksViewMode.kanban),
    (s) => s.tasksView.value == null,
  ),
  // The collapsed columns name one account's task statuses, so the board's
  // arrangement goes with the account, like the Tasks view above.
  DevicePrefKeys.kanban: _Probe(
    (s) =>
        s.kanbanPrefs.set(const KanbanPrefs(collapsedStatusIds: {'status_1'})),
    (s) => s.kanbanPrefs.value == const KanbanPrefs(),
  ),
  DevicePrefKeys.hideUnverifiedUsers: _Probe(
    (s) => s.hideUnverifiedUsers.set(true),
    (s) => !s.hideUnverifiedUsers.value,
  ),
  DevicePrefKeys.hideEmptyPanels: _Probe(
    (s) => s.hideEmptyPanels.set(false, isPhone: true),
    (s) => s.hideEmptyPanels.value == null,
  ),
  DevicePrefKeys.sidebarCollapsed: _Probe(
    (s) => s.sidebar.set(true),
    (s) => !s.sidebar.value,
  ),
  DevicePrefKeys.defaultItemsTab: _Probe(
    (s) => s.defaultItemsTab.set(kItemsTabTasks),
    (s) => s.defaultItemsTab.value == kItemsTabProducts,
  ),
  DevicePrefKeys.listDensity: _Probe(
    (s) => s.listDensity.set(kListDensityCompact),
    (s) => s.listDensity.value == kListDensityNormal,
  ),
  DevicePrefKeys.hoursFormat: _Probe(
    (s) => s.hoursFormat.set(kHoursFormatHoursMinutes),
    (s) => s.hoursFormat.value == kHoursFormatDecimal,
  ),
  DevicePrefKeys.hidePeppolStatus: _Probe(
    (s) => s.hidePeppolStatus.set(true),
    (s) => !s.hidePeppolStatus.value,
  ),
  DevicePrefKeys.trustedCertificates: _Probe(
    (s) => s.certificateTrust.trust('pay.example.com', 443, _certificate),
    (s) => s.certificateTrust.pins.isEmpty,
  ),
  // Written just before the logout it explains — which may wipe — so it has
  // to survive one.
  DevicePrefKeys.signOutNotice: _Probe(
    (s) => s.signOutNotice.record(SignOutReason.inactivity),
    (s) => s.signOutNotice.pending == null,
  ),
  // "This machine has been told" — the next person to sign in on it isn't
  // pitched the phone app again.
  // One controller runs both promos, under the key the platform picks (the
  // desktop-app promo on a phone), so each key is probed through the store.
  DevicePrefKeys.mobileAppPromo: _Probe(
    (s) => s.devicePrefs.write(DevicePrefKeys.mobileAppPromo, '{"done":true}'),
    (s) => s.devicePrefs.read(DevicePrefKeys.mobileAppPromo) == null,
  ),
  DevicePrefKeys.desktopAppPromo: _Probe(
    (s) => s.devicePrefs.write(DevicePrefKeys.desktopAppPromo, '{"done":true}'),
    (s) => s.devicePrefs.read(DevicePrefKeys.desktopAppPromo) == null,
  ),
  // "This install has shown these notes" — the next person to sign in isn't
  // told about the same update again, and the promo's day-long hold after the
  // dialog survives the sign-out too.
  DevicePrefKeys.whatsNew: _Probe(
    (s) => s.whatsNew.noteOpened(DateTime.utc(2026, 10, 14, 12)),
    (s) => s.whatsNew.state.shownAt == null,
  ),
  // Whether this machine's checker is worth the noise of flagged SKUs.
  DevicePrefKeys.spellCheck: _Probe(
    (s) => s.spellCheck.set(false),
    (s) => s.spellCheck.value,
  ),
  // How the Tasks surfaces read on this screen, like list density.
  DevicePrefKeys.showSeconds: _Probe(
    (s) => s.showSeconds.set(true),
    (s) => !s.showSeconds.value,
  ),
  // How this screen's scroll views read, like list density.
  DevicePrefKeys.alwaysShowScrollbars: _Probe(
    (s) => s.alwaysShowScrollbars.set(true),
    (s) => !s.alwaysShowScrollbars.value,
  ),
  // Whether this device spends a download per file on a thumbnail.
  DevicePrefKeys.documentThumbnails: _Probe(
    (s) => s.documentThumbnails.set(false),
    (s) => s.documentThumbnails.value,
  ),
  // How wide this screen shows each list column.
  DevicePrefKeys.listColumnWidths: _Probe(
    (s) => s.listColumnWidths.setWidth('invoice', 'client_id', 320),
    (s) => s.listColumnWidths.value.isEmpty,
  ),
  // What a signed-out user gets back on their return — the sign-out that
  // fills it must not empty it.
  DevicePrefKeys.accountPrefsKept: _Probe(
    (s) => s.devicePrefs.write(
      DevicePrefKeys.accountPrefsKept,
      '{"someone":{"tasks_view":"kanban"}}',
    ),
    (s) => s.devicePrefs.read(DevicePrefKeys.accountPrefsKept) == null,
  ),
  // A security choice about this device's owner, not the signed-in account.
  DevicePrefKeys.lockAfterInactivity: _Probe(
    (s) => s.lockAfterInactivity.set(5),
    (s) => s.lockAfterInactivity.value == 0,
  ),
  DevicePrefKeys.downloadsFolder: _Probe(
    (s) => s.downloadsFolder.set('/x'),
    (s) => s.downloadsFolder.value == '',
  ),
  // "This device has been asked" — and its install age — survive a sign-out,
  // so the next person here isn't asked the day after someone declined.
  DevicePrefKeys.reviewPrompt: _Probe(
    (s) => s.reviewPrompt.noteRatedManually(),
    (s) => !s.reviewPrompt.state.done,
  ),
  // "This device has greeted this person" — a sign-out must not make the
  // Welcome greet them again, and the promo's hold after it survives too.
  DevicePrefKeys.welcome: _Probe(
    (s) => s.welcome.noteOpened(),
    (s) => s.welcome.state.shownAt == null,
  ),
  // A reader used with one account doesn't offer card payments to the next.
  DevicePrefKeys.cardReaderUsed: _Probe(
    (s) => s.terminal.noteReaderUsed(),
    (s) => !s.terminal.readerUsed,
  ),
  // Each merchant signing in sees Apple's "How to Tap" once.
  DevicePrefKeys.howToTapShown: _Probe(
    (s) => s.terminal.markHowToTapShown(),
    (s) => s.terminal.howToTapDue,
  ),
  // Each merchant turns Tap to Pay on iPhone on for themselves.
  DevicePrefKeys.tapToPayAnnounced: _Probe(
    (s) => s.terminal.markTapToPayAnnounced(),
    (s) => !s.terminal.tapToPayAnnounced,
  ),
  // A payment still being checked belongs to the account that took it.
  DevicePrefKeys.pendingCardPayments: _Probe(
    (s) => s.terminal.notePending(
      companyId: 'co',
      invoiceId: 'inv',
      paymentIntentId: 'pi_probe',
    ),
    (s) => s.terminal.pendingFor('co', 'inv') == null,
  ),
  // "This browser has been told" — the web's idle timeout signs people out
  // on its own, and the banner must not come back each time.
  DevicePrefKeys.webAppBannerDismissed: _Probe(
    (s) => s.webAppBanner.dismiss(),
    (s) => !s.webAppBanner.dismissed,
  ),
  // How this device's editors behave after a Save — a look-and-feel choice
  // of the device, kept across a sign-out like the theme.
  DevicePrefKeys.afterSaving: _Probe(
    (s) => s.afterSaving.set(false, isPhone: false),
    (s) => s.afterSaving.value == null,
  ),
  // Whose choice the appearance was: a sign-out forgets it — the look itself
  // stays (the theme probes above) — so the next person to sign in adopts
  // their own synced one rather than racing it.
  DevicePrefKeys.appearanceSyncedAt: _Probe(
    (s) => s.theme.setThemeMode(ThemeMode.light),
    (s) => s.theme.syncedAt == null,
  ),
  // This install has met an account's synced appearance: a shared device
  // never uploads the last user's unstamped look as the next one's.
  DevicePrefKeys.appearanceSeeded: _Probe(
    (s) => s.devicePrefs.write(DevicePrefKeys.appearanceSeeded, true),
    (s) => s.devicePrefs.read(DevicePrefKeys.appearanceSeeded) != true,
  ),
  // Which teammates' comments this user has read: the next person to sign in
  // has read nothing, and the returning user gets it back.
  DevicePrefKeys.commentReads: _Probe(
    (s) => s.devicePrefs.write(
      DevicePrefKeys.commentReads,
      '{"user":"u1","companies":{"co":{"base":1}}}',
    ),
    (s) => s.devicePrefs.read(DevicePrefKeys.commentReads) == null,
  ),
};

final _certificate = CertificateFacts(
  sha256: 'ab' * 32,
  subject: '/CN=pay.example.com',
  issuer: '/CN=pay.example.com',
  notBefore: DateTime.utc(2026, 1, 1, 12),
  notAfter: DateTime.utc(2027, 1, 1, 12),
);

void main() {
  test('every device preference has a probe', () {
    expect(
      {for (final k in DevicePrefKeys.all) k.name},
      {for (final k in _probes.keys) k.name},
      reason:
          'a new DevicePrefKeys entry needs a probe here, so its behaviour '
          'across a sign-out is decided and pinned',
    );
  });

  Future<ShellFixture> changedEverything() async {
    final fixture = await buildFixture(
      companies: const [FakeCompany(id: 'co1', name: 'Acme')],
    );
    for (final MapEntry(:key, value: probe) in _probes.entries) {
      await probe.change(fixture.services);
      expect(
        probe.isDefault(fixture.services),
        isFalse,
        reason: 'the ${key.name} probe must move it off its default',
      );
    }
    // The shortcut write is fire-and-forget; let it land.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return fixture;
  }

  test('a deliberate sign-out keeps the device preferences and forgets the '
      'account ones, in memory and on disk', () async {
    final fixture = await changedEverything();
    addTearDown(fixture.dispose);

    await fixture.services.auth.logout(data: LocalDataPolicy.destroy);

    final rows = await fixture.db.devicePrefsDao.readAll();
    for (final MapEntry(:key, value: probe) in _probes.entries) {
      final kept = key.scope == PrefScope.device;
      expect(
        probe.isDefault(fixture.services),
        !kept,
        reason: kept
            ? '${key.name} belongs to the device — a sign-out keeps it'
            : '${key.name} belongs to the account — the next person to sign '
                  'in must not inherit it',
      );
      expect(rows.containsKey(key.name), kept, reason: '${key.name} on disk');
    }
  });

  test('an end that keeps local data keeps every preference', () async {
    final fixture = await changedEverything();
    addTearDown(fixture.dispose);

    await fixture.services.auth.logout(data: LocalDataPolicy.keep);

    final rows = await fixture.db.devicePrefsDao.readAll();
    for (final MapEntry(:key, value: probe) in _probes.entries) {
      expect(probe.isDefault(fixture.services), isFalse, reason: key.name);
      expect(rows.containsKey(key.name), isTrue, reason: key.name);
    }
  });
}
