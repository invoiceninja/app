import 'package:material_ui/material_ui.dart';

import 'package:admin/app/router.dart';
import 'package:admin/data/db/dao/invoice_dao.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/columns/column_cells.dart';
import 'package:admin/domain/columns/column_factories.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/ui/core/widgets/vendor_name_label.dart';
import 'package:admin/domain/columns/custom_field_columns.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/client_name_label.dart';
import 'package:admin/ui/core/widgets/design_name_label.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/core/widgets/party_money_cell.dart';
import 'package:admin/ui/features/billing_shared/peppol_status_icon.dart';
import 'package:admin/ui/features/dashboard/helpers/when_text.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_status_pill.dart';
import 'package:admin/ui/features/projects/widgets/project_name_label.dart';
import 'package:admin/utils/notes_html.dart';

typedef InvoiceColumn = ColumnDefinition<Invoice>;

/// Default visible columns for the Invoice list. Mirrors the React admin
/// client's default column registry: status, number, client, amount,
/// balance, date, due_date.
const List<String> kDefaultInvoiceColumns = <String>[
  InvoiceFieldIds.status,
  InvoiceFieldIds.number,
  InvoiceFieldIds.clientId,
  InvoiceFieldIds.amount,
  InvoiceFieldIds.balance,
  InvoiceFieldIds.date,
  InvoiceFieldIds.dueDate,
];

