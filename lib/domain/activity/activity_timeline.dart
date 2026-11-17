/// The `/activity` screen's timeline: what kind of event a row is, how the
/// loaded window is cut into periods, and which runs of rows fold together.
///
/// Pure functions over `DashboardActivity`, no Flutter import, so the bucket
/// arithmetic is unit-testable without a widget. Everything here operates on
/// the **loaded window only** — `GET /activities?reactv2` has no paging, offset
/// or date filter (BACKEND.md § F3), so there is nothing older to ask for.
library;

import 'package:admin/data/models/api/activity_api_model.dart'
    show kCommentActivityTypeId;
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/domain/activity/activity_tones.dart';

/// What an activity row *means* to the person reading the feed — the
/// category filter's vocabulary.
///
/// Derived from [kActivityTones] rather than a second id table, so a tone fix
/// re-files the row here too. Comments (type 141) are their own category
/// because the tone map leaves them neutral, and a typed note is the opposite
/// of "other". Logged calls are comments — calls stay a lens, not a category.
enum ActivityCategory { sent, viewed, paid, edited, expense, comment, other }

ActivityCategory activityCategoryFor(DashboardActivity a) {
  if (a.activityTypeId == kCommentActivityTypeId) {
    return ActivityCategory.comment;
  }
  return switch (activityToneFor(a.activityTypeId)) {
    ActivityTone.sent => ActivityCategory.sent,
    ActivityTone.viewed => ActivityCategory.viewed,
    ActivityTone.paid => ActivityCategory.paid,
    ActivityTone.draft => ActivityCategory.edited,
    ActivityTone.expense => ActivityCategory.expense,
    ActivityTone.neutral => ActivityCategory.other,
  };
}

/// The tone a category paints with — the same colour family as the row icons
/// it filters, so a chip and the rows it keeps read as one thing.
ActivityTone toneForCategory(ActivityCategory c) => switch (c) {
  ActivityCategory.sent => ActivityTone.sent,
  ActivityCategory.viewed => ActivityTone.viewed,
  ActivityCategory.paid => ActivityTone.paid,
  ActivityCategory.edited => ActivityTone.draft,
  ActivityCategory.expense => ActivityTone.expense,
  ActivityCategory.comment || ActivityCategory.other => ActivityTone.neutral,
};

/// How wide one timeline bar is.
enum TimelineBucketSize { quarterHour, halfHour, hour, day, week, month, year }

/// The bucket width for a window spanning [span].
///
/// The window is 250–2500 rows, which is a morning on a busy account and
/// years on a quiet one, so a fixed width is wrong at one end or the other.
/// The thresholds keep the bar count at or under about 63, whatever the span:
/// 15 minutes up to 12 hours (48 bars), 30 minutes up to a day (48), an hour
/// up to two days (48). Hour bars over a busy morning drew three or four
/// slabs with nothing to read between them.
TimelineBucketSize bucketSizeFor(Duration span) {
  if (span <= const Duration(hours: 12)) return TimelineBucketSize.quarterHour;
  if (span <= const Duration(hours: 24)) return TimelineBucketSize.halfHour;
  if (span <= const Duration(days: 2)) return TimelineBucketSize.hour;
  if (span <= const Duration(days: 62)) return TimelineBucketSize.day;
  if (span <= const Duration(days: 366)) return TimelineBucketSize.week;
  if (span <= const Duration(days: 365 * 5)) return TimelineBucketSize.month;
  return TimelineBucketSize.year;
}

/// One bar: the local-time half-open interval `[start, end)` and how many
/// rows fell in it.
class TimelineBucket {
  const TimelineBucket({
    required this.start,
    required this.end,
    required this.count,
  });

  final DateTime start;
  final DateTime end;
  final int count;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

/// The period a timeline draws and the bars inside it.
class ActivityTimeline {
  const ActivityTimeline({required this.size, required this.buckets});

  static const empty = ActivityTimeline(
    size: TimelineBucketSize.day,
    buckets: <TimelineBucket>[],
  );

  final TimelineBucketSize size;
  final List<TimelineBucket> buckets;

