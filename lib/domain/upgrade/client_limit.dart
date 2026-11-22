import 'package:flutter/foundation.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';

/// The hosted Free plan's client cap before an account exists — the server's
/// default, `config/ninja.php` → `quotas.free.clients`, which `CreateAccount`
/// copies into `accounts.hosted_client_count`. Only the signup screen reads
/// this: once signed in, the account's own `hosted_client_count` is the cap.
const int kFreePlanClientLimit = 5;

/// The hosted Free plan's company cap, `config/ninja.php` →
/// `quotas.free.max_companies`. The signup line says "one company" in words.
const int kFreePlanCompanyLimit = 1;

/// Whether [session] is under the hosted Free plan's client cap — the server's
/// `Account::isFreeHostedClient()`, which adds `CanStoreClientsRule` to a
/// client create: a hosted plan that is free (blank slug) or whose paid date
/// has run out. Never self-hosted, which has no client limit at all.
///
/// A hosted trial is `plan: pro` with `plan_expires` at the trial's end
/// (`NinjaPlanController::finalizeTrialAccount`), so it is not limited until
/// that date passes — see [hostedTrialEndsOn].
bool isFreeHostedClientPlan(AuthSession? session) =>
    session != null &&
    session.isHosted &&
    (!session.isPaidPlanSlug || session.isPlanExpired);

/// The cap on clients for [session], or null when there is none to show:
/// self-hosted, a live paid plan or trial, or an account whose
/// `hosted_client_count` is unknown (0 — the server sends 5 for every hosted
/// account it creates, so 0 is a row written before the field was read).
int? freePlanClientLimit(AuthSession? session) {
  if (!isFreeHostedClientPlan(session)) return null;
  final limit = session!.hostedClientCount;
  return limit > 0 ? limit : null;
}

/// Where an account stands against its Free plan client cap.
enum ClientQuotaState {
  /// Room for at least one more.
  underLimit,

  /// Exactly at the cap: the next create is refused.
  atLimit,

  /// More clients than the cap — a plan or trial lapsed after they were
  /// added. Every one is kept; only a new one is refused.
  overLimit,
}

/// A Free plan account's client usage: [used] of [limit]. [used] is the
/// server's total for the company — every client, archived and deleted ones
/// included, as `CanStoreClientsRule` counts `$company->clients()`
/// (`withTrashed`) — plus creates still waiting in the outbox.
@immutable
class ClientQuota {
  const ClientQuota({required this.limit, required this.used});

  final int limit;
  final int used;

  ClientQuotaState get state => used < limit
      ? ClientQuotaState.underLimit
      : used == limit
      ? ClientQuotaState.atLimit
      : ClientQuotaState.overLimit;

  /// Whether a new client would be refused by the server.
  bool get blocksNewClient => used >= limit;

  @override
  bool operator ==(Object other) =>
      other is ClientQuota && other.limit == limit && other.used == used;

  @override
  int get hashCode => Object.hash(limit, used);

  @override
  String toString() => 'ClientQuota($used of $limit)';
}

/// [limit] and [used] as a quota, or null when either is unknown — and an
/// unknown count never blocks a create (the server's 422 still stands behind
/// it).
ClientQuota? clientQuotaOf({required int? limit, required int? used}) =>
    (limit == null || used == null)
    ? null
    : ClientQuota(limit: limit, used: used < 0 ? 0 : used);

/// The day a hosted Pro trial ends, or null when [session] is not in one.
///
/// The login envelope carries no trial flag a client can trust on hosted:
/// `trial_days_left` is a literal 0 there (`AccountTransformer`), so
/// [AuthSession.isTrial] reads false, and `is_trial` is not sent. What a trial
/// does leave is its shape: `finalizeTrialAccount` sets `plan: pro`,
/// `trial_started` and `plan_expires` at the trial's end, 14 days on. A plan
/// paid after the trial moves `plan_expires` past that window, which is what
/// tells the two apart here. A store-billed plan is never a trial.
DateTime? hostedTrialEndsOn(AuthSession session, {DateTime? now}) {
  if (!session.isHosted || session.hasIapPlan) return null;
  if (!session.isPaidPlanSlug) return null;
  final started = DateTime.tryParse(session.trialStarted.trim());
  final raw = session.planExpires.trim();
  if (started == null || raw.length < 10) return null;
  final ends = DateTime.tryParse('${raw.substring(0, 10)}T00:00:00Z');
  if (ends == null) return null;
  if (hostedPlanDateExpired(raw, now ?? DateTime.now())) return null;
  // Longer than a trial: a paid plan that followed one.
  if (ends.difference(started).inDays > kHostedTrialMaxDays) return null;
  return ends;
}

/// The longest gap between `trial_started` and `plan_expires` still read as
/// a trial. Hosted trials run 14 days (`NinjaPlanController`); a week of slack
/// covers a trial whose end follows its recurring invoice's send date, and
/// stays well short of the month a paid plan adds.
const int kHostedTrialMaxDays = 21;

/// Whether a rejected client create is the Free plan's client cap. The server
/// keys `CanStoreClientsRule` on `id` (`StoreClientRequest::rules`), a field
/// no client form has, and translates its message (`texts.limit_clients`), so
/// the key is what is matched, never the text.
bool isClientLimitRejection(Map<String, List<String>> fieldErrors) =>
    fieldErrors.containsKey('id');

/// Whether a rejected import is the Free plan's client cap: the server's
/// `ValidatesClientImportLimit` adds `limit_clients` under `files.client` (a
/// file sent with the request) or `column_map.client` (the preview's cached
/// copy, by hash). Only read for a session [freePlanClientLimit] limits; the
/// same keys carry a file-type error on any plan.
bool isClientImportLimitRejection(Map<String, List<String>> fieldErrors) =>
    fieldErrors.containsKey('files.client') ||
    fieldErrors.containsKey('column_map.client');
