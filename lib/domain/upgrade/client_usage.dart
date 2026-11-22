import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/client_limit.dart';

final _log = Logger('ClientUsage');

/// How long after a queued client create leaves the outbox the server is
/// asked again — long enough that a burst of saves is one request.
const Duration kClientUsageRefetchDelay = Duration(milliseconds: 1500);

/// How old a count may be before a surface that opens asks again.
const Duration kClientUsageMaxAge = Duration(minutes: 1);

/// How many clients a hosted Free plan account holds, against its cap — what
/// the clients list's usage line, the Plan screen and the New-client gate all
/// read (docs/free-plan-limits.md).
///
/// **The count is the server's total**, never a Drift row count: lists page in
/// fifty at a time and a fresh device holds a handful, so a local count
/// under-reports exactly when it matters. Creates still in the outbox are
/// added on top, so an offline sixth client is caught before it becomes a
/// dead row.
///
/// Asks nothing for a session the cap does not apply to (self-hosted, a paid
/// plan, a trial). Unknown — offline before the first answer, a failed
/// request — leaves [quota] null, and a null quota never blocks.
class ClientUsage extends ChangeNotifier {
  ClientUsage({
    required ValueListenable<AuthSession?> session,
    required Future<int?> Function() fetchCount,
    required Stream<int> Function(String companyId) watchQueuedCreates,
    this.refetchDelay = kClientUsageRefetchDelay,
    DateTime Function()? now,
  }) : _session = session,
       _fetchCount = fetchCount,
       _watchQueuedCreates = watchQueuedCreates,
       _now = now ?? DateTime.now {
    _session.addListener(_onSession);
    _onSession();
  }

  final ValueListenable<AuthSession?> _session;
  final Future<int?> Function() _fetchCount;
  final Stream<int> Function(String companyId) _watchQueuedCreates;
  final Duration refetchDelay;
  final DateTime Function() _now;

  /// Whose count this is: server, account, company and user. A different key
  /// drops every number held for the last one.
  String? _key;
  int? _serverCount;
  DateTime? _fetchedAt;
  int _queued = 0;
  StreamSubscription<int>? _queuedSub;
  Timer? _refetch;
  Future<void>? _inFlight;
  String? _inFlightKey;
  bool _disposed = false;

  /// The cap for the current session, or null when none applies.
  int? get limit => freePlanClientLimit(_session.value);

  /// Usage against [limit], or null when there is no cap or the count is not
  /// known yet.
  ClientQuota? get quota {
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
    if (key != null) {
      final companyId = _session.value!.currentCompanyId;
      int? last;
      _queuedSub = _watchQueuedCreates(companyId).listen((n) {
        if (_key != key) return;
        final previous = last;
        last = n;
        if (_queued != n) {
          _queued = n;
          _notify();
        }
        // A create leaving the outbox is when the server's total moves.
        if (previous != null && n < previous) {
          _refetch?.cancel();
          _refetch = Timer(refetchDelay, () => unawaited(refresh()));
        }
      }, onError: (Object e) => _log.fine('Queued creates not watched: $e'));
      unawaited(refresh());
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
      final total = await _fetchCount();
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
