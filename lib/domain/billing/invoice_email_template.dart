// Which email template an invoice's Email action opens on.
//
// Two callers share [nextReminderTemplateAfter]: the dashboard's Remind
// (`nextInvoiceReminderTemplate` in `lib/domain/dashboard/needs_attention.dart`,
// over a `DashboardInvoiceRow`) and the invoice record's Email action
// ([invoiceEmailTemplateFor], over an [Invoice]). One copy, so the two can
// never open different reminders for the same invoice.

import 'package:admin/data/models/domain/billing/invitation.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/value/date.dart';

/// The server id of the invoice's first email (`BillingEmailTemplate.initial`).
const String kInvoiceInitialTemplate = 'invoice';

/// The reminder that follows [remindersSent] of the three numbered ones: the
/// first not yet sent, then the endless one.
String nextReminderTemplateAfter(int remindersSent) => switch (remindersSent) {
  <= 0 => 'reminder1',
  1 => 'reminder2',
  2 => 'reminder3',
  _ => 'reminder_endless',
};

/// How many of the three numbered reminders [invoice] has had — the count the
/// dashboard reads off the same three `reminderN_sent` columns.
int invoiceRemindersSent(Invoice invoice) => [
  invoice.reminder1Sent,
  invoice.reminder2Sent,
  invoice.reminder3Sent,
].where((d) => d != null).length;

/// The template the invoice's Email action opens the email screen on.
///
/// * A draft, or an invoice no recipient has been emailed yet (no invitation
///   carries a `sent_date` — one that was only marked sent): the initial email.
///   A reminder about an invoice the client never received reads as a
///   mistake.
/// * Past due ([Invoice.isPastDueOn], so a partial's own due date counts): the
///   next reminder not yet sent.
/// * Anything else: the initial email, which is what the screen opens on
///   without being told.
///
/// The screen's picker stays free to change it.
String invoiceEmailTemplateFor(Invoice invoice, {required Date today}) {
  if (invoice.isDraft || !invoice.invitations.any((i) => i.hasBeenSent)) {
    return kInvoiceInitialTemplate;
  }
  if (invoice.isPastDueOn(today)) {
    return nextReminderTemplateAfter(invoiceRemindersSent(invoice));
  }
  return kInvoiceInitialTemplate;
}
