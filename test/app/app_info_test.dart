import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/app_info.dart';
import 'package:admin/app/version.dart';

/// The App info rows (Debug Panel → App info) are a pure function of
/// [AppInfoInputs]; [tr] is the identity here, so a label reads as its key.
void main() {
  String tr(String key) => key;

  AppInfoInputs inputs({
    bool isWeb = false,
    TargetPlatform platform = TargetPlatform.macOS,
    String hostSystem = 'Version 26.4 (Build 25E246)',
    bool isWasm = false,
    bool usesSkwasm = false,
    bool? impeller = true,
    String? buildNumber = '34',
    String gitCommit = '',
    String? serverUrl = 'https://invoicing.co',
    bool isHosted = true,
    List<String> foldFeatures = const [],
    TextDirection textDirection = TextDirection.ltr,
    Brightness brightness = Brightness.light,
  }) => AppInfoInputs(
    clientVersion: '5.1.31',
    buildNumber: buildNumber,
    gitCommit: gitCommit,
    buildMode: 'release',
    isBeta: true,
    isStoreBuild: true,
    storeBilling: false,
    demoMode: false,
    demoBuild: true,
    hasSentryDsn: true,
    sentryRunning: false,
    isWeb: isWeb,
    platform: platform,
    hostSystem: hostSystem,
    isWasm: isWasm,
    usesSkwasm: usesSkwasm,
    impeller: impeller,
    serverUrl: serverUrl,
    isHosted: isHosted,
    serverVersion: '5.13.53',
    plan: 'enterprise',
    reportErrors: true,
    screenSize: const Size(1280.4, 799.6),
    pixelRatio: 2,
    textScale: 1.25,
    locale: const Locale('en', 'US'),
    textDirection: textDirection,
    brightness: brightness,
    foldFeatures: foldFeatures,
    bookPosture: foldFeatures.isNotEmpty,
  );

  Map<String, String> rowMap(List<AppInfoRow> rows) => {
    for (final r in rows) r.label: r.value,
  };

  test('native rows, in order', () {
    final rows = appInfoRows(inputs(), tr);
    expect(rows.map((r) => r.toString()).toList(), [
      'app_version: 5.1.31',
      'app_info_build_number: 34',
      'app_info_build_mode: release',
      'beta: yes',
      'app_info_store_build: yes',
      'app_info_store_billing: no',
      'demo_mode: no',
      'app_info_demo_build: yes',
      'app_info_sentry: no',
      'app_info_sentry_dsn: yes',
      'app_info_platform: macOS',
      'app_info_os_version: Version 26.4 (Build 25E246)',
      'app_info_impeller: yes',
      'server: https://invoicing.co',
      'app_info_hosting: hosted',
      'app_info_server_version: 5.13.53',
      'plan: enterprise',
      'app_info_report_errors: yes',
      'app_info_screen_size: 1280 × 800',
      'app_info_pixel_ratio: 2.00',
      'app_info_text_scale: 1.25',
      'app_info_locale: en-US',
      'app_info_text_direction: LTR',
      'theme: light',
      'app_info_display_features: none',
    ]);
  });

  test('web: user agent, compile target and renderer; no OS / Impeller', () {
    const ua = 'Mozilla/5.0 (Macintosh) Gecko/20100101 Firefox/147.0';
    final wasm = rowMap(
      appInfoRows(
        inputs(
          isWeb: true,
          hostSystem: ua,
          isWasm: true,
          usesSkwasm: true,
          impeller: null,
        ),
        tr,
      ),
    );
    expect(wasm['app_info_platform'], 'Web');
    expect(wasm['app_info_user_agent'], ua);
    expect(wasm['app_info_compiled_to'], 'WebAssembly');
    expect(wasm['app_info_renderer'], 'skwasm');
    expect(wasm.containsKey('app_info_os_version'), isFalse);
    expect(wasm.containsKey('app_info_impeller'), isFalse);

    final js = rowMap(
      appInfoRows(inputs(isWeb: true, hostSystem: ua, impeller: null), tr),
    );
    expect(js['app_info_compiled_to'], 'JavaScript');
    expect(js['app_info_renderer'], 'CanvasKit');
  });

  test('every platform has its own name', () {
    expect(
      [
        for (final p in [
          TargetPlatform.iOS,
          TargetPlatform.android,
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        ])
          appInfoPlatformName(isWeb: false, platform: p),
        appInfoPlatformName(isWeb: true, platform: TargetPlatform.android),
      ],
      ['iOS', 'Android', 'macOS', 'Windows', 'Linux', 'Web'],
    );
  });

  test('optional rows drop out; blanks read as a dash', () {
    final m = rowMap(
      appInfoRows(
        inputs(buildNumber: null, hostSystem: '', impeller: null),
        tr,
      ),
    );
    expect(m.containsKey('app_info_build_number'), isFalse);
    expect(m.containsKey('app_info_commit'), isFalse);
    expect(m.containsKey('app_info_impeller'), isFalse);
    expect(m['app_info_os_version'], '—');

    final withCommit = rowMap(appInfoRows(inputs(gitCommit: 'a1b2c3d'), tr));
    expect(withCommit['app_info_commit'], 'a1b2c3d');
  });

  test('signed out: no server rows', () {
    final m = rowMap(appInfoRows(inputs(serverUrl: null), tr));
    for (final key in [
      'server',
      'app_info_hosting',
      'app_info_server_version',
      'plan',
      'app_info_report_errors',
    ]) {
      expect(m.containsKey(key), isFalse, reason: key);
    }
    final selfHosted = rowMap(appInfoRows(inputs(isHosted: false), tr));
    expect(selfHosted['app_info_hosting'], 'selfhosted');
  });

  test('display: RTL, dark, and the fold with its posture', () {
    final m = rowMap(
      appInfoRows(
        inputs(
          textDirection: TextDirection.rtl,
          brightness: Brightness.dark,
          foldFeatures: ['fold postureHalfOpened 0×2208', 'cutout unknown'],
        ),
        tr,
      ),
    );
    expect(m['app_info_text_direction'], 'RTL');
    expect(m['theme'], 'dark');
    expect(
      m['app_info_display_features'],
      'fold postureHalfOpened 0×2208, cutout unknown',
    );
    expect(m['app_info_book_posture'], 'yes');
  });

  test('Copy all is one label: value line per row', () {
    final rows = [
      const AppInfoRow('App Version', '5.1.31'),
      const AppInfoRow('Platform', 'Web'),
    ];
    expect(appInfoText(rows), 'App Version: 5.1.31\nPlatform: Web');
  });

  test('running() reads the binary: version, mode, platform', () {
    final i = AppInfoInputs.running(
      screenSize: const Size(800, 600),
      pixelRatio: 1,
      textScale: 1,
      locale: const Locale('en'),
      textDirection: TextDirection.ltr,
      brightness: Brightness.light,
    );
    expect(i.clientVersion, AppVersion.kClientVersion);
    expect(i.isBeta, kAppIsBeta);
    expect(i.isWeb, isFalse);
    expect(i.platform, defaultTargetPlatform);
    // `flutter test` is a debug VM build: Sentry never starts there.
    expect(i.buildMode, 'debug');
    expect(i.sentryRunning, isFalse);
    expect(i.impeller, isNotNull);
    expect(i.hostSystem, isNotEmpty);
  });
}
