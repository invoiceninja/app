import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/domain/billing/invitation.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/billing/invoice_email_template.dart';

final _today = Date(2026, 5, 18);
const _emailed = [Invitation(key: 'k', sentDate: '2026-04-01 12:00:00')];
const _notEmailed = [Invitation(key: 'k')];

// status_id wire ids: 1 draft, 2 sent, 3 partial, 4 paid.
Invoice _inv(
  String statusId, {
  List<Invitation> invitations = _emailed,
  Date? due,
  Date? partialDue,
  String balance = '100',
  int reminders = 0,
}) => Invoice.fromApi(InvoiceApi(id: 'i1', statusId: statusId)).copyWith(
  balance: Decimal.parse(balance),
  amount: Decimal.fromInt(100),
  dueDate: due,
  partialDueDate: partialDue,
  invitations: invitations,
  reminder1Sent: reminders >= 1 ? Date(2026, 5, 1) : null,
  reminder2Sent: reminders >= 2 ? Date(2026, 5, 8) : null,
  reminder3Sent: reminders >= 3 ? Date(2026, 5, 15) : null,
);

void main() {
  final late = Date(2026, 5, 1);
  final ahead = Date(2026, 6, 1);

  test('the reminder after N sent: the first unsent, then the endless one', () {
    expect(nextReminderTemplateAfter(0), 'reminder1');
    expect(nextReminderTemplateAfter(1), 'reminder2');
    expect(nextReminderTemplateAfter(2), 'reminder3');
    expect(nextReminderTemplateAfter(3), 'reminder_endless');
  });

  group('invoiceEmailTemplateFor', () {
    String pick(Invoice i) => invoiceEmailTemplateFor(i, today: _today);

    test('a draft opens on the initial email, even with a past due date', () {
      expect(pick(_inv('1', due: late, invitations: _notEmailed)), 'invoice');
    });

    test('a sent invoice no one was emailed opens on the initial email', () {
      // Marked sent, never emailed: a reminder would be its first message.
      expect(pick(_inv('2', due: late, invitations: _notEmailed)), 'invoice');
    });

    test('a past-due invoice opens on the next unsent reminder', () {
      expect(pick(_inv('2', due: late)), 'reminder1');
      expect(pick(_inv('2', due: late, reminders: 1)), 'reminder2');
      expect(pick(_inv('3', due: late, reminders: 2)), 'reminder3');
      expect(pick(_inv('2', due: late, reminders: 3)), 'reminder_endless');
    });

    test('a partial due date past is past due, as the status pill says', () {
      expect(pick(_inv('2', due: ahead, partialDue: late)), 'reminder1');
    });

    test('anything else keeps the default', () {
      expect(pick(_inv('2', due: ahead)), 'invoice');
      expect(pick(_inv('4', due: late, balance: '0')), 'invoice');
    });
  });
}
