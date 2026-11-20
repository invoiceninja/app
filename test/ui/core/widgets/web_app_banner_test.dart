import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/idle_timeout_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/app/web_app_banner_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/connectivity_watcher.dart';
import 'package:admin/domain/mobile_app_promo.dart';
import 'package:admin/domain/web_app_banner.dart';
import 'package:admin/ui/core/widgets/web_app_banner.dart';

import '../../../_localization_helper.dart';
import '../../../_support/fake_url_launcher.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(AuthSession? s) : session = ValueNotifier(s);

  @override
  final ValueNotifier<AuthSession?> session;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeServices implements Services {
  _FakeServices({
    required this.auth,
    required this.webAppBanner,
    required bool online,
  }) : connectivity = ConnectivityWatcher.fixed(online: online);

  @override
  final _FakeAuth auth;
  @override
  final WebAppBannerController webAppBanner;
  @override
  final ConnectivityWatcher connectivity;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeIdle implements IdleTimeoutController {
  final ValueNotifier<bool> expiring = ValueNotifier(false);

  @override
  ValueListenable<bool> get expiringSoon => expiring;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

AuthSession _session({
  String baseUrl = 'https://invoicing.co',
  bool isHosted = true,
}) => AuthSession(
  baseUrl: baseUrl,
  isHosted: isHosted,
  accountId: 'a1',
  companies: const [],
  currentCompanyId: 'c1',
);

Finder get _banner => find.byKey(const ValueKey('web_app_banner'));
Finder get _openWeb => find.byKey(const ValueKey('web_app_banner_open_web'));
Finder get _getApp => find.byKey(const ValueKey('web_app_banner_get_app'));
Finder get _dismiss => find.byKey(const ValueKey('web_app_banner_dismiss'));

void main() {
  late DevicePrefsStore prefs;
  late WebAppBannerController controller;
  late _FakeServices services;
  late _FakeIdle idle;

  setUp(() {
    prefs = DevicePrefsStore(null);
    controller = WebAppBannerController(prefs: prefs);
    idle = _FakeIdle();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool isWeb = true,
    bool isDemoBuild = false,
    bool demoMode = false,
    AuthSession? session,
    bool signedIn = true,
    bool online = true,
    bool withServices = true,
    TextDirection direction = TextDirection.ltr,
    double width = 1200,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    services = _FakeServices(
      auth: _FakeAuth(signedIn ? (session ?? _session()) : null),
      webAppBanner: controller,
      online: online,
    );
    final banner = WebAppBanner(
      isWeb: isWeb,
      isDemoBuild: isDemoBuild,
      demoMode: demoMode,
    );
    final app = MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: Scaffold(
        body: Column(
          children: [
            banner,
            const Expanded(child: Placeholder()),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      withServices
          ? MultiProvider(
              providers: [
                Provider<Services>.value(value: services),
                Provider<IdleTimeoutController>.value(value: idle),
              ],
              child: app,
            )
          : app,
    );
    await tester.pump();
  }

  group('where it shows', () {
    testWidgets('off the web it is nothing, and reads no Services', (
      tester,
    ) async {
      await pump(tester, isWeb: false, withServices: false);
      expect(_banner, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on the web, signed in to hosted, it shows', (tester) async {
      await pump(tester);
      expect(_banner, findsOneWidget);
      expect(
        find.text(
          'For the best experience, use Invoice Ninja Web or install the app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Open Invoice Ninja Web'), findsOneWidget);
      // flutter_test reports Android unless a variant says otherwise.
      expect(find.text('Get the Android app'), findsOneWidget);
    });

    testWidgets('never in the demo build', (tester) async {
      await pump(tester, isDemoBuild: true, withServices: false);
      expect(_banner, findsNothing);
    });

    testWidgets('never in demo mode', (tester) async {
      await pump(tester, demoMode: true, withServices: false);
      expect(_banner, findsNothing);
    });

    testWidgets('never on the demo server', (tester) async {
      await pump(
        tester,
        session: _session(baseUrl: 'https://demo.invoiceninja.com'),
      );
      expect(_banner, findsNothing);
    });

    testWidgets('never signed out', (tester) async {
      await pump(tester, signedIn: false);
      expect(_banner, findsNothing);

      services.auth.session.value = _session();
      await tester.pump();
      expect(_banner, findsOneWidget);
    });

    testWidgets('stands down while offline', (tester) async {
      await pump(tester, online: false);
      expect(_banner, findsNothing);
    });

    testWidgets('stands down while the session-expiry strip is up', (
      tester,
    ) async {
      await pump(tester);
      expect(_banner, findsOneWidget);

      idle.expiring.value = true;
      await tester.pump();
      expect(_banner, findsNothing);

      idle.expiring.value = false;
      await tester.pump();
      expect(_banner, findsOneWidget);
    });

    testWidgets(
      'self-hosted on a platform with no app has nothing to offer, so nothing '
      'shows',
      (tester) async {
        await pump(tester, session: _session(isHosted: false));
        expect(_banner, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.fuchsia),
    );
  });

  group('the buttons', () {
    testWidgets('Open Invoice Ninja Web opens hosted React', (tester) async {
      final launcher = installFakeUrlLauncher();
      await pump(tester);
      await tester.tap(_openWeb);
      await tester.pump();
      expect(launcher.launched, [kHostedReactUrl]);
    });

    final nativeTargets = <TargetPlatform, (String, String)>{
      TargetPlatform.iOS: ('Get the iPhone and iPad app', kMobileAppIosUrl),
      TargetPlatform.android: ('Get the Android app', kMobileAppAndroidUrl),
      TargetPlatform.macOS: ('Get the Mac app', kMacAppUrl),
      TargetPlatform.windows: ('Get the Windows app', kWindowsAppUrl),
      TargetPlatform.linux: (
        'Get the Linux app',
        'https://flathub.org/apps/com.invoiceninja.InvoiceNinja',
      ),
    };
    for (final MapEntry(key: platform, value: (label, url))
        in nativeTargets.entries) {
      testWidgets('$label opens its download page', (tester) async {
        final launcher = installFakeUrlLauncher();
        await pump(tester);
        expect(find.text(label), findsOneWidget);
        await tester.tap(_getApp);
        await tester.pump();
        expect(launcher.launched, [url]);
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets('a platform with no app offers only the web app', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.text('For the best experience, use Invoice Ninja Web.'),
        findsOneWidget,
      );
      expect(_openWeb, findsOneWidget);
      expect(_getApp, findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

    testWidgets('self-hosted offers only the native app', (tester) async {
      await pump(tester, session: _session(isHosted: false));
      expect(
        find.text('For the best experience, install the app.'),
        findsOneWidget,
      );
      expect(_openWeb, findsNothing);
      expect(_getApp, findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('dismissing', () {
    testWidgets('the ✕ hides it and stores the choice', (tester) async {
      await pump(tester);
      expect(find.byTooltip("Don't show this again"), findsOneWidget);

      await tester.tap(_dismiss);
      await tester.pump();
      expect(_banner, findsNothing);
      expect(prefs.read(DevicePrefKeys.webAppBannerDismissed), isTrue);

      // A fresh owner on the same store (the next launch) stays dismissed.
      controller = WebAppBannerController(prefs: prefs);
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(_banner, findsNothing);
    });

    testWidgets('a sign-out does not bring it back', (tester) async {
      await pump(tester);
      await tester.tap(_dismiss);
      await tester.pump();

      prefs.forgetWiped();
      await tester.pump();
      expect(controller.dismissed, isTrue);
      expect(_banner, findsNothing);
    });

    test('the choice survives a relaunch', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final first = DevicePrefsStore(db);
      await first.load();
      await WebAppBannerController(prefs: first).dismiss();

      final next = DevicePrefsStore(db);
      await next.load();
      expect(WebAppBannerController(prefs: next).dismissed, isTrue);
    });
  });

  group('sizing', () {
    testWidgets('one slim line with a pointer', (tester) async {
      // The test font draws every glyph a full em wide, so the sentence and
      // both buttons need about twice the width real text does.
      await pump(tester, width: 2400);
      expect(tester.getSize(_banner).height, lessThanOrEqualTo(32));
      expect(tester.getSize(_dismiss).height, 28);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('44 px targets on touch, wrapping on a phone', (tester) async {
      await pump(tester, width: 390);
      expect(tester.takeException(), isNull);
      for (final target in [_openWeb, _getApp, _dismiss]) {
        expect(
          tester.getSize(target).height,
          greaterThanOrEqualTo(InSizes.touchTarget),
        );
      }
      // The buttons wrap under the sentence.
      final text = find.text(
        'For the best experience, use Invoice Ninja Web or install the app.',
      );
      expect(
        tester.getTopLeft(_openWeb).dy,
        greaterThan(tester.getTopLeft(text).dy),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  testWidgets('right-to-left: the icon leads at the right, the ✕ at the left', (
    tester,
  ) async {
    await pump(tester, direction: TextDirection.rtl);
    expect(tester.takeException(), isNull);
    final icon = find.descendant(
      of: _banner,
      matching: find.byIcon(Icons.devices_outlined),
    );
    expect(
      tester.getCenter(icon).dx,
      greaterThan(tester.getCenter(_dismiss).dx),
    );
    expect(
      tester.getCenter(icon).dx,
      greaterThan(tester.getCenter(_openWeb).dx),
    );
  });

  testWidgets('drawn in the info tokens', (tester) async {
    await pump(tester);
    expect(tester.widget<Material>(_banner).color, InTheme.light.accentSoft);
  });
}
