// The plan-gate banner never promises a free trial on a store build: a hosted
// trial starts on the web with a card, and the button there opens the store
// sheet, which sells a paid plan.

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/ui/features/settings/widgets/plan_gate_banner.dart';

AuthSession _free() => const AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct',
  companies: [],
  currentCompanyId: '',
);

void main() {
  test('a trial-eligible free account is offered the trial off store', () {
    expect(_free().isEligibleForTrial, isTrue);
    final copy = planGateCopy(
      PlanGateLevel.pro,
      _free(),
      isOwner: true,
      storeBilling: false,
    );
    expect(copy.key, 'start_free_trial_message');
  });

  test('a store build gets the neutral upgrade copy instead', () {
    final copy = planGateCopy(
      PlanGateLevel.pro,
      _free(),
      isOwner: true,
      storeBilling: true,
    );
    expect(copy.key, 'upgrade_to_paid_plan');
  });

  test('a non-owner still gets the ask-your-owner copy on a store build', () {
    final copy = planGateCopy(
      PlanGateLevel.pro,
      _free(),
      isOwner: false,
      storeBilling: true,
    );
    expect(copy.key, 'owner_upgrade_to_paid_plan');
  });
}
