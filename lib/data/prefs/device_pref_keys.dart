/// Whether a device preference belongs to the device or to whoever is signed
/// in — which decides whether wiping local data forgets it.
enum PrefScope {
  /// Kept when local data is wiped (a deliberate sign-out, or another identity
  /// signing in): how the app looks and responds on this device.
  device,

  /// Forgotten with the signed-in user's data: it describes their account —
  /// its entities, roster, dashboard or companies — and the next person to
  /// sign in on this device must not inherit it.
  account,
}

/// How a preference's value is written to its `device_prefs` row.
sealed class PrefCodec<T extends Object> {
  const PrefCodec();

  static const PrefCodec<String> string = _StringCodec();
  static const PrefCodec<bool> boolean = _BoolCodec();
  static const PrefCodec<double> decimal = _DoubleCodec();

  String encode(T value);

  /// Null when [raw] isn't a [T] — written by a newer build, say — which reads
  /// exactly like a preference that was never set.
  T? decode(String raw);
}

final class _StringCodec extends PrefCodec<String> {
  const _StringCodec();

  @override
  String encode(String value) => value;

  @override
  String decode(String raw) => raw;
}

/// `'1'` / `'0'` — also what SQLite made of the `nav_state` BOOLEAN columns
/// when v12 copied them into the TEXT `value` column.
final class _BoolCodec extends PrefCodec<bool> {
  const _BoolCodec();

  @override
  String encode(bool value) => value ? '1' : '0';

  @override
  bool? decode(String raw) => switch (raw) {
    '1' || 'true' => true,
    '0' || 'false' => false,
    _ => null,
  };
}

final class _DoubleCodec extends PrefCodec<double> {
  const _DoubleCodec();

  @override
  String encode(double value) => value.toString();

  @override
  double? decode(String raw) => double.tryParse(raw);
}

/// One device preference: the name of its `device_prefs` row, how its value
/// is encoded there, and whether a data wipe forgets it.
final class PrefKey<T extends Object> {
  const PrefKey(this.name, this.codec, this.scope);

  final String name;
  final PrefCodec<T> codec;
  final PrefScope scope;

  @override
  String toString() => 'PrefKey($name)';
}

/// A reserved `device_prefs` row: present once the store's `nav_state`
/// preference columns have been copied into `device_prefs`
/// (`carryNavStatePrefs`). Never a preference, and never wiped.
const String kPrefsCarriedFromNavState = '_carried_from_nav_state';

/// Every device preference. Adding one is adding a key here — no schema
/// change, no migration. A name is a row on installed devices, so it is never
/// renamed or reused (`test/data/prefs/device_pref_keys_test.dart`).
abstract final class DevicePrefKeys {
  // The seventeen that were `nav_state` columns through schema v11. Each row
  // is named after its column, so v12 could copy them across by name.
  static const locale = PrefKey<String>(
    'locale',
    PrefCodec.string,
    PrefScope.device,
  );
  static const themeMode = PrefKey<String>(
    'theme_mode',
    PrefCodec.string,
    PrefScope.device,
  );
  static const lightVariant = PrefKey<String>(
    'light_variant',
    PrefCodec.string,
    PrefScope.device,
  );
  static const darkVariant = PrefKey<String>(
    'dark_variant',
    PrefCodec.string,
    PrefScope.device,
  );
  static const customTheme = PrefKey<String>(
    'custom_theme_json',
    PrefCodec.string,
    PrefScope.device,
  );
  static const textScale = PrefKey<double>(
    'text_scale',
    PrefCodec.decimal,
    PrefScope.device,
  );
  static const keyboardShortcuts = PrefKey<String>(
    'keyboard_shortcuts_json',
    PrefCodec.string,
    PrefScope.device,
  );
  static const sidebarBadgeModes = PrefKey<String>(
    'sidebar_badge_modes_json',
    PrefCodec.string,
    PrefScope.account,
  );
  static const confirmActions = PrefKey<bool>(
    'confirm_actions',
    PrefCodec.boolean,
    PrefScope.account,
  );
  static const statusTabs = PrefKey<bool>(
    'status_tabs',
    PrefCodec.boolean,
    PrefScope.device,
  );
  static const contactsSync = PrefKey<String>(
    'contacts_sync_json',
    PrefCodec.string,
    PrefScope.account,
  );
  static const phoneActions = PrefKey<String>(
    'phone_actions_json',
    PrefCodec.string,
    PrefScope.device,
  );
  static const sidebarMenu = PrefKey<String>(
    'sidebar_menu_json',
    PrefCodec.string,
    PrefScope.account,
  );
  static const tasksView = PrefKey<String>(
    'tasks_view',
    PrefCodec.string,
    PrefScope.account,
  );

