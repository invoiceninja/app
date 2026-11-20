/// How the app is running, as the Debug Panel's App info tab shows it: build,
/// platform, server and display, one label / value row each.
///
/// [appInfoRows] is pure — every input arrives through [AppInfoInputs], so a
/// test can describe any build on any platform. [AppInfoInputs.running] fills
/// the build and platform half from the running binary; the widget supplies
/// what only a `BuildContext` or the session knows.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/env.dart';
import 'package:admin/app/host_system.dart';
import 'package:admin/app/version.dart';
import 'package:admin/domain/upgrade/store_build.dart';

/// One row: a localized [label] and its [value], already rendered.
@immutable
class AppInfoRow {
  const AppInfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AppInfoRow && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

/// Everything [appInfoRows] reads.
@immutable
class AppInfoInputs {
  const AppInfoInputs({
    required this.clientVersion,
    this.buildNumber,
    this.gitCommit = '',
    required this.buildMode,
    required this.isBeta,
    required this.isStoreBuild,
    required this.storeBilling,
    required this.demoMode,
    required this.demoBuild,
    required this.hasSentryDsn,
    required this.sentryRunning,
    required this.isWeb,
    required this.platform,
    this.hostSystem = '',
    this.isWasm = false,
    this.usesSkwasm = false,
    this.impeller,
    this.serverUrl,
    this.isHosted = false,
    this.serverVersion = '',
    this.plan = '',
    this.reportErrors = false,
    required this.screenSize,
    required this.pixelRatio,
    required this.textScale,
    required this.locale,
    required this.textDirection,
    required this.brightness,
    this.foldFeatures = const [],
    this.bookPosture = false,
  });

  /// The build and platform half from the running binary, the rest from the
  /// caller. [buildNumber] is `PackageInfo.buildNumber` once it has loaded.
  factory AppInfoInputs.running({
    String? buildNumber,
    String? serverUrl,
    bool isHosted = false,
    String serverVersion = '',
    String plan = '',
    bool reportErrors = false,
    required ui.Size screenSize,
    required double pixelRatio,
    required double textScale,
    required ui.Locale locale,
    required ui.TextDirection textDirection,
    required ui.Brightness brightness,
    List<String> foldFeatures = const [],
    bool bookPosture = false,
  }) => AppInfoInputs(
    clientVersion: AppVersion.kClientVersion,
    buildNumber: buildNumber,
    gitCommit: Env.gitCommit,
    buildMode: kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    isBeta: kAppIsBeta,
    isStoreBuild: StoreReview.isStoreBuild,
    storeBilling: isStoreBillingBuild,
    demoMode: Env.demoMode,
    demoBuild: Env.isDemoBuild,
    hasSentryDsn: Env.sentryDsn.isNotEmpty,
    // `main.dart`'s gate (release / profile, never the web, a DSN baked in),
    // plus the store package: the F-Droid twin's `runWithCrashReporting` only
    // runs the app.
    sentryRunning:
        !kIsWeb &&
        !kDebugMode &&
        Env.sentryDsn.isNotEmpty &&
        StoreReview.isStoreBuild,
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    hostSystem: hostSystemDescription(),
    isWasm: kIsWasm,
    // flutter_tools compiles every web build with exactly one of
    // FLUTTER_WEB_USE_SKWASM=true / FLUTTER_WEB_USE_SKIA=true
    // (`WebRendererMode.updateDartDefines`), and the engine picks its
    // renderer from the same define (`configuration.dart`), so this is the
    // renderer the page loaded — not a guess from [kIsWasm]. The bootstrap's
    // `?renderer=canvaskit` escape hatch shows up here as the JavaScript
    // build it selects.
    usesSkwasm: const bool.fromEnvironment('FLUTTER_WEB_USE_SKWASM'),
    // The engine's own Impeller flag: `isShaderFilterSupported` returns it
    // verbatim on native (`dart:ui` painting.dart). Meaningless on the web.
    impeller: kIsWeb ? null : ui.ImageFilter.isShaderFilterSupported,
    serverUrl: serverUrl,
    isHosted: isHosted,
    serverVersion: serverVersion,
    plan: plan,
    reportErrors: reportErrors,
    screenSize: screenSize,
    pixelRatio: pixelRatio,
    textScale: textScale,
    locale: locale,
    textDirection: textDirection,
    brightness: brightness,
    foldFeatures: foldFeatures,
    bookPosture: bookPosture,
  );

  final String clientVersion;

  /// Null until `PackageInfo` answers; the row is left out until then.
  final String? buildNumber;

  /// `Env.gitCommit`; empty leaves the row out.
  final String gitCommit;

  /// `release`, `profile` or `debug`.
  final String buildMode;
  final bool isBeta;
  final bool isStoreBuild;
  final bool storeBilling;
  final bool demoMode;
  final bool demoBuild;
  final bool hasSentryDsn;
  final bool sentryRunning;

  final bool isWeb;
  final TargetPlatform platform;

  /// The user agent on the web, the OS version on native (`host_system`).
  final String hostSystem;
  final bool isWasm;
  final bool usesSkwasm;

