/// Each edit screen's `carryEdit` (docs/after-saving.md): an edit typed
/// while a new record's create was out, laid over the record the server
/// made by [carryChangedFields]. What a record's wire JSON leaves out — its
/// local state, timestamps, documents — and every list the edit did not
/// touch come from the stored record, as its repository's decode overlays
/// them. Invitations are matched by contact ([keepStoredInvitations]),
/// contacts by place when their number is unchanged ([CarriedList]), and line
/// items carry no identity: the server drops theirs.
library;

import 'package:admin/ui/core/edit/carry_edit.dart';
import 'package:admin/data/models/api/bank_transaction_api_model.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/credit_api_model.dart';
import 'package:admin/data/models/api/expense_api_model.dart';
import 'package:admin/data/models/api/expense_category_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/api/payment_api_model.dart';
import 'package:admin/data/models/api/product_api_model.dart';
import 'package:admin/data/models/api/project_api_model.dart';
import 'package:admin/data/models/api/purchase_order_api_model.dart';
import 'package:admin/data/models/api/quote_api_model.dart';
import 'package:admin/data/models/api/recurring_expense_api_model.dart';
import 'package:admin/data/models/api/recurring_invoice_api_model.dart';
import 'package:admin/data/models/api/subscription_api_model.dart';
import 'package:admin/data/models/api/task_api_model.dart';
import 'package:admin/data/models/api/vendor_api_model.dart';
import 'package:admin/data/models/domain/bank_transaction.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/credit.dart';
import 'package:admin/data/models/domain/expense.dart';
import 'package:admin/data/models/domain/expense_category.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/data/models/domain/payment_link.dart';
import 'package:admin/data/models/domain/product.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/data/models/domain/purchase_order.dart';
import 'package:admin/data/models/domain/quote.dart';
import 'package:admin/data/models/domain/recurring_expense.dart';
import 'package:admin/data/models/domain/recurring_invoice.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/data/models/domain/vendor.dart';

/// [carryChangedFields] for a Invoice.
CarriedEdit<Invoice> carryInvoiceEdit(
  Invoice sent,
  Invoice edited,
  Invoice stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => Invoice.fromApi(InvoiceApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    schedule: stored.schedule,
    lastSentDate: stored.lastSentDate,
    lineItems: changed.contains('line_items')
        ? merged.lineItems
        : stored.lineItems,
    invitations: changed.contains('invitations')
        ? keepStoredInvitations(merged.invitations, stored.invitations)
        : stored.invitations,
  ),
);

/// [carryChangedFields] for a Quote.
CarriedEdit<Quote> carryQuoteEdit(Quote sent, Quote edited, Quote stored) =>
    carryChangedFields(
      sent: sent,
      edited: edited,
      stored: stored,
      toJson: (r) => r.toApiJson(preserveTempId: true),
      fromJson: (json) => Quote.fromApi(QuoteApi.fromJson(json)),
      keepStored: (merged, stored, changed) => merged.copyWith(
        id: stored.id,
        isDirty: stored.isDirty,
        isDeleted: stored.isDeleted,
        archivedAt: stored.archivedAt,
        createdAt: stored.createdAt,
        updatedAt: stored.updatedAt,
        documents: stored.documents,
        lastSentDate: stored.lastSentDate,
        lineItems: changed.contains('line_items')
            ? merged.lineItems
            : stored.lineItems,
        invitations: changed.contains('invitations')
            ? merged.invitations
            : stored.invitations,
      ),
    );

/// [carryChangedFields] for a Credit.
CarriedEdit<Credit> carryCreditEdit(
  Credit sent,
  Credit edited,
  Credit stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => Credit.fromApi(CreditApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    lineItems: changed.contains('line_items')
        ? merged.lineItems
        : stored.lineItems,
    invitations: changed.contains('invitations')
        ? keepStoredInvitations(merged.invitations, stored.invitations)
        : stored.invitations,
  ),
);

/// [carryChangedFields] for a RecurringInvoice.
CarriedEdit<RecurringInvoice> carryRecurringInvoiceEdit(
  RecurringInvoice sent,
  RecurringInvoice edited,
  RecurringInvoice stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) =>
      RecurringInvoice.fromApi(RecurringInvoiceApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    lineItems: changed.contains('line_items')
        ? merged.lineItems
        : stored.lineItems,
    invitations: changed.contains('invitations')
        ? keepStoredInvitations(merged.invitations, stored.invitations)
        : stored.invitations,
  ),
);

