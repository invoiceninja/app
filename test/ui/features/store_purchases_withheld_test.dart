// A store build may ship before the hosted billing: until the hosted config
// says it sells in-app to the account (`inAppPurchasesOffered`), no prompt
// shows a way to buy, upgrade elsewhere or start a trial, and each says only
// which plan the feature is on (App Store 3.1.3(f), Play Payments policy;
// docs/in-app-purchases.md). Once the config says yes, every prompt is as it
// was; desktop, the web and F-Droid never change. The Plan tab, the footers,
// New company, the client limit and DocuNinja's seats are pinned beside
// their own tests; these are the prompts with no test file of their own.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/reports_repository.dart';
import 'package:admin/domain/docuninja/docuninja_access.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/domain/upgrade/purchase_offer.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/ui/features/docuninja/widgets/docuninja_states.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_actions.dart';
import 'package:admin/ui/features/reports/widgets/report_states.dart';
import 'package:admin/ui/features/settings/widgets/plan_gate_banner.dart';
import 'package:admin/utils/formatting.dart';

import '../../_localization_helper.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(AuthSession s) : session = ValueNotifier<AuthSession?>(s);
  @override
  final ValueNotifier<AuthSession?> session;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// In-person card payments on a plan below Pro.
class _FakeTerminal implements TerminalController {
  @override
  TerminalAvailability availabilityFor(String companyId, Invoice invoice) =>
      TerminalAvailability.upgrade;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices(AuthSession s) : auth = _FakeAuth(s);
  @override
  final AuthRepository auth;
  @override
  final TerminalController terminal = _FakeTerminal();
  @override
  Formatter? formatterIfReady(String companyId) => null;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AuthSession _free({bool isOwner = true, bool isHosted = true}) => AuthSession(
  baseUrl: isHosted ? 'https://invoicing.co' : 'https://in.example.test',
  isHosted: isHosted,
  accountId: 'acct',
  accountKey: 'acct-key',
  currentCompanyId: 'co',
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
);

/// The three builds a prompt can be on.
enum _Build { storeWithheld, storeOffered, desktop }

void _use(_Build build) {
  debugStoreBillingOverride = build != _Build.desktop;
  // Desktop never reads the offer: say no, to prove it.
  debugInAppPurchasesOfferedOverride = build == _Build.storeOffered;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AuthSession? session,
  PurchaseOffer? offer,
}) async {
  Widget app = MaterialApp(
    theme: buildInTheme(InTheme.light),
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: kTestSupportedLocales,
    home: Provider<Services>.value(
      value: _FakeServices(session ?? _free()),
      child: Scaffold(body: Center(child: child)),
    ),
  );
  if (offer != null) {
    app = ChangeNotifierProvider<PurchaseOffer>.value(value: offer, child: app);
  }
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

const _proPlans = 'This feature needs the Pro or Enterprise plan.';
const _docuNinjaPlans = 'DocuNinja needs the Pro or Enterprise plan.';

void main() {
  tearDown(() {
    debugStoreBillingOverride = null;
    debugInAppPurchasesOfferedOverride = null;
    debugInAppStoreOpenOverride = null;
  });

  group('PlanGateBanner', () {
    for (final style in PlanGateStyle.values) {
      testWidgets('${style.name}: a store build that sells nothing names the '
          'plans, with no button', (tester) async {
        _use(_Build.storeWithheld);
        await _pump(tester, PlanGateBanner(style: style));

        expect(find.text(_proPlans), findsOneWidget);
        expect(find.text('Manage Plan'), findsNothing);
        expect(find.textContaining('Upgrade'), findsNothing);
        expect(find.textContaining('trial'), findsNothing);
      });

      testWidgets('${style.name}: once the config sells here, Upgrade is '
          'back', (tester) async {
        _use(_Build.storeOffered);
        await _pump(tester, PlanGateBanner(style: style));

        expect(find.text(_proPlans), findsNothing);
        expect(find.text('Manage Plan'), findsOneWidget);
      });

      testWidgets('${style.name}: desktop is unchanged', (tester) async {
        _use(_Build.desktop);
        await _pump(tester, PlanGateBanner(style: style));

        expect(find.text(_proPlans), findsNothing);
        expect(find.text('Manage Plan'), findsOneWidget);
      });
    }

    testWidgets('an Enterprise gate names the Enterprise plan', (tester) async {
      _use(_Build.storeWithheld);
      await _pump(
        tester,
        const PlanGateBanner(
          style: PlanGateStyle.inset,
          level: PlanGateLevel.enterprise,
        ),
      );

      expect(find.text('Requires an Enterprise Plan'), findsOneWidget);
      expect(find.text('Manage Plan'), findsNothing);
    });

    testWidgets('once the store is open, a member is told the owner can '
        'upgrade, with no button', (tester) async {
      _use(_Build.storeWithheld);
      debugInAppStoreOpenOverride = true;
      await _pump(
        tester,
        const PlanGateBanner(style: PlanGateStyle.inset),
        session: _free(isOwner: false),
      );

      expect(
        find.text(
          'The account owner can upgrade to a paid plan to enable the '
          'advanced advanced settings',
        ),
        findsOneWidget,
      );
      expect(find.text('Manage Plan'), findsNothing);
    });

    testWidgets('a member is not told the owner can upgrade', (tester) async {
      _use(_Build.storeWithheld);
      await _pump(
        tester,
        const PlanGateBanner(style: PlanGateStyle.inset),
        session: _free(isOwner: false),
      );

      expect(find.text(_proPlans), findsOneWidget);
      expect(find.textContaining('upgrade'), findsNothing);
    });

    testWidgets('withheld only for a hosted session on a store build', (
      tester,
    ) async {
      for (final (build, session, expected) in [
        (_Build.storeWithheld, _free(), true),
        (_Build.storeOffered, _free(), false),
        (_Build.desktop, _free(), false),
        // Self-hosted has no hosted plan to sell, on any build.
        (_Build.storeWithheld, _free(isHosted: false), false),
      ]) {
        _use(build);
        await _pump(
          tester,
          Builder(builder: (context) => Text('${purchasesWithheld(context)}')),
          session: session,
        );
        expect(
          find.text('$expected'),
          findsOneWidget,
          reason: '${build.name}, hosted: ${session.isHosted}',
        );
      }
    });

    testWidgets('follows the offer live, without a rebuild from above', (
      tester,
    ) async {
      debugStoreBillingOverride = true;
      final offer = PurchaseOffer();
      addTearDown(offer.dispose);
      await _pump(
        tester,
        const PlanGateBanner(style: PlanGateStyle.inset),
        offer: offer,
      );
      expect(find.text(_proPlans), findsOneWidget);
      expect(find.text('Manage Plan'), findsNothing);

      offer.update(true);
      await tester.pumpAndSettle();
      expect(find.text(_proPlans), findsNothing);
      expect(find.text('Manage Plan'), findsOneWidget);
    });
  });

  group('DocuNinja', () {
    testWidgets('the plan wall names the plans, with no Upgrade', (
      tester,
    ) async {
      _use(_Build.storeWithheld);
      await _pump(tester, DocuNinjaPlanWallView(onUpgrade: () {}));

      expect(find.text(_docuNinjaPlans), findsOneWidget);
      expect(find.text('Upgrade Plan'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    for (final build in [_Build.storeOffered, _Build.desktop]) {
      testWidgets('the plan wall keeps Upgrade (${build.name})', (
        tester,
      ) async {
        _use(build);
        await _pump(tester, DocuNinjaPlanWallView(onUpgrade: () {}));

        expect(find.text(_docuNinjaPlans), findsNothing);
        expect(find.text('Upgrade Plan'), findsOneWidget);
      });
    }

    Widget join() => DocuNinjaJoinView(
      isAdmin: true,
      isEligible: false,
      isCreating: false,
      onCreate: () {},
      onUpgrade: () {},
    );

    testWidgets('Join on a lower plan names the plans, with no Upgrade', (
      tester,
    ) async {
      _use(_Build.storeWithheld);
      await _pump(tester, SingleChildScrollView(child: join()));

      expect(find.text(_docuNinjaPlans), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Upgrade'), findsNothing);
    });

    testWidgets('Join on a lower plan keeps Upgrade once the config sells', (
      tester,
    ) async {
      _use(_Build.storeOffered);
      await _pump(tester, SingleChildScrollView(child: join()));

      expect(find.text(_docuNinjaPlans), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Upgrade'), findsOneWidget);
    });

    testWidgets('another page sends a plan-walled user home in plain words', (
      tester,
    ) async {
      _use(_Build.storeWithheld);
      await _pump(
        tester,
        const DocuNinjaGoHomeState(access: DocuNinjaAccess.planWall),
      );
      expect(find.text(_docuNinjaPlans), findsOneWidget);
    });
  });

  group('Reports', () {
    String tr(String key, [Map<String, String>? params]) => key;
    const planRequired = ReportError(kind: ReportErrorKind.planRequired);

    test('a refused report names the plans when purchases are withheld', () {
      expect(
        reportErrorText(tr, planRequired, purchasesWithheld: true),
        'reports_need_pro_or_enterprise',
      );
      expect(reportErrorText(tr, planRequired), 'upgrade_to_view_reports');
    });

    testWidgets('read from the build and the offer', (tester) async {
      for (final (build, expected) in [
        (_Build.storeWithheld, 'Reports need the Pro or Enterprise plan.'),
        (_Build.storeOffered, 'Upgrade your plan to view reports'),
        (_Build.desktop, 'Upgrade your plan to view reports'),
      ]) {
        _use(build);
        await _pump(
          tester,
          Builder(
            builder: (context) =>
                Text(reportErrorMessage(context, planRequired)),
          ),
        );
        expect(find.text(expected), findsOneWidget, reason: build.name);
      }
    });
  });
  group('Collect card payment on a plan below Pro', () {
    Future<void> tapCollect(WidgetTester tester, {bool isOwner = true}) async {
      final session = _free(isOwner: isOwner);
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => InvoiceActions.collectCardPayment(
              context,
              context.read<Services>(),
              'co',
              Invoice.fromApi(const InvoiceApi(id: 'inv1')),
            ),
            child: const Text('collect'),
          ),
        ),
        session: session,
      );
      await tester.tap(find.text('collect'));
      await tester.pumpAndSettle();
    }

    const planRequired =
        'In-person card payments need the Pro or Enterprise plan.';

    for (final isOwner in [true, false]) {
      testWidgets('a store build that sells nothing says which plans, with '
          'Close only (owner: $isOwner)', (tester) async {
        _use(_Build.storeWithheld);
        await tapCollect(tester, isOwner: isOwner);

        expect(find.text(planRequired), findsOneWidget);
        expect(find.textContaining('upgrade'), findsNothing);
        expect(
          find.byKey(const ValueKey('terminal_plan_close')),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('terminal_plan_close')));
        await tester.pumpAndSettle();
        expect(find.text(planRequired), findsNothing);
      });
    }

    testWidgets('once the store is open, a member is told to ask the owner, '
        'still with Close only', (tester) async {
      _use(_Build.storeWithheld);
      debugInAppStoreOpenOverride = true;
      await tapCollect(tester, isOwner: false);

      expect(
        find.text(
          'In-person card payments need the Pro or Enterprise plan. Ask '
          'the account owner to upgrade.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('terminal_plan_close')), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    for (final build in [_Build.storeOffered, _Build.desktop]) {
      testWidgets('keeps its confirm, which leads to Upgrade (${build.name})', (
        tester,
      ) async {
        _use(build);
        await tapCollect(tester, isOwner: false);

        expect(
          find.text(
            'In-person card payments need the Pro or Enterprise plan. Ask '
            'the account owner to upgrade.',
          ),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byKey(const ValueKey('terminal_plan_close')), findsNothing);
      });
    }
  });
}
