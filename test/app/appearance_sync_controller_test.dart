import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/appearance_sync_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/data/repositories/user_settings_repository.dart';
import 'package:admin/domain/appearance_sync.dart';

/// `AppearanceSyncController` against a real in-memory database: the theme
/// follows the user across devices and companies (invoiceninja/app#199).
void main() {
  late AppDatabase db;
  late DevicePrefsStore prefs;
  late ThemeController theme;
  late UserSettingsRepository userSettings;
  late ValueNotifier<AuthSession?> session;
  late AppearanceSyncController sync;
  var clock = 1000;

  AuthSession sessionFor(String companyId, {String userId = 'u1'}) =>
      AuthSession(
        baseUrl: 'https://example.test',
        isHosted: true,
        accountId: 'acc',
        companies: const [],
        currentCompanyId: companyId,
        userId: userId,
      );

  Future<void> storeSettings(
    String companyId,
    Map<String, dynamic> settings, {
    String userId = 'u1',
  }) => db.userSettingsDao.upsert(
    UserSettingsCompanion(
      companyId: Value(companyId),
      userId: Value(userId),
      updatedAt: const Value(0),
      extraJson: Value(jsonEncode(settings)),
      tableColumnsJson: const Value('{}'),
    ),
  );

  Map<String, dynamic> withAppearance(AppearanceRecord r) => {
    kAppearanceSettingsKey: {
      'theme_mode': r.themeMode,
      'light_variant': r.lightVariant,
      'dark_variant': r.darkVariant,
      'custom': r.custom,
      'updated_at': r.updatedAt,
    },
  };

  Future<AppearanceRecord?> serverCopy(String companyId) async =>
      AppearanceRecord.fromSettings(await userSettings.getSettings(companyId));

  Future<List<OutboxRow>> queued(String companyId) => db.outboxDao
      .activeRowsFor(companyId: companyId, entityType: kUserSettingsWireName);

  /// Lets the watch streams deliver and the passes they trigger finish.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await sync.idle;
    }
  }

  void start({AuthSession? initial}) {
    session = ValueNotifier(initial);
    sync = AppearanceSyncController(
      session: session,
      userSettings: userSettings,
      theme: theme,
      prefs: prefs,
      now: () => DateTime.fromMillisecondsSinceEpoch(clock),
    );
  }

  setUp(() async {
    clock = 1000;
    db = AppDatabase(NativeDatabase.memory());
    prefs = DevicePrefsStore(db);
    await prefs.load();
    theme = ThemeController(
      prefs: prefs,
      now: () => DateTime.fromMillisecondsSinceEpoch(clock),
    );
    userSettings = UserSettingsRepository(
      db: db,
      now: () => DateTime.fromMillisecondsSinceEpoch(clock),
    );
  });

  tearDown(() async {
    sync.dispose();
    theme.dispose();
    await db.close();
  });

  const otherComputer = AppearanceRecord(
    themeMode: 'dark',
    lightVariant: 'mist',
    darkVariant: 'midnight',
    custom: {
      'light': <String, Object?>{},
      'dark': {'surface': '#112233'},
    },
    updatedAt: 500,
  );

  test('signing in on a new computer adopts the colours changed on the '
      'other one — in whichever company they were changed', () async {
    // The other computer changed them under company b; this one opens on a.
    await storeSettings('a', {});
    await storeSettings('b', withAppearance(otherComputer));
    start(initial: sessionFor('a'));
    await settle();

    expect(theme.themeMode, ThemeMode.dark);
    expect(theme.lightVariant, LightVariant.mist);
    expect(theme.darkVariant, DarkVariant.midnight);
    expect(
      theme.customTheme.darkOverrides[CustomToken.surface],
      const Color(0xFF112233),
    );
    expect(theme.syncedAt, 500);
    // Company a converges: it is sent the adopted copy.
    expect((await serverCopy('a'))?.updatedAt, 500);
    expect((await serverCopy('a'))?.sameLook(otherComputer), isTrue);
    expect(await queued('a'), hasLength(1));
    expect(await queued('b'), isEmpty, reason: 'only the active company');
  });

  test('a change here is written to the active company only, stamped, and '
      'collapses into one queued row', () async {
    await storeSettings('a', {});
    await storeSettings('b', {});
    start(initial: sessionFor('a'));
    await settle();

    clock = 2000;
    await theme.setThemeMode(ThemeMode.dark);
    await settle();
    clock = 3000;
    await theme.setDarkVariant(DarkVariant.carbon);
    await settle();

    final copy = await serverCopy('a');
    expect(copy?.themeMode, 'dark');
    expect(copy?.darkVariant, 'carbon');
    expect(copy?.updatedAt, 3000);
    expect(await serverCopy('b'), isNull);
    expect(await queued('a'), hasLength(1), reason: 'rapid changes collapse');
    expect(await queued('b'), isEmpty);
  });

  test('switching company sends the newly active one the newer copy it '
      'lacks', () async {
    await storeSettings('a', {});
    await storeSettings('b', {});
    start(initial: sessionFor('a'));
    await settle();
    clock = 2000;
    await theme.setThemeMode(ThemeMode.light);
    await settle();
    expect(await serverCopy('b'), isNull);

    session.value = sessionFor('b');
    await settle();

    expect((await serverCopy('b'))?.updatedAt, 2000);
    expect((await serverCopy('b'))?.themeMode, 'light');
  });

  test('a stale copy another client wrote back is put right, and the look '
      'here does not revert', () async {
    await storeSettings('a', {});
    start(initial: sessionFor('a'));
    await settle();
    clock = 4000;
    await theme.setThemeMode(ThemeMode.dark);
    await settle();

    // React's profile save puts back the copy it loaded at page open.
    await applyServerSettings(
      db,
      companyId: 'a',
      userId: 'u1',
      settings: withAppearance(
        const AppearanceRecord(
          themeMode: 'light',
          lightVariant: 'sand',
          darkVariant: 'espresso',
          updatedAt: 100,
        ),
      ),
      nowMs: 4100,
    );
    await settle();

    expect(theme.themeMode, ThemeMode.dark);
    expect((await serverCopy('a'))?.updatedAt, 4000);
    expect((await serverCopy('a'))?.themeMode, 'dark');
  });

  test('a newer copy arriving with a /refresh is adopted live', () async {
    await storeSettings('a', {});
    start(initial: sessionFor('a'));
    await settle();
    clock = 2000;
    await theme.setThemeMode(ThemeMode.light);
    await settle();

    // The light change has reached the server (a queued one would be laid
    // over the capture instead).
    for (final row in await queued('a')) {
      await db.outboxDao.deleteRow(row.id);
    }
    await applyServerSettings(
      db,
      companyId: 'a',
      userId: 'u1',
      settings: withAppearance(otherComputer.withUpdatedAt(9000)),
      nowMs: 9200,
    );
    await settle();

    expect(theme.themeMode, ThemeMode.dark);
    expect(theme.syncedAt, 9000);
  });

  test('an upgraded device uploads its own look once when the account has '
      'none, and is marked seeded', () async {
    await prefs.write(DevicePrefKeys.themeMode, 'dark');
    await prefs.write(DevicePrefKeys.lightVariant, 'paper');
    await prefs.load();
    expect(theme.syncedAt, isNull);
    await storeSettings('a', {});
    clock = 7000;
    start(initial: sessionFor('a'));
    await settle();

    final copy = await serverCopy('a');
    expect(copy?.themeMode, 'dark');
    expect(copy?.lightVariant, 'paper');
    expect(copy?.updatedAt, 7000);
    expect(theme.syncedAt, 7000);
    expect(prefs.read(DevicePrefKeys.appearanceSeeded), isTrue);
  });

  test('a seeded device does not upload an unstamped look — the next user '
      'of a shared computer keeps their account clean', () async {
    await prefs.write(DevicePrefKeys.themeMode, 'dark');
    await prefs.write(DevicePrefKeys.appearanceSeeded, true);
    await prefs.load();
    await storeSettings('a', {}, userId: 'u2');
    start(initial: sessionFor('a', userId: 'u2'));
    await settle();

    expect(await serverCopy('a'), isNull);
    expect(await queued('a'), isEmpty);
    expect(theme.themeMode, ThemeMode.dark, reason: 'the look stays');
  });

  test('nothing is read or written while signed out', () async {
    await storeSettings('a', withAppearance(otherComputer));
    start();
    await settle();
    await theme.setThemeMode(ThemeMode.light);
    await settle();

    expect(theme.themeMode, ThemeMode.light);
    expect((await serverCopy('a'))?.themeMode, 'dark');
  });

  test('another identity\'s stored settings are ignored', () async {
    await storeSettings('a', {});
    await storeSettings('b', withAppearance(otherComputer), userId: 'other');
    start(initial: sessionFor('a'));
    await settle();

    expect(theme.themeMode, ThemeMode.system);
  });
}
