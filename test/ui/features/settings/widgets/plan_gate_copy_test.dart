// The plan-gate banner never promises a free trial on a store build: a hosted
// trial starts on the web with a card, and the button there opens the store
// sheet, which sells a paid plan. Nor does it offer a store build's trial or
// web-billed plan a button that could only say the plan is managed on the
// web.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';
import 'package:admin/ui/features/settings/widgets/plan_gate_banner.dart';

AuthSession _session({String plan = '', int trialDaysLeft = -1}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct',
  companies: const [
    AuthCompany(
      id: 'co',
      name: 'Co',
      displayName: 'Co',
      permissions: '',
      isAdmin: true,
      isOwner: true,
    ),
  ],
  currentCompanyId: 'co',
  plan: plan,
  trialDaysLeft: trialDaysLeft,
);

PlanGateCopy _copy(
  AuthSession s, {
  required bool storeBilling,
  PlanGateLevel level = PlanGateLevel.pro,
  bool isOwner = true,
  bool offered = true,
}) {
  final withheld = storePurchasesWithheld(
    storeBilling: storeBilling,
    session: s,
    offered: offered,
  );
  return planGateCopy(
    level,
    s,
    isOwner: isOwner,
    route: resolveUpgradeRoute(
      purchasesOffered: !withheld,
      storeBilling: storeBilling,
      session: s,
      now: DateTime.utc(2026, 11, 20, 12),
    ),
    purchasesWithheld: withheld,
  );
}

void main() {
  test('a trial-eligible free account is offered the trial off store', () {
    expect(_session().isEligibleForTrial, isTrue);
    final copy = _copy(_session(), storeBilling: false);
    expect(copy.key, 'start_free_trial_message');
    expect(copy.cta, isTrue);
  });

  test('a store build gets the neutral upgrade copy instead', () {
    final copy = _copy(_session(), storeBilling: true);
    expect(copy.key, 'upgrade_to_paid_plan');
    expect(copy.cta, isTrue);
  });

  test('a non-owner still gets the ask-your-owner copy on a store build', () {
    final copy = _copy(_session(), storeBilling: true, isOwner: false);
    expect(copy.key, 'owner_upgrade_to_paid_plan');
    expect(copy.cta, isFalse);
  });

  group('a store build with a plan billed on the web', () {
    test('a Pro plan at an Enterprise gate: managed on the web, no '
        'button', () {
      final copy = _copy(
        _session(plan: 'pro'),
        storeBilling: true,
        level: PlanGateLevel.enterprise,
      );
      expect(copy.key, 'plan_managed_on_web');
      expect(copy.cta, isFalse);
    });

    test('a trial: managed on the web, no button', () {
      final copy = _copy(
        _session(trialDaysLeft: 5),
        storeBilling: true,
        level: PlanGateLevel.enterprise,
      );
      expect(copy.key, 'plan_managed_on_web');
      expect(copy.cta, isFalse);
    });

    test('desktop keeps its copy and button', () {
      final copy = _copy(
        _session(plan: 'pro'),
        storeBilling: false,
        level: PlanGateLevel.enterprise,
      );
      expect(copy.key, 'requires_an_enterprise_plan');
      expect(copy.cta, isTrue);
    });
  });

  // Until the hosted config sells to the account, a store build says only
  // which plans have the feature: no button, no "upgrade", no trial, and no
  // "the owner can upgrade" (App Store 3.1.3(f), Play Payments policy).
  group('a store build that sells nothing', () {
    test('a free account at a Pro gate: the plans, no button, no trial', () {
      final copy = _copy(_session(), storeBilling: true, offered: false);
      expect(copy.key, 'feature_needs_pro_or_enterprise');
      expect(copy.cta, isFalse);
    });

    test('an Enterprise gate names the Enterprise plan, no button', () {
      final copy = _copy(
        _session(),
        storeBilling: true,
        offered: false,
        level: PlanGateLevel.enterprise,
      );
      expect(copy.key, 'requires_an_enterprise_plan');
      expect(copy.cta, isFalse);
    });

    test('a member is told the owner can upgrade once the store is open, '
        'with no button', () {
      final withheld = storePurchasesWithheld(
        storeBilling: true,
        session: _session(),
        offered: false,
      );
      final copy = planGateCopy(
        PlanGateLevel.pro,
        _session(),
        isOwner: false,
        route: UpgradeRoute.planScreen,
        purchasesWithheld: withheld,
        storeOpen: true,
      );
      expect(copy.key, 'owner_upgrade_to_paid_plan');
      expect(copy.cta, isFalse);
      // The owner still gets the plans only: nothing is sold to them.
      expect(
        planGateCopy(
          PlanGateLevel.pro,
          _session(),
          isOwner: true,
          route: UpgradeRoute.planScreen,
          purchasesWithheld: withheld,
          storeOpen: true,
        ).key,
        'feature_needs_pro_or_enterprise',
      );
    });

    test('a member is not told the owner can upgrade while the store is '
        'closed', () {
      final copy = _copy(
        _session(),
        storeBilling: true,
        offered: false,
        isOwner: false,
      );
      expect(copy.key, 'feature_needs_pro_or_enterprise');
      expect(copy.cta, isFalse);
    });

    test('a plan billed on the web is still managed on the web', () {
      final copy = _copy(
        _session(plan: 'pro'),
        storeBilling: true,
        offered: false,
        level: PlanGateLevel.enterprise,
      );
      expect(copy.key, 'plan_managed_on_web');
      expect(copy.cta, isFalse);
    });

    test('desktop is unchanged whatever the offer', () {
      final copy = _copy(_session(), storeBilling: false, offered: false);
      expect(copy.key, 'start_free_trial_message');
      expect(copy.cta, isTrue);
    });
  });
}
