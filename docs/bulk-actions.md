# Bulk actions

Companion to CLAUDE.md § Adding a new entity. This doc covers what a list offers when several rows
are selected: which bulk actions each entity has, which server action each one sends, and how to add
another. Per-record actions (the ⋮ menu, record screens) are out of scope here. They live in each
entity's `*_actions.dart`.

## A bulk action is one outbox row per selected record, never one row for the whole selection

`GenericListViewModel.applyBulkAction` calls a `BulkAction`'s `apply` / `applyArg` once per eligible
id. Each call enqueues its own outbox row, keyed to that record, with its own idempotency key. The
server's `/bulk` route takes an `ids` array, but sending one id per row keeps every per-record outbox
rule working:

- an `unconfirmed` row holds back later edits to *its* record;
- a discard or a dead row clears *its* record's `is_dirty` (`SyncRepository._releaseDeadLifecycleDirty`);
- the conflict sheet and the Outbox screen name one record.

A single multi-id row would need its own version of each of those. The bank-transaction
`convertMatched` / `unlinkTransaction` rows (`kBulkTransactionEntityId`) show the cost: those rows
have no record to reconcile. The price is N requests for N records. `bulk_update` has always paid it.

## A bulk action that sets a field writes it locally first, so it works offline

Change Category, Assign Group, Set Tax Category and Bulk Update all go through a repository method
(`ExpenseRepository.bulkCategorize`, `ClientRepository.assignGroup`,
`ProductRepository.setTaxCategory`, `*Repository.bulkUpdate`). In one transaction, that method:

1. upserts the patched row with `is_dirty = true`, so the list shows the new value at once, online or
   not;
2. enqueues a row whose payload is `{id, <the field the server reads>}`.

When the row drains, `bulkActionHandler` (`lib/app/services_entity_wiring.dart`) posts
`{action, ids: [id], ...extraKeys}` to `/<entity>/bulk`. It handles the result as follows:

