import 'package:flutter/widgets.dart';

import 'package:admin/data/models/value/date.dart';
import 'package:admin/l10n/localization.dart';

/// How a dashboard row says *when*, relative to today — the phrases shared by
/// the needs-attention band and the list panels, so "due in 3 days" reads the
/// same wherever an invoice appears.
///
/// Each count has a singular and a plural key: the app's localization has no
/// plural rules, and "1 days late" is the kind of slip a user reads as a bug.

/// "12 days late". [days] below one — the server's day and the device's can
/// differ by one around midnight — is simply "Past Due", never "0 days late".
String lateText(BuildContext context, int days) {
  if (days <= 0) return context.tr('past_due');
  return context.tr(
    days == 1 ? 'days_late_count_singular' : 'days_late_count_plural',
    {'count': '$days'},
  );
}

/// "due today" / "due in 3 days".
String dueText(BuildContext context, Date due, Date today) =>
    _dueInDaysText(context, due.differenceInDays(today));

String _dueInDaysText(BuildContext context, int days) {
  if (days <= 0) return context.tr('due_today_label');
  return context.tr(
    days == 1 ? 'due_in_days_count_singular' : 'due_in_days_count_plural',
    {'count': '$days'},
  );
}

/// "expires today" / "expires in 3 days".
String expiresText(BuildContext context, Date validUntil, Date today) =>
    _expiresInDaysText(context, validUntil.differenceInDays(today));

String _expiresInDaysText(BuildContext context, int days) {
  if (days <= 0) return context.tr('expires_today_label');
  return context.tr(
    days == 1
        ? 'expires_in_days_count_singular'
        : 'expires_in_days_count_plural',
    {'count': '$days'},
  );
}

/// How far ahead a deadline has to be before a table row stops mentioning it.
/// "due in 89 days" under a February date is noise; the date says it already.
const int kRowWhenWindowDays = 30;

/// What a dashboard table row's relative sub-line says.
enum RowWhenKind { dueIn, late, expiresIn, expired }

/// A row's relative sub-line, decided — [rowWhenText] words it. Kept apart from
/// the wording so the rules (near or late only, nothing on a closed document)
/// are testable without a widget tree.
@immutable
class RowWhen {
  const RowWhen(this.kind, this.days);

  final RowWhenKind kind;

  /// Days until the deadline, or past it for [RowWhenKind.late]; 0 is today.
  final int days;

  /// Drawn in the overdue tone: the deadline has already gone.
  bool get isLate => kind == RowWhenKind.late || kind == RowWhenKind.expired;

  @override
  bool operator ==(Object other) =>
      other is RowWhen && other.kind == kind && other.days == days;

  @override
  int get hashCode => Object.hash(kind, days);

  @override
  String toString() => 'RowWhen($kind, $days)';
}

/// An invoice row's sub-line: "12 days late" once [due] has passed, "due in 3
/// days" within [kRowWhenWindowDays], otherwise nothing. Null [due] — no due
/// date, or a closed invoice (draft, paid, cancelled), which the caller passes
/// as null — says nothing.
///
/// [today] is the device's local day (`Date.today()`), the day the user is
/// living in.
RowWhen? invoiceRowWhen({required Date? due, required Date today}) {
  if (due == null) return null;
  final days = due.differenceInDays(today);
  if (days < 0) return RowWhen(RowWhenKind.late, -days);
  if (days <= kRowWhenWindowDays) return RowWhen(RowWhenKind.dueIn, days);
  return null;
}

/// A quote row's sub-line: "expired" once [validUntil] has passed, "expires in
/// 3 days" within [kRowWhenWindowDays], otherwise nothing. Null for a quote
/// with no valid-until date or one no longer open (draft, approved,
/// converted…), which the caller passes as null.
RowWhen? quoteRowWhen({required Date? validUntil, required Date today}) {
  if (validUntil == null) return null;
  final days = validUntil.differenceInDays(today);
  if (days < 0) return RowWhen(RowWhenKind.expired, -days);
  if (days <= kRowWhenWindowDays) return RowWhen(RowWhenKind.expiresIn, days);
  return null;
}

/// [when] in words.
String rowWhenText(BuildContext context, RowWhen when) => switch (when.kind) {
  RowWhenKind.late => lateText(context, when.days),
  RowWhenKind.dueIn => _dueInDaysText(context, when.days),
  RowWhenKind.expiresIn => _expiresInDaysText(context, when.days),
  RowWhenKind.expired => context.tr('expired'),
};
