// The desktop-app promo's automatic opener and permanent entries on a phone
// (docs/desktop-app-promo.md). Like the phone-app promo's entry test, a light
// fake stands in for `Services`.

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/mobile_app_promo_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/core/dialogs/automatic_dialogs.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:admin/ui/features/mobile_promo/mobile_app_promo_host.dart';
import 'package:admin/ui/features/settings/widgets/desktop_app_section.dart';
import 'package:admin/ui/features/settings/widgets/mobile_app_section.dart';
import 'package:admin/ui/features/shell/widgets/mobile_app_promo_footer.dart';

import '../../../_localization_helper.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(this._session);
  final ValueNotifier<AuthSession?> _session;
  @override
  ValueListenable<AuthSession?> get session => _session;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices(AuthSession? session)
    : auth = _FakeAuth(ValueNotifier(session));
  @override
  final AuthRepository auth;
  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AuthSession _session({
  bool isHosted = true,
  String baseUrl = 'https://invoicing.co',
}) => AuthSession(
  baseUrl: baseUrl,
  isHosted: isHosted,
  accountId: 'acct',
  companies: [
    AuthCompany(
      id: 'co',
      name: 'Co',
      displayName: 'Co',
      permissions: '',
      isAdmin: true,
      isOwner: true,
      enabledModules: 0x7fffffff,
    ),
  ],
  currentCompanyId: 'co',
  userEmail: 'me@example.com',
);

const _title = 'Invoice Ninja on your computer';
const _entry = 'Get the desktop app';

void main() {
  final phones = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });
  tearDown(AutomaticDialogs.resetForTest);

  Future<MobileAppPromoController> pump(
    WidgetTester tester,
    Widget child, {
    AuthSession? session,
    bool promote = true,
    MobileAppPromoState state = const MobileAppPromoState(),
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = DevicePrefsStore(null);
    await prefs.write(DevicePrefKeys.desktopAppPromo, state.encode());
    final controller = MobileAppPromoController(
      prefs: prefs,
      promote: promote,
      prefKey: DevicePrefKeys.desktopAppPromo,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Provider<Services>.value(
          value: _FakeServices(session ?? _session()),
          child: ChangeNotifierProvider.value(value: controller, child: child),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  group('MobileAppPromoHost on a phone', () {
    const due = MobileAppPromoState(daysSeen: 3, lastDay: '2000-01-01');
    Widget host() => const MobileAppPromoHost(
      child: Scaffold(body: Center(child: Text('home'))),
    );

    testWidgets('opens the desktop promo on its own once due, and a close '
        'snoozes it', (tester) async {
      final c = await pump(tester, host(), state: due);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Invoice Ninja on your phone'), findsNothing);
      expect(c.shownThisLaunch, isTrue);

      await tester.tap(find.text('Remind me later'));
      await tester.pumpAndSettle();
      expect(c.state.closes, 1);
      expect(c.isDue(DateTime.now()), isFalse);
    }, variant: phones);

    testWidgets('not before the third day of use', (tester) async {
      final c = await pump(
        tester,
        host(),
        state: const MobileAppPromoState(daysSeen: 1, lastDay: '2000-01-01'),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(_title), findsNothing);
      expect(c.state.daysSeen, 2, reason: 'today counted');
    }, variant: phones);

    testWidgets('never for a server only this device reaches', (tester) async {
      await pump(
        tester,
        host(),
        state: due,
        session: _session(isHosted: false, baseUrl: 'http://localhost:8000'),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(_title), findsNothing);
    }, variant: phones);

    testWidgets('never unless the app asked for it', (tester) async {
      await pump(tester, host(), promote: false, state: due);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(_title), findsNothing);
    }, variant: phones);
  });

  group('DesktopAppSection (Device Settings)', () {
    Widget section() => const Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [MobileAppSection(), DesktopAppSection()]),
      ),
    );

    testWidgets('offers the promo on a phone, opened as a request, and '
        'the phone-app card stays away', (tester) async {
      await pump(tester, section(), promote: false);
      expect(find.text('Desktop app'), findsOneWidget);
      expect(find.text('Mobile app'), findsNothing);
      await tester.tap(find.text(_entry));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Remind me later'), findsNothing);
    }, variant: phones);

    testWidgets('absent for the demo and a loopback server', (tester) async {
      for (final url in [kDemoBaseUrl, 'http://127.0.0.1:8000']) {
        await pump(
          tester,
          section(),
          session: _session(isHosted: false, baseUrl: url),
        );
        expect(find.text('Desktop app'), findsNothing, reason: url);
      }
    }, variant: phones);

    testWidgets('absent on a computer', (tester) async {
      await pump(tester, section());
      expect(find.text('Desktop app'), findsNothing);
      expect(find.text('Mobile app'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  testWidgets('a phone gets no sidebar card for either promo', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: SizedBox(
          width: 232,
          child: Column(children: [MobileAppPromoFooter(touch: true)]),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  }, variant: phones);
}
