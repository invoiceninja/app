import 'dart:convert';
import 'dart:math' as math;

import 'package:admin/data/models/domain/activity.dart';
import 'package:admin/domain/activity/activity_refs.dart';

/// Which comments a user has already seen — the read state behind the
/// Comments card's "N new" tag and the shell's comments inbox
/// (docs/comments-and-activity.md § A teammate's comment is new until you
/// have seen it).
///
/// Pure: no Flutter, no store. `CommentsInboxController` owns the stored copy
/// (`DevicePrefKeys.commentReads`) and calls into here.

/// How many per-record stamps one company keeps. The oldest stamps go first;
/// a record that falls off simply goes back to the company [baseline], so the
/// worst a trim can do is call a comment new that was already seen months ago
/// — and only one newer than the baseline at that.
const int kCommentReadsMaxRecords = 500;

/// The key a record's stamp is stored under: the singular wire name the
/// activity feeds use (`invoice`, `purchase_order`, …) and the record's hashed
/// id. The Comments card passes `EntityActivityViewModel.entityWireName`; a
/// comment's refs carry the same tokens.
String commentRecordKey(String wireName, String id) => '$wireName:$id';

/// An activity's `created_at`, in the epoch seconds the server stamps.
int activityEpochSeconds(Activity a) =>
    a.createdAt.millisecondsSinceEpoch ~/ 1000;

/// One company's read state for one user.
class CompanyCommentReads {
  const CompanyCommentReads({
    required this.baseline,
    this.feedSeen = 0,
    this.records = const <String, int>{},
  });

  /// When tracking started for this user and company (epoch seconds). Nothing
  /// older is ever new — without it, the first launch after this shipped
  /// would call every comment a teammate ever wrote "new".
  final int baseline;

  /// The newest teammate comment the inbox showed when it was last opened.
  final int feedSeen;

  /// [commentRecordKey] → the newest comment the record's Comments card
  /// showed when it was last on screen.
  final Map<String, int> records;

  /// Comments on the record at [key] newer than this are new on its card.
  int recordThreshold(String key) => math.max(baseline, records[key] ?? 0);

  CompanyCommentReads withRecordSeen(String key, int at) {
    if (at <= (records[key] ?? 0)) return this;
    final next = {...records, key: at};
    if (next.length > kCommentReadsMaxRecords) {
      final byAge = next.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in byAge.take(next.length - kCommentReadsMaxRecords)) {
        next.remove(e.key);
      }
    }
    return CompanyCommentReads(
      baseline: baseline,
      feedSeen: feedSeen,
      records: next,
    );
  }

  CompanyCommentReads withFeedSeen(int at) => at <= feedSeen
      ? this
      : CompanyCommentReads(baseline: baseline, feedSeen: at, records: records);

  Map<String, Object> toJson() => {
    'base': baseline,
    if (feedSeen > 0) 'feed': feedSeen,
    if (records.isNotEmpty) 'records': records,
  };

  static CompanyCommentReads? fromJson(Object? json) {
    if (json is! Map) return null;
    final base = json['base'];
    if (base is! int) return null;
    final feed = json['feed'];
    final raw = json['records'];
    return CompanyCommentReads(
      baseline: base,
      feedSeen: feed is int ? feed : 0,
      records: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is int)
              e.key as String: e.value as int,
      },
    );
  }
}

/// Everything stored, for one user. The stored blob names its user, so a
/// copy written for someone else reads as empty even where a sign-out did not
/// wipe it (an end that keeps local data, then another identity).
class CommentReads {
  const CommentReads({
    required this.userId,
    this.companies = const <String, CompanyCommentReads>{},
  });

  final String userId;
  final Map<String, CompanyCommentReads> companies;