  /// How the kanban board is drawn — card fields, lane grouping, collapsed
  /// columns — as `KanbanPrefs` JSON (docs/tasks-views.md). The collapsed set
  /// names this account's statuses, so a sign-out forgets it, like
  /// [tasksView].
  static const kanban = PrefKey<String>(
    'kanban_json',
    PrefCodec.string,
    PrefScope.account,
  );
  static const hideUnverifiedUsers = PrefKey<bool>(
    'hide_unverified_users',
    PrefCodec.boolean,
    PrefScope.account,
  );
  static const hideEmptyPanels = PrefKey<bool>(
    'hide_empty_panels',
    PrefCodec.boolean,
    PrefScope.account,
  );
  static const sidebarCollapsed = PrefKey<bool>(
    'sidebar_collapsed',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// Which items tab (`products` / `tasks`) a billing document opens on when
  /// its lines don't decide (React #3355's `default_tab`). The user's habit,
  /// so it follows the account.
  static const defaultItemsTab = PrefKey<String>(
    'default_items_tab',
    PrefCodec.string,
    PrefScope.account,
  );

  /// List row density (`normal` / `compact`) — how tightly entity lists pack
  /// their rows. How the app looks on this screen, like [textScale], so it
  /// stays with the device.
  static const listDensity = PrefKey<String>(
    'list_density',
    PrefCodec.string,
    PrefScope.device,
  );

  /// How the Tasks weekly view and the reports show hours (`decimal` /
  /// `hh_mm`, React's `preferences.duration_format`, ui#3422). The user's
  /// habit, so it follows the account, as React's per-user setting does.
  static const hoursFormat = PrefKey<String>(
    'hours_format',
    PrefCodec.string,
    PrefScope.account,
  );

  /// Hide the PEPPOL sent / failed icon on the invoice and credit lists
  /// (React's `preferences.hide_peppol_sent_status`, ui#3410). Per user in
  /// React, so it follows the account here.
  static const hidePeppolStatus = PrefKey<bool>(
    'hide_peppol_status',
    PrefCodec.boolean,
    PrefScope.account,
  );

  /// Server certificates the user chose to trust although this device
  /// refused them — each pinned by its SHA-256 to one self-hosted host:port
  /// (`CertificateTrustStore`). It describes the servers this device talks
  /// to, not an account, and it is made at the login screen before any
  /// account exists: an identity-change wipe runs inside that same sign-in,
  /// so an account scope would forget the pin halfway through it.
  static const trustedCertificates = PrefKey<String>(
    'trusted_certificates_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// Why the last session ended on its own — `{reason, detail?}` JSON, shown
  /// once on the sign-in screen (`SignOutNotice`). Written just before the
  /// logout it explains, which may wipe local data, so it belongs to the
  /// device: an account scope would forget it in the same breath.
  static const signOutNotice = PrefKey<String>(
    'sign_out_notice_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// The "get the mobile app" promo's schedule — `{closes, nextAt, done,
  /// engaged, daysSeen, lastDay}` JSON (`MobileAppPromoController`). It is
  /// "this machine has been told", not a fact about an account, so a
  /// sign-out keeps it and the next user of the same desktop isn't re-pitched.
  static const mobileAppPromo = PrefKey<String>(
    'mobile_app_promo_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// The "What's new" dialog's record — `{seenVersion, shownAt, attempts,
  /// attemptedVersion}` JSON (`WhatsNewController`). It is "this install has
  /// shown these notes", so a sign-out keeps it: the next person signing in
  /// here is not told about the same update again (docs/whats-new-dialog.md).
  static const whatsNew = PrefKey<String>(
    'whats_new_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// Underline spelling (and, on macOS, grammar) mistakes in a line item's
  /// name and description (docs/spell-check.md). Whether this device's
  /// checker is worth the noise of flagged SKUs is a judgement about the
  /// machine and its language, like [listDensity], so it stays with the
  /// device.
  static const spellCheck = PrefKey<bool>(
    'spell_check',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// Show seconds on the Tasks surfaces that leave them out by default — the
  /// kanban cards, a timer past a day, a time entry's start and end
  /// (docs/tasks-views.md). How the app reads on this device, like
  /// [listDensity], so it stays with the device.
  static const showSeconds = PrefKey<bool>(
    'show_seconds',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// Draw a document's photo or first PDF page as a thumbnail in document
  /// lists (invoiceninja/app#206, docs/document-thumbnails.md). Each one is a
  /// download, so it follows this device's connection, not the user.
  static const documentThumbnails = PrefKey<bool>(
    'document_thumbnails',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// The folder a desktop download is written to; empty is the OS Downloads
  /// folder (docs/file-downloads.md). A path on this machine, so it stays
  /// with the device.
  static const downloadsFolder = PrefKey<String>(
    'downloads_folder',
    PrefCodec.string,
    PrefScope.device,
  );

  /// The review prompt's schedule — install age, days of use, wins, asks
  /// (`ReviewPromptController`, docs/review-prompt.md). Like
  /// [mobileAppPromo] it is "this device has been asked": a sign-out keeps
  /// it, so the install age survives and the next person here isn't asked
  /// the day after someone else declined.
  static const reviewPrompt = PrefKey<String>(
    'review_prompt_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// The first-run experience's record (`WelcomeController`,
  /// docs/first-run-welcome.md): which users this device has greeted, keyed
  /// by server and user, and each company's setup checklist. Device scope so
  /// a sign-out does not greet the same person again; per user because the
  /// JSON is keyed by user.
  static const welcome = PrefKey<String>(
    'welcome_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// A Bluetooth card reader has been connected in this app, so invoices
  /// offer "Collect card payment" on a phone without Tap to Pay
  /// (`TerminalController`, docs/in-person-payments.md). Account scope: it
  /// follows the Stripe account that reader was used with.
  static const cardReaderUsed = PrefKey<bool>(
    'card_reader_used',
    PrefCodec.boolean,
    PrefScope.account,
  );

  /// Apple's "How to Tap" explainer has been shown before this account's
  /// first Tap to Pay on iPhone collection (App Review requires it;
  /// `showHowToTap`, docs/in-person-payments.md). Account scope: each merchant
  /// signing in on this phone sees it once.
  static const howToTapShown = PrefKey<bool>(
    'how_to_tap_shown',
    PrefCodec.boolean,
    PrefScope.account,
  );

  /// Card payments that may have been charged and that the server hadn't
  /// answered for when the app last knew: `{paymentIntentId: {company,
  /// invoice}}` (`TerminalController`). Checked when the invoice opens, and
  /// before another payment is entered on it. Account scope: the next person
  /// to sign in can't check another account's payments.
  static const pendingCardPayments = PrefKey<String>(
    'pending_card_payments_json',
    PrefCodec.string,
    PrefScope.account,
  );

  /// Tap to Pay on iPhone has been turned on, or announced, for this account:
  /// the enable screen reached Ready (and, later, the awareness modal was
  /// seen). Account scope, like [howToTapShown].
  static const tapToPayAnnounced = PrefKey<bool>(
    'tap_to_pay_announced',
    PrefCodec.boolean,
    PrefScope.account,
  );

  /// The web build's "other apps" banner was dismissed in this browser
  /// (`WebAppBannerController`). "This browser has been told", like
  /// [mobileAppPromo], so a sign-out keeps it — the web's idle timeout signs
  /// people out on its own, and the banner must not come back each time.
  static const webAppBannerDismissed = PrefKey<bool>(
    'web_app_banner_dismissed',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// What Save on an edit screen does next: stay in the editor (`true`) or go
  /// to the record (`false`) — Device Settings → Forms → After Saving
  /// (`AfterSavingController`, docs/after-saving.md, invoiceninja/app#202).
  /// No row means automatic: the editor on a tablet or a desktop, the record
  /// on a phone. Device scope: it is how this device's editors behave, like
  /// the theme, not something the account chose.
  static const afterSaving = PrefKey<bool>(
    'after_saving',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// When the appearance this device shows ([themeMode], the palettes,
  /// [customTheme]) was last changed here or adopted from the account, in
  /// epoch ms — the stamp `flutter_appearance` is ordered by
  /// (`lib/domain/appearance_sync.dart`, invoiceninja/app#199). Owned by
  /// `ThemeController`. Account scope: the look itself stays with the device,
  /// but whose choice it was goes with a sign-out, so the next person to sign
  /// in adopts their own.
  static const appearanceSyncedAt = PrefKey<String>(
    'appearance_synced_at',
    PrefCodec.string,
    PrefScope.account,
  );

  /// This device has met an account's synced appearance once, so a look
  /// nobody stamped is never uploaded again (`AppearanceSyncController`).
  /// Device scope: the upload-once migration is for this install, and must
  /// not hand the last user's look to the next one on a shared device.
  static const appearanceSeeded = PrefKey<bool>(
    'appearance_seeded',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// The "get the desktop app" promo's schedule on a phone — the same JSON
  /// as [mobileAppPromo], kept by the same `MobileAppPromoController`
  /// (docs/desktop-app-promo.md). A key of its own, so "this phone has been
  /// told about the desktop app" never reads as an answer to the other promo.
  static const desktopAppPromo = PrefKey<String>(
    'desktop_app_promo_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// Column widths the user dragged on the wide entity lists, as JSON
  /// `{"<entityType>": {"<columnId>": <width>}}` (`ListColumnWidthsController`,
  /// docs/entity-lists.md). Device scope: the right width depends on this
  /// screen, like [listDensity] — a laptop and a wide monitor want different
  /// ones, so they do not follow the account.
  static const listColumnWidths = PrefKey<String>(
    'list_column_widths_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// A signed-out user's account preferences ([keptForReturningUser]), kept
  /// aside per identity so the same user signing back in gets them back
  /// (`DevicePrefsStore.keepForReturningUser`, invoiceninja/app#209). JSON
  /// `{"<identity hash>": {"<key name>": "<stored value>"}}`, at most five
  /// identities. Device scope, or the sign-out that fills it would empty it.
  static const accountPrefsKept = PrefKey<String>(
    'account_prefs_kept_json',
    PrefCodec.string,
    PrefScope.device,
  );

  /// Which teammates' comments this user has seen, per company and per
  /// record (`CommentsInboxController`, docs/comments-and-activity.md § A
  /// teammate's comment is new until you have seen it): JSON naming its
  /// `user`, and per company id a `base` (when tracking started), a `feed`
  /// (the inbox last opened) and `records` (`wire:id` → the newest comment its
  /// card showed), all in epoch seconds — `CommentReads.encode`. Account
  /// scope: what one person has read says nothing about the next; and the
  /// blob names its user, so a copy that outlives a kept-data session end is
  /// never read by someone else.
  static const commentReads = PrefKey<String>(
    'comment_reads_json',
    PrefCodec.string,
    PrefScope.account,
  );

  /// Minutes of inactivity after which the app locks behind the device's own
  /// authentication without signing out; `0` (or no row) is Never
  /// (`LockAfterInactivityController`, docs/soft-lock.md). Device scope: the
  /// lock proves the person holding *this device* is its owner — Face ID, a
  /// fingerprint, the device passcode — not who is signed in, and a sign-out
  /// that forgot it would quietly drop a security choice the next sign-in on
  /// the same device never made.
  static const lockAfterInactivity = PrefKey<double>(
    'lock_after_inactivity_minutes',
    PrefCodec.decimal,
    PrefScope.device,
  );

  /// Keep every scroll bar's thumb on screen instead of fading it once the
  /// scrolling stops — Device Settings → Appearance, pointer platforms only
  /// (`AlwaysShowScrollbarsController`, docs/scrollbars.md). How this
  /// device's screen reads, like [listDensity], so it stays with the device.
  static const alwaysShowScrollbars = PrefKey<bool>(
    'always_show_scrollbars',
    PrefCodec.boolean,
    PrefScope.device,
  );

  /// In the order they were added; append new keys at the end.
  static const List<PrefKey<Object>> all = [
    locale,
    themeMode,
    lightVariant,
    darkVariant,
    customTheme,
    textScale,
    keyboardShortcuts,
    sidebarBadgeModes,
    confirmActions,
    statusTabs,
    contactsSync,
    phoneActions,
    sidebarMenu,
    tasksView,
    kanban,
    hideUnverifiedUsers,
    hideEmptyPanels,
    sidebarCollapsed,
    defaultItemsTab,
    listDensity,
    hoursFormat,
    hidePeppolStatus,
    trustedCertificates,
    signOutNotice,
    mobileAppPromo,
    whatsNew,
    spellCheck,
    showSeconds,
    downloadsFolder,
    reviewPrompt,
    welcome,
    cardReaderUsed,
    pendingCardPayments,
    howToTapShown,
    tapToPayAnnounced,
    webAppBannerDismissed,
    afterSaving,
    appearanceSyncedAt,
    appearanceSeeded,
    desktopAppPromo,
    documentThumbnails,
    listColumnWidths,
    accountPrefsKept,
    commentReads,
    lockAfterInactivity,
    alwaysShowScrollbars,
  ];

  /// The account preferences a sign-out keeps aside for the SAME user's
  /// return ([accountPrefsKept]) — choices about how this user works: the
  /// sidebar counters, menu, Tasks layout, dashboard, confirmations. Left out
  /// on purpose: contacts sync (the sign-out removed its contacts from the
  /// address book, and turning it back on silently would re-add them), the
  /// card-payment state, and the appearance sync stamp.
  static final Set<String> keptForReturningUser = {
    sidebarBadgeModes.name,
    confirmActions.name,
    sidebarMenu.name,
    tasksView.name,
    kanban.name,
    hideUnverifiedUsers.name,
    hideEmptyPanels.name,
    defaultItemsTab.name,
    hoursFormat.name,
    hidePeppolStatus.name,
    howToTapShown.name,
    tapToPayAnnounced.name,
    commentReads.name,
  };

  /// The rows a data wipe leaves in place: the [PrefScope.device] keys and the
  /// carry marker. Anything else — an account key, or a key this build does
  /// not know (written by a newer one) — is forgotten, the safe answer when
  /// the next person to sign in may be someone else.
  static final Set<String> keptOnWipe = {
    for (final key in all)
      if (key.scope == PrefScope.device) key.name,
    kPrefsCarriedFromNavState,
  };
}