- **An echo** (the server's `listResponse` of `ids`) goes through `applyUpdateResponse` /
  `applyEchoTemplate`. That clears the dirty flag.
- **A null echo** (the row was gone server-side) clears the flag directly.
- **A 4xx** dead-letters the row. `_releaseDeadLifecycleDirty` then clears the flag, so the next
  refresh replaces the refused value.

These kinds are `DeliverySafety.idempotent` because each one sets an absolute value.

Each server action here requires a real id, so a blank pick is refused before it is queued:

- Expense `categorize(Collection, int $category_id)` is a TypeError (500) on null.
- `assign_group` is `required_if` + `exists`.
- `set_tax_id` is `required_if` + `in:1..9`.

`showBulkPickDialog` (`lib/ui/core/dialogs/bulk_pick_dialog.dart`) is the prep dialog for setting one
related record. It holds one picker, and Save stays disabled until something is picked. Clearing the
relation is left to the record's edit screen, as in React.

## A risky bulk verb is `confirm: true` and has no prep dialog in front

These follow CLAUDE.md § Action confirmations. They fire at once and are financial, outward-facing or
hard to reverse, so they set `BulkAction.confirm`:

- invoice Cancel
- quote Convert to Project
- credit Mark Paid
- payment Send Email

Change Category, Assign Group and Set Tax Category stop for input already, so they do not
(`bulk_confirm_no_double_prompt_test`).

Each one's `eligible` mirrors its single-record twin's gate, tmpGate included. A record still being
created has no server id to cancel or convert. The list screen gates every bulk item on
`edit_<entity>` (`EntityListScreenScaffold._bulkActionAllowed`, for the entities in
`kPermissionEntities`). Module-dependent items use `isAvailable`, for example Convert to Project
only where projects are on.

## Recurring invoices have no Run Template, because the server has no `template` action there

`BulkRecurringInvoiceRequest` allows
`archive,restore,delete,increase_prices,update_prices,start,stop,send_now,set_payment_link,bulk_update,auto_bill,auto_bill_enabled`.
That holds on `v5-develop` too. `RecurringInvoiceController::bulk` never dispatches
`TemplateAction`. The single-record Run Template was removed for this reason earlier
(`recurring_invoice_actions.dart`). The bulk entry stayed, and every row 422'd into a dead outbox
entry. It is gone now.

## Run Template stays where it was and is not spread further, because nothing fetches its result

For every entity, `template` returns `{"message": "<hash>"}`. `TemplateAction` writes the PDF to
`templates/<hash>.pdf`, or emails it when `send_email=true`. React then polls for the hash and
downloads the file. This app does neither, so a run produces nothing the user can see. Adding it to
clients, tasks, projects, payments and expenses (all offered by React) needs that download flow first.
It also needs one run over the whole selection (templates are written for a collection) rather than
one row per record.

## Matrix

Legend: **S** = the server's bulk `action` rule accepts it, **R** = React's list offers it in bulk,
**V** = v1's multiselect offers it, **Ours** = this app's list, before → after this review. A blank
cell means no.

The sources for each column are:

- **S:** `app/Http/Requests/<E>/Bulk*Request.php` and `<E>Controller::bulk` in
  `/Users/hillel/Code/invoiceninja`.
- **R:** `src/pages/<e>/common/hooks/useCustomBulkActions.tsx`, plus DataTable's default
  archive / restore / delete.
- **V:** `getActions(multiselect: true)`.

| Entity | Action (server) | S | R | V | Ours |
|---|---|---|---|---|---|
| client | archive / restore / delete | Y | Y | Y | Y → Y |
| client | `bulk_update` | Y | Y | Y | Y → Y |
| client | `assign_group` | Y | Y | Y | — → **Y** |
| client | `template` | Y | Y | Y | — → — (skipped, see Run Template) |
| product | archive / restore / delete | Y | Y | Y | Y → Y |
| product | `set_tax_id` | Y | | Y | — → **Y** |
| task | archive / restore / delete, start, stop | Y | Y | Y | Y → Y |
| task | `bulk_update` | Y | Y | | Y → Y (server ≥ 5.13.44) |
| task | `template` | Y | Y | Y | — → — (skipped) |
| task | invoice / add to invoice (client-side) | — | Y | Y | Y → Y |
| project | archive / restore / delete | Y | Y | Y | Y → Y |
| project | `invoice` | Y | Y | Y | Y → Y (built on the device) |
| project | `template` | Y | Y | Y | — → — (skipped) |
| vendor | archive / restore / delete | Y | Y | Y | Y → Y |
| payment | archive / restore / delete | Y | Y | Y | Y → Y |
| payment | `email` (receipt) | Y | Y | Y | — → **Y** |
| payment | `template` | Y | Y | Y | — → — (skipped) |
| expense | archive / restore / delete | Y | Y | Y | Y → Y |
| expense | `bulk_update` | Y | Y | | Y → Y |
| expense | `bulk_categorize` | Y | Y | | — → **Y** |
| expense | `template` | Y | Y | | — → — (skipped) |
| expense | invoice / add to invoice (client-side) | — | Y | Y | Y → Y |
| recurring expense | archive / restore / delete, start, stop | Y | Y | Y | Y → Y |
| invoice | archive / restore / delete, mark_sent, mark_paid, auto_bill, email, template, print / download | Y | Y | Y | Y → Y |
| invoice | `cancel` | Y | Y | Y | — → **Y** |
| invoice | `set_payment_link` | Y | | | — → — (neither client offers it) |
| quote | archive / restore / delete, mark_sent, approve, convert_to_invoice, email, template, print / download | Y | Y | Y | Y → Y |
| quote | `cancel` | develop | | | Y → Y (server ≥ 5.13.44) |
| quote | `convert_to_project` | Y | Y | Y | — → **Y** |
| credit | archive / restore / delete, mark_sent, email, template, print / download | Y | Y | Y | Y → Y |
| credit | `mark_paid` | Y | | Y | — → **Y** |
| purchase order | archive / restore / delete, mark_sent, email, template, print / download, `expense`, `add_to_inventory` | Y | Y | Y | Y → Y |
| purchase order | `cancel` | Y | | | — → — (neither client offers it) |
| recurring invoice | archive / restore / delete, start, stop, update_prices, increase_prices, send_now, bulk_update | Y | Y / some | Y / some | Y → Y |
| recurring invoice | `template` | **not accepted** | | Y | Y → **removed** |
| recurring invoice | `set_payment_link` | Y | | | — → — |
| bank transaction | archive / restore, `unlink` | Y | Y | Y | Y → Y |
| bank transaction | delete | Y | Y | Y | — → **Y** |
| bank transaction | `convert_matched` | Y | Y | Y | — → — (one at a time by design: it creates payments / expenses and confirms each) |
| expense category | delete | Y | Y | Y | — → **Y** (archive / restore were there) |
| payment link | delete | Y | Y | Y | — → **Y** |
| company gateway | delete | Y | Y | Y | — → **Y** |
| document | download, delete | Y | | Y | Y → Y |
| group, task status, payment term, tax rate, token, webhook, design, schedule, tag, transaction rule, bank account | archive / restore / delete | Y | Y | Y | — → — (skipped: settings-style lists with no multiselect) |

Bulk Update coverage: `$bulk_update_columns` exists only on Client, Expense, Task and
RecurringInvoice. React's `BulkUpdatesAction` covers the same four, and so does this app
(`lib/domain/bulk_update_columns.dart`).

## Skipped, and why

- **Run Template on clients, tasks, projects, payments, expenses.** Nothing fetches the result (see
  above).
- **Bank transaction `convert_matched` in bulk.** It was left out on purpose
  (`transaction_list_screen.dart`). It creates payments and expenses server-side, and each one is
  confirmed.
- **Bulk actions on the settings-style lists** (group, task status, payment term, tax rate, token,
  webhook, design, schedule, tag, transaction rule, bank account). Those screens live under
  `lib/ui/features/settings/**` and have no multiselect. Adding one means building the list
  machinery there.
- **Invoice `cancel` with a Verifactu `reason`.** React sends a reason when Verifactu is on. Neither
  this app's single-record cancel nor the bulk one asks for one.
- **`set_payment_link`, PO `cancel`, `auto_bill_enabled`.** The server accepts them, but neither React
  nor v1 offers them in bulk.
