// The hosted Free plan's client cap, as the app reads it (docs/free-plan-limits.md):
// who it applies to, how usage against it is worded, how a hosted trial is
// recognised, and that Upgrade really opens for an account whose plan lapsed
// with more clients than the cap.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/login_response_api_model.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/client_limit.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';

// The real clock: `isPlanExpired` reads it, so every date here is relative.
final _now = DateTime.now().toUtc();

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

AuthSession _session({
  bool isHosted = true,
  String plan = '',
  String planExpires = '',
  String trialStarted = '',
  bool hasIapPlan = false,
  int hostedClientCount = 5,
  bool isOwner = true,
}) => AuthSession(
  baseUrl: isHosted ? 'https://invoicing.co' : 'https://in.example.test',
  isHosted: isHosted,
  accountId: 'acct',
  currentCompanyId: 'co',
  plan: plan,
  planExpires: planExpires,
  trialStarted: trialStarted,
  hasIapPlan: hasIapPlan,
  hostedClientCount: hostedClientCount,
  ninjaPortalUrl: 'https://invoicing.co/portal',
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

void main() {
  group('the session carries hosted_client_count', () {
    test('from the login envelope, and back out of the stored blob', () {
      final account = AccountEnvelopeApi.fromJson(const {
        'id': 'acct',
        'plan': '',
        'hosted_client_count': 5,
        'hosted_company_count': 1,
      });
      final session = _session(hostedClientCount: 0).withAccount(account);
      expect(session.hostedClientCount, 5);
      // `_persistAndActivate` stores `toJson()` as the account row's
      // `features_json`, which a restore reads `hosted_client_count` from.
      final stored =
          jsonDecode(jsonEncode(account.toJson())) as Map<String, dynamic>;
      expect(stored['hosted_client_count'], 5);
    });
  });

  group('freePlanClientLimit', () {
    test('a free hosted account has the server cap', () {
      expect(freePlanClientLimit(_session()), 5);
      expect(freePlanClientLimit(_session(plan: 'free')), 5);
      expect(freePlanClientLimit(_session(hostedClientCount: 7)), 7);
    });

    test('self-hosted never has one', () {
      expect(freePlanClientLimit(_session(isHosted: false)), isNull);
      expect(isFreeHostedClientPlan(_session(isHosted: false)), isFalse);
    });

    test('a live paid plan or trial has none', () {
      final future = _day(_now.add(const Duration(days: 30)));
      expect(
        freePlanClientLimit(_session(plan: 'pro', planExpires: future)),
        isNull,
      );
      expect(
        freePlanClientLimit(_session(plan: 'enterprise', planExpires: future)),
        isNull,
      );
    });

    test('a paid plan whose date has run out is Free again', () {
      expect(
        freePlanClientLimit(_session(plan: 'pro', planExpires: '2020-01-01')),
        5,
      );
    });

    test('an unknown cap (0) shows nothing rather than a zero', () {
      expect(freePlanClientLimit(_session(hostedClientCount: 0)), isNull);
    });

    test('no session, no cap', () {
      expect(freePlanClientLimit(null), isNull);
    });
  });

  group('ClientQuota', () {
    test('under, at and over the cap', () {
      const under = ClientQuota(limit: 5, used: 3);
      const at = ClientQuota(limit: 5, used: 5);
      const over = ClientQuota(limit: 5, used: 11);
      expect(under.state, ClientQuotaState.underLimit);
      expect(under.blocksNewClient, isFalse);
      expect(at.state, ClientQuotaState.atLimit);
      expect(at.blocksNewClient, isTrue);
      expect(over.state, ClientQuotaState.overLimit);
      expect(over.blocksNewClient, isTrue);
    });

    test('an unknown count or cap is no quota, so it never blocks', () {
      expect(clientQuotaOf(limit: 5, used: null), isNull);
      expect(clientQuotaOf(limit: null, used: 9), isNull);
      expect(
        clientQuotaOf(limit: 5, used: 2),
        const ClientQuota(limit: 5, used: 2),
      );
    });

    test('never a negative count', () {
      expect(clientQuotaOf(limit: 5, used: -1)!.used, 0);
    });
  });

  group('hostedTrialEndsOn', () {
    // `finalizeTrialAccount`: plan pro, trial_started, plan_expires 14 days on.
    final started = _now.subtract(const Duration(days: 4));
    final ends = started.add(const Duration(days: 14));

    test('a hosted trial ends on its plan_expires day', () {
      final s = _session(
        plan: 'pro',
        trialStarted: started.toIso8601String(),
        planExpires: _day(ends),
      );
      expect(
        hostedTrialEndsOn(s, now: _now),
        DateTime.utc(ends.year, ends.month, ends.day),
      );
      // ...and is not under the cap until then.
      expect(freePlanClientLimit(s), isNull);
    });

    test('a plan paid after the trial is not a trial', () {
      final s = _session(
        plan: 'pro',
        trialStarted: started.toIso8601String(),
        planExpires: _day(started.add(const Duration(days: 44))),
      );
      expect(hostedTrialEndsOn(s, now: _now), isNull);
    });

    test('a trial that has ended, a store plan, or self-hosted: none', () {
      final old = _now.subtract(const Duration(days: 30));
      expect(
        hostedTrialEndsOn(
          _session(
            plan: 'pro',
            trialStarted: old.toIso8601String(),
            planExpires: _day(old.add(const Duration(days: 14))),
          ),
          now: _now,
        ),
        isNull,
      );
      expect(
        hostedTrialEndsOn(
          _session(
            plan: 'pro',
            hasIapPlan: true,
            trialStarted: started.toIso8601String(),
            planExpires: _day(ends),
          ),
          now: _now,
        ),
        isNull,
      );
      expect(
        hostedTrialEndsOn(
          _session(
            isHosted: false,
            plan: 'pro',
            trialStarted: started.toIso8601String(),
            planExpires: _day(ends),
          ),
          now: _now,
        ),
        isNull,
      );
    });

    test('never started a trial', () {
      expect(
        hostedTrialEndsOn(
          _session(plan: 'pro', planExpires: _day(ends)),
          now: _now,
        ),
        isNull,
      );
    });
  });

  test('a rejection keyed on id is the client cap', () {
    expect(
      isClientLimitRejection(const {
        'id': ["You've hit the 5 client limit on Free accounts."],
      }),
      isTrue,
    );
    expect(
      isClientLimitRejection(const {
        'name': ['required'],
      }),
      isFalse,
    );
  });

  group('Upgrade opens for an account over the cap', () {
    // A Pro plan that lapsed with 11 clients: the server blanks the slug
    // (`Account::getPlan`) and keeps the old date.
    final lapsed = _session(
      plan: '',
      planExpires: _day(_now.subtract(const Duration(days: 80))),
    );

    test('it is a Free plan account', () {
      expect(freePlanClientLimit(lapsed), 5);
      expect(
        const ClientQuota(limit: 5, used: 11).state,
        ClientQuotaState.overLimit,
      );
    });

    test('off the stores it opens the billing portal', () {
      expect(
        resolveUpgradeRoute(
          purchasesOffered: true,
          storeBilling: false,
          session: lapsed,
          now: _now,
        ),
        UpgradeRoute.billingPortal,
      );
    });

    test('on a store build its owner gets the purchase sheet', () {
      expect(
        resolveUpgradeRoute(
          purchasesOffered: true,
          storeBilling: true,
          session: lapsed,
          now: _now,
        ),
        UpgradeRoute.purchaseSheet,
      );
    });
  });
}
