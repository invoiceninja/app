import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/data/models/api/activity_api_model.dart';
import 'package:admin/data/models/domain/activity.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/activity/comment_reads.dart';

final _log = Logger('CommentsInboxController');

/// The floor between two inbox-driven refetches of the company activity feed.
/// The feed is ~30 KB (`kActivityFeedRows` rows), and the dashboard and
/// `/activity` refresh the same cache row — a row any of them wrote within
/// this window is fresh enough.
const Duration kCommentsInboxMinGap = Duration(minutes: 2);

/// How many teammate comments the inbox lists — the newest in the window.
const int kCommentsInboxMaxRows = 50;

/// Teammates' comments and which of them this user has seen
/// (docs/comments-and-activity.md § A teammate's comment is new until you
/// have seen it).
///
/// Two readers. Every record's Comments card asks [recordThreshold] once per
/// visit and reports what it showed through [markRecordSeen]; the shell's
/// inbox row and the phone's menu button read [unreadCount], and the inbox
/// lists [comments] and clears them with [markFeedSeen].
///
/// **The inbox reads the company feed the dashboard card and `/activity`
/// already share** (`DashboardRepository.watchActivities`), and refetches it
/// only when the app's own delta refresh lands
/// (`RefreshScheduler.completedRefreshes` — the 5-minute tick, app resume and
/// a hosted push all end there), debounced, and never within
/// [kCommentsInboxMinGap] of the row's last write by anyone. No timer of its
/// own, no new endpoint.
///
/// **Admins only** ([enabled]). `ActivityController::index` narrows the feed
/// to the caller's own rows for anyone without `is_admin`, so for everyone
/// else it can never hold a teammate's comment, and an inbox would only ever
/// say "nothing new". Their record cards still mark new comments — the
/// per-record feed is not narrowed that way.
///
/// The owner of [DevicePrefKeys.commentReads]: it follows the store (a wipe
/// or a returning user's restore) like every other owner.
class CommentsInboxController extends ChangeNotifier {
  CommentsInboxController({
    required DevicePrefsStore prefs,
    required ValueListenable<AuthSession?> session,
    required Stream<List<DashboardActivity>?> Function(String companyId)
    watchFeed,
    required Stream<DateTime?> Function(String companyId) watchFeedFetchedAt,
    required Future<void> Function(String companyId) refreshFeed,
    Listenable? refreshCycles,
    DateTime Function()? now,
    this.debounce = const Duration(seconds: 2),
    this.minGap = kCommentsInboxMinGap,
  }) : _prefs = prefs,
       _session = session,
       _watchFeed = watchFeed,
       _watchFeedFetchedAt = watchFeedFetchedAt,
       _refreshFeed = refreshFeed,
       _refreshCycles = refreshCycles,
       _now = now ?? DateTime.now {
    prefs.addListener(_syncReads);
    session.addListener(_onSession);
    refreshCycles?.addListener(_onRefreshCycle);
    _onSession();
  }

  final DevicePrefsStore _prefs;
  final ValueListenable<AuthSession?> _session;
  final Stream<List<DashboardActivity>?> Function(String) _watchFeed;
  final Stream<DateTime?> Function(String) _watchFeedFetchedAt;
  final Future<void> Function(String) _refreshFeed;
  final Listenable? _refreshCycles;
  final DateTime Function() _now;

  /// Collapses a burst of triggers (a push, then the resume refresh) into one
  /// fetch.
  final Duration debounce;

  /// See [kCommentsInboxMinGap].
  final Duration minGap;

  String _userId = '';
  String _companyId = '';
  bool _enabled = false;
  CommentReads _reads = const CommentReads(userId: '');

  StreamSubscription<List<DashboardActivity>?>? _feedSub;
  StreamSubscription<DateTime?>? _fetchedAtSub;
  DateTime? _fetchedAt;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _disposed = false;

  List<Activity> _comments = const [];

  /// The signed-in user's hashed id, or empty while signed out.
  String get currentUserId => _userId;

  /// The active company — the one [comments] belong to.
  String get companyId => _companyId;

  /// Whether the inbox applies to this session: signed in, and an admin of
  /// the active company (see the class doc).
  bool get enabled => _enabled;

  /// Teammates' comments in the company feed's window, newest first, at most
  /// [kCommentsInboxMaxRows]. Empty when not [enabled].
  List<Activity> get comments => _comments;

  /// How many of [comments] are new ([isNewInInbox]). Zero when not
  /// [enabled] or before tracking has started for this company.
  int get unreadCount => _enabled ? _comments.where(isUnread).length : 0;

  /// Whether [a] is new in the inbox.
  bool isUnread(Activity a) {
    final reads = _reads.companies[_companyId];
    if (reads == null) return false;
    return isNewInInbox(a, currentUserId: _userId, reads: reads);
  }

  /// Comments on the record newer than this (epoch seconds) are new on its
  /// card; null while signed out. Starts tracking for [companyId] when it
  /// hasn't yet, so a first visit calls nothing new. Never notifies — the
  /// card calls it while building.
  int? recordThreshold({
    required String companyId,
    required String wireName,
    required String id,
  }) {
    if (_userId.isEmpty || companyId.isEmpty) return null;
    final reads = _readsFor(companyId);
    return reads.recordThreshold(commentRecordKey(wireName, id));
  }

  /// The record's card showed comments up to [upTo] (epoch seconds). Moves
  /// the inbox count when one of them was counted there.
  void markRecordSeen({
    required String companyId,
    required String wireName,
    required String id,
    required int upTo,
  }) {
    if (_disposed || _userId.isEmpty || companyId.isEmpty) return;
    final reads = _readsFor(companyId);
    final next = reads.withRecordSeen(commentRecordKey(wireName, id), upTo);
    if (identical(next, reads)) return;
    _store(companyId, next);
  }

