import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/client_limit.dart';

final _log = Logger('ClientUsage');

/// How long after a queued client create, purge or merge leaves the outbox
/// the server is asked again — long enough that a burst of saves is one
/// request.
const Duration kClientUsageRefetchDelay = Duration(milliseconds: 1500);

/// How old a count may be before a surface that opens asks again.
const Duration kClientUsageMaxAge = Duration(minutes: 1);

/// How old a count that just refused a New client may be before it is asked
/// for again — a refusal is when a stale-high number costs the most.
const Duration kClientUsageBlockedMaxAge = Duration(seconds: 10);

/// How many clients a hosted Free plan account holds, against its cap — what
/// the clients list's usage line, the Plan screen and the New-client gate all
/// read (docs/free-plan-limits.md).
///
/// **The count is the server's total**, never a Drift row count: lists page in
/// fifty at a time and a fresh device holds a handful, so a local count
/// under-reports exactly when it matters. Creates still in the outbox are
/// added on top, so an offline sixth client is caught before it becomes a
/// dead row, and queued purges and merges (which free a place: the server
/// force-deletes the record) are taken off.
///
/// Asks nothing for a session the cap does not apply to (self-hosted, a paid
/// plan, a trial). Unknown — offline before the first answer, a failed
/// request — leaves [quota] null, and a null quota never blocks.
class ClientUsage extends ChangeNotifier {
  ClientUsage({
    required ValueListenable<AuthSession?> session,
    required Future<int?> Function(String companyId) fetchCount,
    required Stream<({int creates, int removals})> Function(String companyId)
    watchQueued,
    this.refetchDelay = kClientUsageRefetchDelay,
    DateTime Function()? now,
  }) : _session = session,
       _fetchCount = fetchCount,
       _watchQueued = watchQueued,
       _now = now ?? DateTime.now {
    _session.addListener(_onSession);
    _onSession();
  }

  final ValueListenable<AuthSession?> _session;

  /// The server's total for the company named, or null when it cannot be
  /// asked for that company now (its token is not the active one).
  final Future<int?> Function(String companyId) _fetchCount;
  final Stream<({int creates, int removals})> Function(String companyId)
  _watchQueued;
  final Duration refetchDelay;
  final DateTime Function() _now;

  /// Whose count this is: server, account, company and user. A different key
  /// drops every number held for the last one.
  String? _key;
  int? _serverCount;
  DateTime? _fetchedAt;
  String? _companyId;
  int _queued = 0;
  StreamSubscription<({int creates, int removals})>? _queuedSub;
  Timer? _refetch;
  Future<void>? _inFlight;
  String? _inFlightKey;
  bool _disposed = false;

  /// The cap for the current session, or null when none applies.
  int? get limit => freePlanClientLimit(_session.value);

  /// Usage against [limit], or null when there is no cap or the count is not
  /// known yet.
  ClientQuota? get quota {
    // Read between a session change and this object's own listener (another
    // listener of the same notifier, earlier in line): the count held is the
    // last session's, so it is not this one's.
    if (_keyOf(_session.value) != _key) return null;
    final count = _serverCount;
    return clientQuotaOf(
      limit: limit,
      used: count == null ? null : count + _queued,
    );
  }

  static String? _keyOf(AuthSession? s) {
    if (s == null || freePlanClientLimit(s) == null) return null;
    return '${s.baseUrl}|${s.accountId}|${s.currentCompanyId}|${s.userId}|'
        '${s.hostedClientCount}';
  }

  void _onSession() {
    final key = _keyOf(_session.value);
    if (key == _key) return;
    _key = key;
    _serverCount = null;
    _fetchedAt = null;
    _queued = 0;
    _refetch?.cancel();
    unawaited(_queuedSub?.cancel());
    _queuedSub = null;
    _companyId = key == null ? null : _session.value!.currentCompanyId;
    if (key != null) {
      int? lastTotal;
      _queuedSub = _watchQueued(_companyId!).listen((q) {
        if (_key != key) return;
        final net = q.creates - q.removals;
        final total = q.creates + q.removals;
        final previous = lastTotal;
        lastTotal = total;
        if (_queued != net) {
          _queued = net;
          _notify();
        }
        // A create, purge or merge leaving the outbox is when the server's
        // total moves.
        if (previous != null && total < previous) {
          _refetch?.cancel();
          _refetch = Timer(refetchDelay, () => unawaited(refresh()));
        }
      }, onError: (Object e) => _log.fine('Queued changes not watched: $e'));
      // Not in this call: the session flips before the credentials do
      // (`AuthRepository` sets one, then the other, in one synchronous run),
      // so a request sent from here would carry the last company's token and
      // its answer would be filed under this company.
      scheduleMicrotask(() {
        if (!_disposed && _key == key) unawaited(refresh());
      });
    }
    // The old count is gone (and [limit] already reads the new session).
    _notify();
  }

  /// Ask the server for the total, unless one taken within [maxAge] is held.
  /// Never throws: a failure leaves what was known.
  Future<void> refresh({Duration? maxAge}) {
    final key = _key;
    if (key == null) return Future.value();
    final at = _fetchedAt;
    if (maxAge != null &&
        _serverCount != null &&
        at != null &&
        _now().difference(at) < maxAge) {
      return Future.value();
    }
    final pending = _inFlight;
    if (pending != null && _inFlightKey == key) return pending;
    _inFlightKey = key;
    late final Future<void> request;
    request = _fetch(key).whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
    return _inFlight = request;
  }

  Future<void> _fetch(String key) async {
    try {
      final total = await _fetchCount(_companyId!);
      // A company switch under the request: its answer is about another
      // company (or was asked with another company's token).
      if (_disposed || _key != key || total == null) return;
      _serverCount = total;
      _fetchedAt = _now();
      _notify();
    } catch (e) {
      _log.fine('Client count not refreshed: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeListener(_onSession);
    _refetch?.cancel();
    unawaited(_queuedSub?.cancel());
    super.dispose();
  }
}
