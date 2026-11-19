// Account Management → Plan, the hosted "Change Plan" card. A store build
// never links to the web billing portal (App Store 3.1.1(a), Play Payments 4),
// manages an in-app plan in the store, and doesn't sell over a web-billed
// plan. Desktop, the web and F-Droid keep the portal button.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/ui/features/settings/views/basic/account_management/plan_screen.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../../../_localization_helper.dart';

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
  _FakeServices({required this.auth});
  @override
  final AuthRepository auth;

  @override
  Formatter? formatterIfReady(String companyId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AuthSession _session({
  String plan = '',
  String planExpires = '',
  bool hasIapPlan = false,
  int trialDaysLeft = -1,
  String ninjaPortalUrl =
      'https://invoiceninja.invoicing.co/client/key_login/x',
}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct',
  companies: const [],
  currentCompanyId: '',
  plan: plan,
  planExpires: planExpires,
  hasIapPlan: hasIapPlan,
  trialDaysLeft: trialDaysLeft,
  ninjaPortalUrl: ninjaPortalUrl,
);

final _activeIap = _session(
  plan: 'pro',
  planExpires: '2099-01-01',
  hasIapPlan: true,
);
final _webPaid = _session(plan: 'enterprise', planExpires: '2099-01-01');
final _trial = _session(plan: 'pro', trialDaysLeft: 7);
final _free = _session();

Future<void> _pump(
  WidgetTester tester,
  AuthSession session, {
  required bool storeBuild,
}) async {
  debugStoreBillingOverride = storeBuild;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Provider<Services>.value(
        value: _FakeServices(auth: _FakeAuth(ValueNotifier(session))),
        child: const Scaffold(body: AccountManagementPlanScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _billedInStore =
    'Your plan is billed through the app store you subscribed in.';
const _billedOnWeb = 'Your plan is billed on the web.';

void main() {
  tearDown(() => debugStoreBillingOverride = null);

  group('store build', () {
    testWidgets('an active in-app plan gets Manage subscription', (
      tester,
    ) async {
      await _pump(tester, _activeIap, storeBuild: true);

      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Manage Plan'), findsOneWidget); // the card title only
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a web-billed plan says so, with no button to the portal', (
      tester,
    ) async {
      await _pump(tester, _webPaid, storeBuild: true);

      expect(find.text(_billedOnWeb), findsOneWidget);
      expect(find.bySubtype<FilledButton>(), findsNothing);
      expect(find.bySubtype<OutlinedButton>(), findsNothing);
      expect(find.text('Manage subscription'), findsNothing);
    });

    testWidgets('a trial (a web card trial) is billed on the web too', (
      tester,
    ) async {
      await _pump(tester, _trial, storeBuild: true);

      expect(find.text(_billedOnWeb), findsOneWidget);
      expect(find.text('Upgrade Plan'), findsNothing);
    });

    testWidgets('a free account gets Upgrade, enabled without a portal URL', (
      tester,
    ) async {
      await _pump(tester, _session(ninjaPortalUrl: ''), storeBuild: true);

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Upgrade Plan'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text(_billedOnWeb), findsNothing);
    });
  });

  group('desktop, web and F-Droid', () {
    testWidgets('an active in-app plan is text only: no Manage, no portal', (
      tester,
    ) async {
      await _pump(tester, _activeIap, storeBuild: false);

      expect(find.text(_billedInStore), findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
      expect(find.bySubtype<FilledButton>(), findsNothing);
      // The old copy told a Mac or web user to "use your phone".
      expect(find.textContaining('phone'), findsNothing);
    });

    testWidgets('a web-billed plan keeps Change Plan to the portal', (
      tester,
    ) async {
      await _pump(tester, _webPaid, storeBuild: false);

      expect(find.text(_billedOnWeb), findsNothing);
      expect(find.text('Manage Plan'), findsNWidgets(2));
    });

    testWidgets('a free account keeps Upgrade Plan', (tester) async {
      await _pump(tester, _free, storeBuild: false);

      expect(find.text('Upgrade Plan'), findsOneWidget);
    });
  });
}