/// [carryChangedFields] for a PurchaseOrder.
CarriedEdit<PurchaseOrder> carryPurchaseOrderEdit(
  PurchaseOrder sent,
  PurchaseOrder edited,
  PurchaseOrder stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => PurchaseOrder.fromApi(PurchaseOrderApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    lineItems: changed.contains('line_items')
        ? merged.lineItems
        : stored.lineItems,
    invitations: changed.contains('invitations')
        ? keepStoredInvitations(merged.invitations, stored.invitations)
        : stored.invitations,
  ),
);

/// [carryChangedFields] for a Task.
CarriedEdit<Task> carryTaskEdit(Task sent, Task edited, Task stored) =>
    carryChangedFields(
      sent: sent,
      edited: edited,
      stored: stored,
      toJson: (r) => r.toApiJson(preserveTempId: true),
      fromJson: (json) => Task.fromApi(TaskApi.fromJson(json)),
      keepStored: (merged, stored, changed) => merged.copyWith(
        id: stored.id,
        isDirty: stored.isDirty,
        isDeleted: stored.isDeleted,
        archivedAt: stored.archivedAt,
        createdAt: stored.createdAt,
        updatedAt: stored.updatedAt,
        documents: stored.documents,
      ),
    );

/// [carryChangedFields] for a Expense.
CarriedEdit<Expense> carryExpenseEdit(
  Expense sent,
  Expense edited,
  Expense stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => Expense.fromApi(ExpenseApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
  ),
);

/// [carryChangedFields] for a RecurringExpense.
CarriedEdit<RecurringExpense> carryRecurringExpenseEdit(
  RecurringExpense sent,
  RecurringExpense edited,
  RecurringExpense stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) =>
      RecurringExpense.fromApi(RecurringExpenseApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
  ),
);

/// [carryChangedFields] for a Project.
CarriedEdit<Project> carryProjectEdit(
  Project sent,
  Project edited,
  Project stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => Project.fromApi(ProjectApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    currentHours: stored.currentHours,
    documents: stored.documents,
  ),
);

/// [carryChangedFields] for a Client.
CarriedEdit<Client> carryClientEdit(
  Client sent,
  Client edited,
  Client stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  lists: const {'contacts': CarriedList.byPosition},
  fromJson: (json) => Client.fromApi(ClientApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    locations: stored.locations,
    contacts: changed.contains('contacts') ? merged.contacts : stored.contacts,
  ),
);

/// [carryChangedFields] for a Vendor.
CarriedEdit<Vendor> carryVendorEdit(
  Vendor sent,
  Vendor edited,
  Vendor stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  lists: const {'contacts': CarriedList.byPosition},
  fromJson: (json) => Vendor.fromApi(VendorApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    contacts: changed.contains('contacts') ? merged.contacts : stored.contacts,
  ),
);

/// [carryChangedFields] for a Payment.
CarriedEdit<Payment> carryPaymentEdit(
  Payment sent,
  Payment edited,
  Payment stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => Payment.fromApi(PaymentApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
    paymentables: stored.paymentables,
    invoices: stored.invoices,
    credits: stored.credits,
  ),
);

/// [carryChangedFields] for a Product.
CarriedEdit<Product> carryProductEdit(
  Product sent,
  Product edited,
  Product stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => Product.fromApi(ProductApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
    documents: stored.documents,
  ),
);

/// [carryChangedFields] for a BankTransaction.
CarriedEdit<BankTransaction> carryBankTransactionEdit(
  BankTransaction sent,
  BankTransaction edited,
  BankTransaction stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) =>
      BankTransaction.fromApi(BankTransactionApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
    createdAt: stored.createdAt,
    updatedAt: stored.updatedAt,
  ),
);

/// [carryChangedFields] for a ExpenseCategory.
CarriedEdit<ExpenseCategory> carryExpenseCategoryEdit(
  ExpenseCategory sent,
  ExpenseCategory edited,
  ExpenseCategory stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) =>
      ExpenseCategory.fromApi(ExpenseCategoryApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
  ),
);

/// [carryChangedFields] for a PaymentLink.
CarriedEdit<PaymentLink> carryPaymentLinkEdit(
  PaymentLink sent,
  PaymentLink edited,
  PaymentLink stored,
) => carryChangedFields(
  sent: sent,
  edited: edited,
  stored: stored,
  toJson: (r) => r.toApiJson(preserveTempId: true),
  fromJson: (json) => PaymentLink.fromApi(SubscriptionApi.fromJson(json)),
  keepStored: (merged, stored, changed) => merged.copyWith(
    id: stored.id,
    isDirty: stored.isDirty,
    isDeleted: stored.isDeleted,
    archivedAt: stored.archivedAt,
  ),
);
