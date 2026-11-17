/// Which kind of record an activity row is about — the `/activity` screen's
/// Record type filter.
///
/// `GET /activities` takes no filters (BACKEND.md § F3), so this is decided on
/// the device: first by the `activity_type_id` (the server's `Activity`
/// constants each name one record type), and for a type that does not — a
/// comment (141) is written on whatever record it is about — by the most
/// specific record the row references, in `activityDeepLinkTarget`'s order.
///
/// A pure leaf with no Flutter import, beside `activity_timeline.dart`.
library;

import 'package:admin/data/models/api/activity_api_model.dart'
    show kCommentActivityTypeId;
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';

/// The record types the filter offers, in the order it lists them.
enum ActivityRecordType {
  client('client'),
  invoice('invoice'),
  quote('quote'),
  credit('credit'),
  payment('payment'),
  recurringInvoice('recurring_invoice'),
  recurringQuote('recurring_quote'),
  purchaseOrder('purchase_order'),
  expense('expense'),
  recurringExpense('recurring_expense'),
  vendor('vendor'),
  task('task'),
  paymentLink('payment_link'),
  user('user');

  const ActivityRecordType(this.labelKey);

  /// Translation key of the option's label.
  final String labelKey;
}

/// The record type each `activity_type_id` is about (`App\Models\Activity`).
/// A type missing here — a comment, an account deletion, a QuickBooks push,
/// a custom document signed — falls back to the row's references.
const Map<int, ActivityRecordType> kActivityRecordTypes = {
  // Clients.
  1: ActivityRecordType.client,
  2: ActivityRecordType.client,
  3: ActivityRecordType.client,
  26: ActivityRecordType.client,
  61: ActivityRecordType.client,
  140: ActivityRecordType.client, // statement emailed
  151: ActivityRecordType.client, // merged
  153: ActivityRecordType.client, // purged
  168: ActivityRecordType.client, // payment method updated
  169: ActivityRecordType.client, // payment method removed
  // Invoices.
  4: ActivityRecordType.invoice,
  5: ActivityRecordType.invoice,
  6: ActivityRecordType.invoice,
  7: ActivityRecordType.invoice,
  8: ActivityRecordType.invoice,
  9: ActivityRecordType.invoice,
  25: ActivityRecordType.invoice,
  53: ActivityRecordType.invoice,
  54: ActivityRecordType.invoice,
  57: ActivityRecordType.invoice,
  58: ActivityRecordType.invoice,
  59: ActivityRecordType.invoice,
  63: ActivityRecordType.invoice,
  64: ActivityRecordType.invoice,
  65: ActivityRecordType.invoice,
  66: ActivityRecordType.invoice,
  143: ActivityRecordType.invoice, // auto-bill succeeded
  144: ActivityRecordType.invoice, // auto-bill failed
  145: ActivityRecordType.invoice, // e-invoice sent
  146: ActivityRecordType.invoice,
  147: ActivityRecordType.invoice,
  154: ActivityRecordType.invoice, // Verifactu
  155: ActivityRecordType.invoice,
  156: ActivityRecordType.invoice,
  157: ActivityRecordType.invoice,
  159: ActivityRecordType.invoice, // document signed
  167: ActivityRecordType.invoice, // e-invoice status
  // Payments.
  10: ActivityRecordType.payment,
  11: ActivityRecordType.payment,
  12: ActivityRecordType.payment,
  13: ActivityRecordType.payment,
  27: ActivityRecordType.payment,
  39: ActivityRecordType.payment,
  40: ActivityRecordType.payment,
  41: ActivityRecordType.payment,
  138: ActivityRecordType.payment, // receipt emailed
  // Credits.
  14: ActivityRecordType.credit,
  15: ActivityRecordType.credit,
  16: ActivityRecordType.credit,
  17: ActivityRecordType.credit,
  28: ActivityRecordType.credit,
  60: ActivityRecordType.credit,
  149: ActivityRecordType.credit,
  161: ActivityRecordType.credit,
  // Quotes.
  18: ActivityRecordType.quote,
  19: ActivityRecordType.quote,
  20: ActivityRecordType.quote,
  21: ActivityRecordType.quote,
  22: ActivityRecordType.quote,
  23: ActivityRecordType.quote,
  24: ActivityRecordType.quote,
  29: ActivityRecordType.quote,
  142: ActivityRecordType.quote, // reminder
  158: ActivityRecordType.quote, // rejected
  160: ActivityRecordType.quote,
  170: ActivityRecordType.quote, // cancelled
  // Vendors.
  30: ActivityRecordType.vendor,
  31: ActivityRecordType.vendor,
  32: ActivityRecordType.vendor,
  33: ActivityRecordType.vendor,
  62: ActivityRecordType.vendor,
  152: ActivityRecordType.vendor, // merged
  // Expenses.
  34: ActivityRecordType.expense,
  35: ActivityRecordType.expense,
  36: ActivityRecordType.expense,
  37: ActivityRecordType.expense,
  47: ActivityRecordType.expense,
  139: ActivityRecordType.expense, // vendor notified (`VendorExpenseNotify`)
  148: ActivityRecordType.expense, // e-expense created
  // Tasks.
  42: ActivityRecordType.task,
  43: ActivityRecordType.task,
  44: ActivityRecordType.task,
  45: ActivityRecordType.task,
  46: ActivityRecordType.task,
  // Users.
  48: ActivityRecordType.user,
  49: ActivityRecordType.user,
  50: ActivityRecordType.user,
  51: ActivityRecordType.user,
  52: ActivityRecordType.user,
  166: ActivityRecordType.user, // purged
  // Payment links (the server's subscriptions).
  80: ActivityRecordType.paymentLink,
  81: ActivityRecordType.paymentLink,
  82: ActivityRecordType.paymentLink,
  83: ActivityRecordType.paymentLink,
  84: ActivityRecordType.paymentLink,
  // Recurring documents.
  100: ActivityRecordType.recurringInvoice,
  101: ActivityRecordType.recurringInvoice,
  102: ActivityRecordType.recurringInvoice,
  103: ActivityRecordType.recurringInvoice,
  104: ActivityRecordType.recurringInvoice,
  110: ActivityRecordType.recurringQuote,
  111: ActivityRecordType.recurringQuote,
  112: ActivityRecordType.recurringQuote,
  113: ActivityRecordType.recurringQuote,
  114: ActivityRecordType.recurringQuote,
  120: ActivityRecordType.recurringExpense,
  121: ActivityRecordType.recurringExpense,
  122: ActivityRecordType.recurringExpense,
  123: ActivityRecordType.recurringExpense,
  124: ActivityRecordType.recurringExpense,
  // Purchase orders.
  130: ActivityRecordType.purchaseOrder,
  131: ActivityRecordType.purchaseOrder,
  132: ActivityRecordType.purchaseOrder,
  133: ActivityRecordType.purchaseOrder,
  134: ActivityRecordType.purchaseOrder,
  135: ActivityRecordType.purchaseOrder,
  136: ActivityRecordType.purchaseOrder,
  137: ActivityRecordType.purchaseOrder,
  162: ActivityRecordType.purchaseOrder,
};

