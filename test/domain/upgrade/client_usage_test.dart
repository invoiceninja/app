// ClientUsage: the server's client total for a hosted Free plan account, plus
// creates still in the outbox — the count the clients list, the Plan screen
// and the New-client gate read (docs/free-plan-limits.md).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/client_limit.dart';
import 'package:admin/domain/upgrade/client_usage.dart';

AuthSession _session({
  bool isHosted = true,
  String plan = '',
  String companyId = 'co',
  int hostedClientCount = 5,
}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: isHosted,
  accountId: 'acct',
  currentCompanyId: companyId,
  userId: 'u1',
  plan: plan,
  planExpires: plan.isEmpty ? '' : '2099-01-01',
  hostedClientCount: hostedClientCount,
  companies: const [],
);

class _Harness {
  _Harness(AuthSession? initial) : session = ValueNotifier(initial) {
    usage = ClientUsage(
      session: session,
      fetchCount: () {
        fetches++;
        final c = Completer<int?>();
        answers.add(c);
        return c.future;
      },
      watchQueuedCreates: (companyId) =>
          (queued[companyId] ??= StreamController<int>.broadcast()).stream,
      refetchDelay: Duration.zero,
    );
  }

  final ValueNotifier<AuthSession?> session;
  final queued = <String, StreamController<int>>{};
  final answers = <Completer<int?>>[];
  int fetches = 0;

  late final ClientUsage usage;

  Future<void> answer(int? total, {int index = -1}) async {
    final c = index < 0 ? answers.last : answers[index];
    c.complete(total);
    await pumpEventQueue();
  }

  Future<void> queue(String companyId, int n) async {
    queued[companyId]!.add(n);
    await pumpEventQueue();
  }
}

void main() {
  test(
    'a free hosted account asks the server and reads used of limit',
    () async {
      final h = _Harness(_session());
      expect(h.usage.limit, 5);
      expect(h.fetches, 1);
      expect(h.usage.quota, isNull, reason: 'unknown until answered');
      await h.answer(3);
      expect(h.usage.quota, const ClientQuota(limit: 5, used: 3));
      h.usage.dispose();
    },
  );

  test('self-hosted and paid sessions ask nothing and have no quota', () async {
    for (final s in [_session(isHosted: false), _session(plan: 'pro')]) {
      final h = _Harness(s);
      await pumpEventQueue();
      expect(h.fetches, 0, reason: '$s');
      expect(h.usage.limit, isNull);
      expect(h.usage.quota, isNull);
      h.usage.dispose();
    }
  });

  test('creates waiting in the outbox count toward the cap', () async {
    final h = _Harness(_session());
    await h.answer(4);
    await h.queue('co', 1);
    expect(h.usage.quota, const ClientQuota(limit: 5, used: 5));
    expect(h.usage.quota!.blocksNewClient, isTrue);
    h.usage.dispose();
  });

  test('a create leaving the outbox asks the server again', () async {
    final h = _Harness(_session());
    await h.answer(4);
    await h.queue('co', 1);
    expect(h.fetches, 1);
    await h.queue('co', 0);
    await Future<void>.delayed(Duration.zero);
    expect(h.fetches, 2);
    await h.answer(5);
    expect(h.usage.quota, const ClientQuota(limit: 5, used: 5));
    h.usage.dispose();
  });

  test('an answer for the company switched away from is dropped', () async {
    final h = _Harness(_session(companyId: 'a'));
    h.session.value = _session(companyId: 'b');
    expect(h.fetches, 2);
    // Company b's answer lands first, then the stale one for a.
    await h.answer(2, index: 1);
    await h.answer(9, index: 0);
    expect(h.usage.quota, const ClientQuota(limit: 5, used: 2));
    h.usage.dispose();
  });

  test('upgrading clears the quota', () async {
    final h = _Harness(_session());
    await h.answer(5);
    expect(h.usage.quota, isNotNull);
    var notified = false;
    h.usage.addListener(() => notified = true);
    h.session.value = _session(plan: 'pro');
    expect(h.usage.quota, isNull);
    expect(notified, isTrue);
    h.usage.dispose();
  });

  test('a failed request leaves the count unknown, never zero', () async {
    final h = _Harness(_session());
    h.answers.last.completeError(Exception('offline'));
    await pumpEventQueue();
    expect(h.usage.quota, isNull);
    h.usage.dispose();
  });

  test('refresh honours maxAge', () async {
    final h = _Harness(_session());
    await h.answer(1);
    await h.usage.refresh(maxAge: const Duration(minutes: 1));
    expect(h.fetches, 1);
    unawaited(h.usage.refresh());
    expect(h.fetches, 2);
    await h.answer(2);
    expect(h.usage.quota!.used, 2);
    h.usage.dispose();
  });
}