  /// The stored blob for [userId]; empty when there is none, it won't
  /// decode, or it belongs to another user.
  static CommentReads decode(String? raw, {required String userId}) {
    final empty = CommentReads(userId: userId);
    if (raw == null || raw.isEmpty || userId.isEmpty) return empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['user'] != userId) return empty;
      final companies = json['companies'];
      return CommentReads(
        userId: userId,
        companies: {
          if (companies is Map)
            for (final e in companies.entries)
              if (e.key is String)
                if (CompanyCommentReads.fromJson(e.value) case final c?)
                  e.key as String: c,
        },
      );
    } catch (_) {
      return empty;
    }
  }

  String encode() => jsonEncode({
    'user': userId,
    'companies': {for (final e in companies.entries) e.key: e.value.toJson()},
  });

  CommentReads withCompany(String companyId, CompanyCommentReads reads) =>
      CommentReads(userId: userId, companies: {...companies, companyId: reads});
}

/// A comment someone other than [currentUserId] wrote. Not a teammate's when
/// the author can't be told — a row with no `user` id is never counted, since
/// it could be the user's own.
bool isTeammateComment(Activity a, {required String currentUserId}) {
  if (!a.isComment || currentUserId.isEmpty) return false;
  final author = a.refs['user']?.id ?? '';
  return author.isNotEmpty && author != currentUserId;
}

/// New on a record's Comments card: a teammate's comment newer than
/// [threshold] (`CompanyCommentReads.recordThreshold`).
bool isNewOnRecord(
  Activity a, {
  required String currentUserId,
  required int threshold,
}) =>
    isTeammateComment(a, currentUserId: currentUserId) &&
    activityEpochSeconds(a) > threshold;

/// The tokens a comment's record keys are read from, most specific first:
/// the documents in [kActivityDocumentTokens] order, then the parties.
const List<String> _kRecordTokens = [
  ...kActivityDocumentTokens,
  'vendor',
  'client',
];

/// Every record a comment is shown on, as [commentRecordKey]s.
///
/// `ActivityController::note()` copies the parent's `client_id` (and
/// `vendor_id`, `invoice_id`, …) onto the row, so a note on an invoice is on
/// the invoice's Comments card *and* its client's. Seeing it on either card
/// counts. On a purchase order or recurring expense an `expense` ref is the
/// old id collision (§ A client's comment feed is mixed), never a relation,
/// so it is left out.
Iterable<String> commentRecordKeys(Activity a) sync* {
  final aliased = kExpenseIdAliasHosts.any(a.refs.containsKey);
  for (final token in _kRecordTokens) {
    if (aliased && token == 'expense') continue;
    final id = a.refs[token]?.id ?? '';
    if (id.isNotEmpty) yield commentRecordKey(token, id);
  }
}

/// New in the inbox: a teammate's comment newer than the last time the inbox
/// was opened **and** than the last time any card it is shown on was seen.
bool isNewInInbox(
  Activity a, {
  required String currentUserId,
  required CompanyCommentReads reads,
}) {
  if (!isTeammateComment(a, currentUserId: currentUserId)) return false;
  var threshold = math.max(reads.baseline, reads.feedSeen);
  for (final key in commentRecordKeys(a)) {
    threshold = math.max(threshold, reads.records[key] ?? 0);
  }
  return activityEpochSeconds(a) > threshold;
}

/// The record a comment was written on, for naming and opening it from the
/// inbox: the most specific linkable ref — a document before its vendor or
/// client — with the same `expense` alias skip as [commentRecordKeys].
///
/// Null when the row names nothing openable. A project's note is one: the
/// feed ships no `project` ref (`Activity::harvestNoteEntities` has no
/// `:project`), so it resolves to the project's client when it has one.
({String token, ActivityRef ref})? commentSourceRecord(Activity a) {
  final aliased = kExpenseIdAliasHosts.any(a.refs.containsKey);
  for (final token in _kRecordTokens) {
    if (aliased && token == 'expense') continue;
    final ref = a.refs[token];
    if (ref != null && ref.isLink) return (token: token, ref: ref);
  }
  return null;
}