final List<InvoiceColumn> kAllInvoiceColumns = <InvoiceColumn>[
  // Display-only column. `calculatedStatusId` is a domain getter, not a
  // denormalized Drift column — adding it to the list screen's
  // `sortOptions` would make `InvoiceDao._sortExpression` throw.
  InvoiceColumn(
    id: InvoiceFieldIds.status,
    labelKey: 'status',
    width: 110,
    cellBuilder: (i, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: InvoiceStatusPill(
            statusId: i.calculatedStatusId,
            hasBounce: i.hasBouncedInvitation,
          ),
        ),
        PeppolStatusIcon(
          clientId: i.clientId,
          backup: i.backup,
          isDraft: i.isDraft,
          isDeleted: i.isDeleted,
          isArchived: i.archivedAt != null,
          padding: const EdgeInsetsDirectional.only(start: 6),
        ),
      ],
    ),
    valueBuilder: (i) => i.calculatedStatusId,
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.number,
    labelKey: 'number',
    width: 130,
    cellBuilder: (i, ctx) => cellLink(
      ctx,
      i.number,
      bold: true,
      onTap: () => goEntityFullDetail(ctx, '/invoices', i.id),
    ),
    valueBuilder: (i) => cellNonZeroString(i.number),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.clientId,
    labelKey: 'client',
    width: 200,
    cellBuilder: (i, _) => i.clientId.isEmpty
        ? cellEmpty()
        : ClientNameLabel(clientId: i.clientId, link: true),
    valueBuilder: (i) => cellNonZeroString(i.clientId),
    copiesCellName: true,
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.date,
    labelKey: 'invoice_date',
    width: 120,
    cellBuilder: (i, ctx) =>
        i.date == null ? cellEmpty() : cellDate(i.date!.toDateTime(), ctx),
    valueBuilder: (i) => i.date?.toIso(),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.dueDate,
    labelKey: 'due_date',
    width: 120,
    cellBuilder: invoiceDueDateCell,
    valueBuilder: (i) => i.dueDate?.toIso(),
  ),
  // Server-stamped when the document is emailed or marked sent.
  InvoiceColumn(
    id: InvoiceFieldIds.lastSentDate,
    labelKey: 'last_sent_date',
    width: 130,
    cellBuilder: (i, ctx) => i.lastSentDate == null
        ? cellEmpty()
        : cellDate(i.lastSentDate!.toDateTime(), ctx),
    valueBuilder: (i) => i.lastSentDate?.toIso(),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.amount,
    labelKey: 'amount',
    width: 130,
    align: ColumnAlign.end,
    cellBuilder: (i, context) =>
        cellPartyMoney(i.amount, context, clientId: i.clientId),
    valueBuilder: (i) => cellMoneyValue(i.amount),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.balance,
    labelKey: 'balance',
    width: 130,
    align: ColumnAlign.end,
    cellBuilder: (i, context) =>
        cellPartyMoney(i.balance, context, clientId: i.clientId),
    valueBuilder: (i) => cellMoneyValue(i.balance),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.paidToDate,
    labelKey: 'paid_to_date',
    width: 130,
    align: ColumnAlign.end,
    cellBuilder: (i, context) =>
        cellPartyMoney(i.paidToDate, context, clientId: i.clientId),
    valueBuilder: (i) => cellMoneyValue(i.paidToDate),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.partial,
    labelKey: 'partial',
    width: 120,
    align: ColumnAlign.end,
    cellBuilder: (i, context) =>
        cellPartyMoney(i.partial, context, clientId: i.clientId),
    valueBuilder: (i) => cellMoneyValue(i.partial),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.partialDueDate,
    labelKey: 'partial_due_date',
    width: 130,
    cellBuilder: (i, ctx) => _lateDateCell(i, i.partialDueDate, ctx),
    valueBuilder: (i) => i.partialDueDate?.toIso(),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.poNumber,
    labelKey: 'po_number',
    width: 130,
    cellBuilder: (i, _) =>
        i.poNumber.isEmpty ? cellEmpty() : cellText(i.poNumber),
    valueBuilder: (i) => cellNonZeroString(i.poNumber),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.designId,
    labelKey: 'design',
    width: 130,
    cellBuilder: (i, _) => i.designId.isEmpty
        ? cellEmpty()
        : DesignNameLabel(designId: i.designId),
    valueBuilder: (i) => cellNonZeroString(i.designId),
    copiesCellName: true,
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.projectId,
    labelKey: 'project',
    width: 160,
    cellBuilder: (i, _) => i.projectId.isEmpty
        ? cellEmpty()
        : ProjectNameLabel(projectId: i.projectId, link: true),
    valueBuilder: (i) => cellNonZeroString(i.projectId),
    copiesCellName: true,
  ),
  // Link to the recurring invoice that generated this invoice. Display-only
  // (not a Drift column / sort option) — renders a "View" link, matching the
  // React admin client.
  InvoiceColumn(
    id: InvoiceFieldIds.recurringId,
    labelKey: 'recurring_invoice',
    sortable: false,
    width: 130,
    cellBuilder: (i, ctx) => i.recurringId.isEmpty
        ? cellEmpty()
        : cellLink(
            ctx,
            ctx.tr('view'),
            onTap: () =>
                goEntityFullDetail(ctx, '/recurring_invoices', i.recurringId),
          ),
    valueBuilder: (i) => cellNonZeroString(i.recurringId),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.assignedUserId,
    labelKey: 'assigned_user',
    width: 160,
    cellBuilder: (i, _) => i.assignedUserId.isEmpty
        ? cellEmpty()
        : UserNameLabel(userId: i.assignedUserId),
    valueBuilder: (i) => cellNonZeroString(i.assignedUserId),
    copiesCellName: true,
  ),
  // Display-only — `public_notes` lives only in the payload JSON; adding it
  // to the screen's `sortOptions` would make `InvoiceDao._sortExpression`
  // throw. Lift into `invoices_table.dart` first if sorting is needed.
  InvoiceColumn(
    id: InvoiceFieldIds.publicNotes,
    labelKey: 'public_notes',
    sortable: false,
    width: 240,
    cellBuilder: (i, _) =>
        i.publicNotes.isEmpty ? cellEmpty() : cellNotes(i.publicNotes),
    valueBuilder: (i) => cellNonZeroString(plainTextFromHtml(i.publicNotes)),
  ),
  InvoiceColumn(
    id: InvoiceFieldIds.privateNotes,
    labelKey: 'private_notes',
    sortable: false,
    width: 240,
    cellBuilder: (i, _) =>
        i.privateNotes.isEmpty ? cellEmpty() : cellNotes(i.privateNotes),
    valueBuilder: (i) => cellNonZeroString(plainTextFromHtml(i.privateNotes)),
  ),
  colUpdatedAt<Invoice>(InvoiceFieldIds.updatedAt, (i) => i.updatedAt),
  // Billing docs can carry a vendor as well as a client. The id, the Drift
  // column and the DAO sort case all already existed — only the column was
  // missing. React and the legacy app both offer it.
  InvoiceColumn(
    id: InvoiceFieldIds.vendorId,
    labelKey: 'vendor',
    width: 160,
    cellBuilder: (i, _) => i.vendorId.isEmpty
        ? cellEmpty()
        : VendorNameLabel(vendorId: i.vendorId, link: true),
    valueBuilder: (i) => cellNonZeroString(i.vendorId),
    copiesCellName: true,
  ),
  // The company's own labels ('Region'), type-aware values and the
  // hiding of unconfigured slots are applied by
  // `decorateCustomFieldColumns` — see `custom_field_columns.dart`.
  ...customFieldColumns<Invoice>(
    prefix: 'invoice',
    ids: const [
      InvoiceFieldIds.customValue1,
      InvoiceFieldIds.customValue2,
      InvoiceFieldIds.customValue3,
      InvoiceFieldIds.customValue4,
    ],
    values: [
      (i) => i.customValue1,
      (i) => i.customValue2,
      (i) => i.customValue3,
      (i) => i.customValue4,
    ],
  ),
  // ── Standard record metadata ──────────────────────────────────────────
  // Shared across every entity list; see `column_factories.dart`. Created /
  // archived / deleted are real Drift columns and sort; state, documents and
  // the two user columns are derived or payload-only and don't.
  colCreatedAt<Invoice>(InvoiceFieldIds.createdAt, (i) => i.createdAt),
  colArchivedAt<Invoice>(InvoiceFieldIds.archivedAt, (i) => i.archivedAt),
  colEntityState<Invoice>(
    InvoiceFieldIds.entityState,
    archivedAt: (i) => i.archivedAt,
    isDeleted: (i) => i.isDeleted,
  ),
  colFlag<Invoice>(
    InvoiceFieldIds.isDeleted,
    (i) => i.isDeleted,
    labelKey: 'is_deleted',
  ),
  colDocumentsCount<Invoice>(
    InvoiceFieldIds.documents,
    (i) => i.documents.length,
  ),
  // Created by. `labelKey: 'user'` — NOT `created_by`, which is
  // "Created by :name" and would leak the raw placeholder.
  colUserName<Invoice>(
    InvoiceFieldIds.userId,
    (i) => i.userId,
    labelKey: 'user',
  ),
  // Attached tags. Display-only (not a sortable Drift column).
  colTags<Invoice>(InvoiceFieldIds.tagIds, 'invoice', (i) => i.tagIds),
];