  /// The inbox was opened: every teammate comment it holds is seen.
  void markFeedSeen() {
    if (_disposed || !_enabled || _comments.isEmpty) return;
    final reads = _readsFor(_companyId);
    final next = reads.withFeedSeen(activityEpochSeconds(_comments.first));
    if (identical(next, reads)) return;
    _store(_companyId, next);
  }

  /// The company's read state, started at "now" when there is none yet.
  CompanyCommentReads _readsFor(String companyId) {
    final existing = _reads.companies[companyId];
    if (existing != null) return existing;
    final started = CompanyCommentReads(
      baseline: _now().millisecondsSinceEpoch ~/ 1000,
    );
    _reads = _reads.withCompany(companyId, started);
    unawaited(_prefs.write(DevicePrefKeys.commentReads, _reads.encode()));
    return started;
  }

  void _store(String companyId, CompanyCommentReads reads) {
    _reads = _reads.withCompany(companyId, reads);
    notifyListeners();
    unawaited(_prefs.write(DevicePrefKeys.commentReads, _reads.encode()));
  }

  /// A wipe, a returning user's restore, or the first load.
  void _syncReads() {
    final next = CommentReads.decode(
      _prefs.read(DevicePrefKeys.commentReads),
      userId: _userId,
    );
    _reads = next;
    notifyListeners();
  }

  void _onSession() {
    if (_disposed) return;
    final s = _session.value;
    final userId = s?.userId ?? '';
    final companyId = s?.currentCompanyId ?? '';
    // `is_admin`, exactly the server's test (`User::isAdmin`), not "admin or
    // owner": an owner without the flag gets the narrowed feed too.
    final enabled =
        userId.isNotEmpty &&
        companyId.isNotEmpty &&
        (s?.currentCompany?.isAdmin ?? false);
    if (userId == _userId && companyId == _companyId && enabled == _enabled) {
      return;
    }
    final userChanged = userId != _userId;
    _userId = userId;
    _companyId = companyId;
    _enabled = enabled;
    if (userChanged) {
      _reads = CommentReads.decode(
        _prefs.read(DevicePrefKeys.commentReads),
        userId: userId,
      );
    }
    _resubscribe();
    notifyListeners();
  }

  void _resubscribe() {
    unawaited(_feedSub?.cancel());
    unawaited(_fetchedAtSub?.cancel());
    _feedSub = null;
    _fetchedAtSub = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _fetchedAt = null;
    _comments = const [];
    if (!_enabled) return;
    final companyId = _companyId;
    _feedSub = _watchFeed(companyId).listen(
      (rows) => _onFeed(companyId, rows),
      onError: (Object e, StackTrace st) =>
          _log.fine('comments inbox feed watch failed', e, st),
    );
    var activationCheckDue = true;
    _fetchedAtSub = _watchFeedFetchedAt(companyId).listen(
      (at) {
        _fetchedAt = at;
        // A company just became active: make sure the window is recent, once
        // its stored freshness is known, so the gap check can skip it when
        // the dashboard (or anyone) wrote it a moment ago. Run directly, not
        // through the debounce timer: a timer here outlived every test that
        // builds `Services` and never signs out.
        if (activationCheckDue) {
          activationCheckDue = false;
          unawaited(_refreshNow());
        }
      },
      onError: (Object e, StackTrace st) =>
          _log.fine('comments inbox freshness watch failed', e, st),
    );
  }

  void _onFeed(String companyId, List<DashboardActivity>? rows) {
    if (_disposed || companyId != _companyId || !_enabled) return;
    final next = <Activity>[];
    for (final row in rows ?? const <DashboardActivity>[]) {
      if (row.activityTypeId != kCommentActivityTypeId) continue;
      final Activity a;
      try {
        a = Activity.fromApi(ActivityApi.fromJson(row.raw));
      } catch (e) {
        _log.fine('comments inbox skipped an unreadable row: $e');
        continue;
      }
      if (isTeammateComment(a, currentUserId: _userId)) next.add(a);
    }
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _comments = List.unmodifiable(
      next.take(math.min(next.length, kCommentsInboxMaxRows)),
    );
    // The first feed this company shows on this device is where tracking
    // starts: nothing already in it is new.
    if (rows != null) _readsFor(companyId);
    notifyListeners();
  }

  void _onRefreshCycle() => _scheduleRefresh();

  void _scheduleRefresh() {
    if (_disposed || !_enabled) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(debounce, () {
      _refreshTimer = null;
      unawaited(_refreshNow());
    });
  }

  Future<void> _refreshNow() async {
    if (_disposed || !_enabled || _refreshing) return;
    final at = _fetchedAt;
    if (at != null && _now().difference(at) < minGap) return;
    final companyId = _companyId;
    _refreshing = true;
    try {
      await _refreshFeed(companyId);
    } catch (e, st) {
      // Offline, a company switch mid-flight, a 5xx: the next refresh cycle
      // tries again. Nothing to show — the badge keeps what it had.
      _log.fine('comments inbox refresh skipped', e, st);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _prefs.removeListener(_syncReads);
    _session.removeListener(_onSession);
    _refreshCycles?.removeListener(_onRefreshCycle);
    _refreshTimer?.cancel();
    unawaited(_feedSub?.cancel());
    unawaited(_fetchedAtSub?.cancel());
    super.dispose();
  }
}
