import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/ui/features/shell/widgets/plan_expired_footer.dart';

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
  _FakeServices({required this.auth});
  @override
  final AuthRepository auth;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// React #3222's "Account plan expired — Pay now", for the owner of a lapsed
/// hosted plan (or ended trial) only.
void main() {
  AuthSession session({
    bool isHosted = true,
    bool isOwner = true,
    String plan = 'pro',
    String planExpires = '2000-01-01',
  }) => AuthSession(
    baseUrl: 'https://example.test',
    isHosted: isHosted,
    accountId: 'acc',
    companies: [
      AuthCompany(
        id: 'co',
        name: 'Co',
        displayName: 'Co',
        permissions: '',
        isAdmin: isOwner,
        isOwner: isOwner,
      ),
    ],
    currentCompanyId: 'co',
    plan: plan,
    planExpires: planExpires,
  );

  test('shows for the owner of a lapsed hosted plan', () {
    expect(PlanExpiredFooter.shows(session()), isTrue);
    // What a live server actually sends once the date has passed:
    // `Account::getPlan()` blanks `plan` from then on.
    expect(PlanExpiredFooter.shows(session(plan: '')), isTrue);
  });

  test('never for a non-owner, self-hosted, a live plan, or no expiry', () {
    expect(PlanExpiredFooter.shows(session(isOwner: false)), isFalse);
    expect(PlanExpiredFooter.shows(session(isHosted: false)), isFalse);
    expect(
      PlanExpiredFooter.shows(session(planExpires: '2999-01-01')),
      isFalse,
    );
    // Never had a plan or a trial.
    expect(
      PlanExpiredFooter.shows(session(plan: '', planExpires: '')),
      isFalse,
    );
    expect(PlanExpiredFooter.shows(null), isFalse);
  });

  group('Pay Now', () {
    tearDown(() => debugStoreBillingOverride = null);

    Future<void> pump(WidgetTester tester, AuthSession s) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Provider<Services>.value(
            value: _FakeServices(auth: _FakeAuth(ValueNotifier(s))),
            child: const Scaffold(body: PlanExpiredFooter()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a store build: a plan still billed on the web is managed on '
        'the web, with no button', (tester) async {
      debugStoreBillingOverride = true;
      await pump(tester, session());

      expect(find.text('Your plan is managed on the web.'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('a store build: a blanked slug is a free account, offered '
        'the purchase', (tester) async {
      debugStoreBillingOverride = true;
      await pump(tester, session(plan: ''));

      expect(find.byType(InkWell), findsOneWidget);
      expect(find.text('Your plan is managed on the web.'), findsNothing);
    });

    testWidgets('desktop keeps Pay Now', (tester) async {
      debugStoreBillingOverride = false;
      await pump(tester, session());

      expect(find.byType(InkWell), findsOneWidget);
    });
  });
}