  /// Null on the web.
  final bool? impeller;

  /// The session's base URL; null when signed out, which leaves out every
  /// server row.
  final String? serverUrl;
  final bool isHosted;
  final String serverVersion;
  final String plan;

  /// The account's `report_errors` opt-in, which decides whether Sentry sends.
  final bool reportErrors;

  final ui.Size screenSize;
  final double pixelRatio;
  final double textScale;
  final ui.Locale locale;
  final ui.TextDirection textDirection;
  final ui.Brightness brightness;

  /// `describeDisplayFeatures` — one entry per fold, hinge or cutout.
  final List<String> foldFeatures;
  final bool bookPosture;
}

/// The platform's own name, which no locale translates.
String appInfoPlatformName({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'Web';
  return switch (platform) {
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

/// The App info rows, in display order. [tr] localizes a key (labels, and the
/// yes / no / none / hosted / light words among the values); every other value
/// is a technical identifier and stays as it is.
List<AppInfoRow> appInfoRows(AppInfoInputs i, String Function(String) tr) {
  String yesNo(bool v) => tr(v ? 'yes' : 'no');
  String orDash(String v) => v.trim().isEmpty ? '—' : v.trim();
  String fixed(double v) => v.toStringAsFixed(2);

  return [
    // Build.
    AppInfoRow(tr('app_version'), i.clientVersion),
    if (i.buildNumber != null && i.buildNumber!.isNotEmpty)
      AppInfoRow(tr('app_info_build_number'), i.buildNumber!),
    if (i.gitCommit.isNotEmpty) AppInfoRow(tr('app_info_commit'), i.gitCommit),
    AppInfoRow(tr('app_info_build_mode'), i.buildMode),
    AppInfoRow(tr('beta'), yesNo(i.isBeta)),
    AppInfoRow(tr('app_info_store_build'), yesNo(i.isStoreBuild)),
    AppInfoRow(tr('app_info_store_billing'), yesNo(i.storeBilling)),
    AppInfoRow(tr('demo_mode'), yesNo(i.demoMode)),
    AppInfoRow(tr('app_info_demo_build'), yesNo(i.demoBuild)),
    AppInfoRow(tr('app_info_sentry'), yesNo(i.sentryRunning)),
    AppInfoRow(tr('app_info_sentry_dsn'), yesNo(i.hasSentryDsn)),

    // Platform.
    AppInfoRow(
      tr('app_info_platform'),
      appInfoPlatformName(isWeb: i.isWeb, platform: i.platform),
    ),
    if (i.isWeb) ...[
      AppInfoRow(tr('app_info_user_agent'), orDash(i.hostSystem)),
      AppInfoRow(
        tr('app_info_compiled_to'),
        i.isWasm ? 'WebAssembly' : 'JavaScript',
      ),
      AppInfoRow(
        tr('app_info_renderer'),
        i.usesSkwasm ? 'skwasm' : 'CanvasKit',
      ),
    ] else ...[
      AppInfoRow(tr('app_info_os_version'), orDash(i.hostSystem)),
      if (i.impeller != null)
        AppInfoRow(tr('app_info_impeller'), yesNo(i.impeller!)),
    ],

    // Server.
    if (i.serverUrl != null) ...[
      AppInfoRow(tr('server'), orDash(i.serverUrl!)),
      AppInfoRow(
        tr('app_info_hosting'),
        tr(i.isHosted ? 'hosted' : 'selfhosted'),
      ),
      AppInfoRow(tr('app_info_server_version'), orDash(i.serverVersion)),
      AppInfoRow(tr('plan'), orDash(i.plan)),
      AppInfoRow(tr('app_info_report_errors'), yesNo(i.reportErrors)),
    ],

    // Display.
    AppInfoRow(
      tr('app_info_screen_size'),
      '${i.screenSize.width.round()} × ${i.screenSize.height.round()}',
    ),
    AppInfoRow(tr('app_info_pixel_ratio'), fixed(i.pixelRatio)),
    AppInfoRow(tr('app_info_text_scale'), fixed(i.textScale)),
    AppInfoRow(tr('app_info_locale'), i.locale.toLanguageTag()),
    AppInfoRow(
      tr('app_info_text_direction'),
      i.textDirection == ui.TextDirection.rtl ? 'RTL' : 'LTR',
    ),
    AppInfoRow(
      tr('theme'),
      tr(i.brightness == ui.Brightness.dark ? 'dark' : 'light'),
    ),
    AppInfoRow(
      tr('app_info_display_features'),
      i.foldFeatures.isEmpty ? tr('none') : i.foldFeatures.join(', '),
    ),
    if (i.foldFeatures.isNotEmpty)
      AppInfoRow(tr('app_info_book_posture'), yesNo(i.bookPosture)),
  ];
}

/// [rows] as plain text, one `label: value` line each — what Copy all writes.
String appInfoText(List<AppInfoRow> rows) =>
    rows.map((r) => '${r.label}: ${r.value}').join('\n');