/// The record [a] is about, or null when neither its type nor its references
/// name one (an account deletion).
ActivityRecordType? activityRecordTypeFor(DashboardActivity a) {
  // A comment's type says nothing about its record; every other mapped type
  // does, even when the row's references are incomplete (a restored quote
  // carries no `quote_id`, BACKEND.md § F3g).
  if (a.activityTypeId != kCommentActivityTypeId) {
    final byType = kActivityRecordTypes[a.activityTypeId];
    if (byType != null) return byType;
  }
  if (a.invoiceId != null) return ActivityRecordType.invoice;
  if (a.quoteId != null) return ActivityRecordType.quote;
  if (a.creditId != null) return ActivityRecordType.credit;
  if (a.paymentId != null) return ActivityRecordType.payment;
  if (a.recurringInvoiceId != null) return ActivityRecordType.recurringInvoice;
  if (a.expenseId != null) return ActivityRecordType.expense;
  if (a.recurringExpenseId != null) return ActivityRecordType.recurringExpense;
  if (a.taskId != null) return ActivityRecordType.task;
  if (a.purchaseOrderId != null) return ActivityRecordType.purchaseOrder;
  if (a.subscriptionId != null) return ActivityRecordType.paymentLink;
  if (a.vendorId != null) return ActivityRecordType.vendor;
  if (a.clientId != null) return ActivityRecordType.client;
  return null;
}