final Map<String, InvoiceColumn> invoiceColumnsById = {
  for (final c in kAllInvoiceColumns) c.id: c,
};

/// The Due Date cell: the date, in the `overdue` ink while the invoice is past
/// due, with "12 days late" in a tooltip (which screen readers also read).
///
/// "Past due" is [Invoice.isPastDueOn] — the predicate behind the Past Due pill
/// and, in SQL, the Overdue tab (`invoiceOverdueFilter`) — so a partial due date
/// that has passed makes the row late even while the full due date is ahead,
/// and the days are counted from that partial date. The cell itself never says
/// how late: relative text in a date column breaks the column's scan and its
/// sort.
Widget invoiceDueDateCell(Invoice i, BuildContext context) =>
    _lateDateCell(i, i.dueDate, context);

/// [date] (the due or the partial due date) as a date cell, marked late as
/// [invoiceDueDateCell] says.
Widget _lateDateCell(Invoice i, Date? date, BuildContext context) {
  if (date == null) return cellEmpty();
  final today = Date.today();
  if (!i.isPastDueOn(today)) return cellDate(date.toDateTime(), context);
  final from = i.partialDueDate ?? i.dueDate ?? date;
  return Tooltip(
    message: lateText(context, today.differenceInDays(from)),
    child: cellDate(date.toDateTime(), context, overdue: true),
  );
}