  int get maxCount => buckets.fold(0, (m, b) => b.count > m ? b.count : m);
}

/// Local start of the bucket holding [t].
///
/// [firstDayOfWeek] is `DateTime.monday` … `DateTime.sunday`. Built with the
/// `DateTime(y, m, d)` constructor, never by subtracting a `Duration`, so a
/// DST change inside the week can't shift a boundary off midnight.
DateTime bucketStart(
  DateTime t,
  TimelineBucketSize size, {
  int firstDayOfWeek = DateTime.monday,
}) {
  switch (size) {
    case TimelineBucketSize.quarterHour:
      return DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % 15);
    case TimelineBucketSize.halfHour:
      return DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % 30);
    case TimelineBucketSize.hour:
      return DateTime(t.year, t.month, t.day, t.hour);
    case TimelineBucketSize.day:
      return DateTime(t.year, t.month, t.day);
    case TimelineBucketSize.week:
      final back = (t.weekday - firstDayOfWeek + 7) % 7;
      return DateTime(t.year, t.month, t.day - back);
    case TimelineBucketSize.month:
      return DateTime(t.year, t.month);
    case TimelineBucketSize.year:
      return DateTime(t.year);
  }
}

/// The start of the bucket after the one starting at [start].
DateTime nextBucketStart(
  DateTime start,
  TimelineBucketSize size,
) => switch (size) {
  TimelineBucketSize.quarterHour => DateTime(
    start.year,
    start.month,
    start.day,
    start.hour,
    start.minute + 15,
  ),
  TimelineBucketSize.halfHour => DateTime(
    start.year,
    start.month,
    start.day,
    start.hour,
    start.minute + 30,
  ),
  TimelineBucketSize.hour => DateTime(
    start.year,
    start.month,
    start.day,
    start.hour + 1,
  ),
  TimelineBucketSize.day => DateTime(start.year, start.month, start.day + 1),
  TimelineBucketSize.week => DateTime(start.year, start.month, start.day + 7),
  TimelineBucketSize.month => DateTime(start.year, start.month + 1),
  TimelineBucketSize.year => DateTime(start.year + 1),
};

/// Local instant an activity happened at.
DateTime activityTime(DashboardActivity a) =>
    DateTime.fromMillisecondsSinceEpoch(a.createdAt * 1000);

/// Buckets [rows] into contiguous bars from the oldest row's bucket to the
/// bucket holding [now].
///
/// **Empty periods are kept** — a quiet month is the thing the timeline exists
/// to show, so a gap must be a zero bar, never a missing one. [spanOf] is
/// what picks the bucket width; pass the *whole* window there (not just the
/// rows that survived a filter) so narrowing the feed doesn't re-scale the
/// axis under the user's pointer.
ActivityTimeline bucketize(
  List<DashboardActivity> rows, {
  required DateTime now,
  required List<DashboardActivity> spanOf,
  int firstDayOfWeek = DateTime.monday,
}) {
  if (spanOf.isEmpty) return ActivityTimeline.empty;
  var oldest = activityTime(spanOf.first);
  for (final a in spanOf) {
    final t = activityTime(a);
    if (t.isBefore(oldest)) oldest = t;
  }
  // A row stamped in the future (clock skew between server and device) still
  // has to land in a bar, so the axis ends at whichever is later.
  var newest = now;
  for (final a in spanOf) {
    final t = activityTime(a);
    if (t.isAfter(newest)) newest = t;
  }
  final size = bucketSizeFor(newest.difference(oldest));

  final starts = <DateTime>[];
  var cursor = bucketStart(oldest, size, firstDayOfWeek: firstDayOfWeek);
  final last = bucketStart(newest, size, firstDayOfWeek: firstDayOfWeek);
  while (!cursor.isAfter(last)) {
    starts.add(cursor);
    cursor = nextBucketStart(cursor, size);
  }

  final counts = List<int>.filled(starts.length, 0);
  final index = <DateTime, int>{
    for (var i = 0; i < starts.length; i++) starts[i]: i,
  };
  for (final a in rows) {
    final key = bucketStart(
      activityTime(a),
      size,
      firstDayOfWeek: firstDayOfWeek,
    );
    final i = index[key];
    if (i != null) counts[i]++;
  }

  return ActivityTimeline(
    size: size,
    buckets: [
      for (var i = 0; i < starts.length; i++)
        TimelineBucket(
          start: starts[i],
          end: i + 1 < starts.length
              ? starts[i + 1]
              : nextBucketStart(starts[i], size),
          count: counts[i],
        ),
    ],
  );
}

