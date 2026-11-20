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
}) => planGateCopy(
  level,
  s,
  isOwner: isOwner,
  route: resolveUpgradeRoute(
    storeBilling: storeBilling,
    session: s,
    now: DateTime.utc(2026, 11, 20, 12),
  ),
);

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
}