/// The server's update activity for each record type, by the create activity
/// it follows (`App\\Models\\Activity`). A payment is left out on purpose: an
/// "entered payment" is money arriving, and an edit to it afterwards is news.
const Map<int, int> kCreateActivityOfUpdate = {
  61: 1, // client
  5: 4, // invoice
  15: 14, // credit
  19: 18, // quote
  62: 30, // vendor
  47: 34, // expense
  43: 42, // task
  49: 48, // user
  81: 80, // subscription
  101: 100, // recurring invoice
  111: 110, // recurring quote
  121: 120, // recurring expense
  131: 130, // purchase order
};

/// How long after a record's creation the same person's edits to it count as
/// part of making it.
const Duration kCreateEditWindow = Duration(minutes: 10);

/// Takes out the edits that are part of creating a record.
///
/// "Created invoice 0029" then "updated invoice 0029" seconds later, by the
/// same person, is one act to a reader: the app (and a person filling in a
/// form in two goes) saves a new record and then saves it again. On a busy
/// afternoon those pairs were half the feed.
///
/// An update is absorbed when the same actor created the same record
/// ([targetOf]) at most [window] earlier, in rows of this list. The create
/// row stays and is told how many edits followed (`absorbed`, by its id), so
/// the row can say so. Anything later than the window, by anyone else, or on
/// a record whose creation is not in the list, is kept as its own row.
({List<DashboardActivity> rows, Map<String, int> absorbed}) absorbCreateEdits(
  List<DashboardActivity> sortedDesc, {
  required String? Function(DashboardActivity) targetOf,
  Duration window = kCreateEditWindow,
}) {
  final createdAt = <String, DashboardActivity>{};
  final creates = kCreateActivityOfUpdate.values.toSet();
  for (final a in sortedDesc) {
    if (!creates.contains(a.activityTypeId)) continue;
    final target = targetOf(a);
    if (target == null) continue;
    createdAt['${a.userId}|${a.activityTypeId}|$target'] = a;
  }
  if (createdAt.isEmpty) {
    return (rows: sortedDesc, absorbed: const <String, int>{});
  }
  final rows = <DashboardActivity>[];
  final absorbed = <String, int>{};
  for (final a in sortedDesc) {
    final createType = kCreateActivityOfUpdate[a.activityTypeId];
    final target = createType == null ? null : targetOf(a);
    final create = target == null
        ? null
        : createdAt['${a.userId}|$createType|$target'];
    if (create != null) {
      final after = activityTime(a).difference(activityTime(create));
      if (!after.isNegative && after <= window) {
        absorbed[create.id] = (absorbed[create.id] ?? 0) + 1;
        continue;
      }
    }
    rows.add(a);
  }
  return (rows: rows, absorbed: absorbed);
}

/// Folds consecutive rows that say the same thing into one run.
///
/// "Test User updated task 0035" four times inside two minutes is one event
/// to a reader and four rows of scroll. A run is consecutive rows (in the
/// order given — newest first) sharing the actor, the activity type, the
/// record [targetOf] resolves and the local day. Two guards:
///
///  * **A row with no target never folds.** Without a record to agree on,
///    "same type, same user" is two different things that happen to share a
///    verb (two users created, two logins).
///  * **A comment never folds** — each one is different text.
List<List<DashboardActivity>> collapseRuns(
  List<DashboardActivity> sortedDesc, {
  required String? Function(DashboardActivity) targetOf,
}) {
  final out = <List<DashboardActivity>>[];
  List<DashboardActivity>? run;
  String? runKey;
  for (final a in sortedDesc) {
    final key = _runKey(a, targetOf(a));
    if (run != null && key != null && key == runKey) {
      run.add(a);
      continue;
    }
    run = [a];
    runKey = key;
    out.add(run);
  }
  return out;
}

String? _runKey(DashboardActivity a, String? target) {
  if (target == null) return null;
  if (a.activityTypeId == kCommentActivityTypeId) return null;
  final t = activityTime(a);
  return '${a.userId}|${a.activityTypeId}|$target|${t.year}-${t.month}-${t.day}';
}
