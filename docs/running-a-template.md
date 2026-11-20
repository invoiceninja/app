# Running a template

Companion to CLAUDE.md § Sync — non-obvious rules (which is at its size cap, so
the rule is stated here and in the `RunTemplateApi` / `MutationKind.runTemplate`
doc comments). This doc holds the server contract behind Run Template, why it
is not an outbox mutation, and the tests that pin it.

## Run Template is a synchronous read, never an outbox mutation — the bulk `template` action answers a job hash, the PDF is polled from `templates/preview/<hash>` and can be read once, and the picker offers only templates whose `entities` names the record type

**The failure it shipped as** (invoiceninja/app#197, reported on the Flatpak but
true everywhere): *"all available templates are always choosable in quotes and
invoices, [and] they won't be created after being put into queue."* Run
Template enqueued `MutationKind.runTemplate`; the drain posted the bulk action,
took the reply as "done" and dropped it. The reply was the only handle on the
PDF, so nothing ever arrived — the user saw "Template queued" and then nothing.

**The server contract** (`invoiceninja/invoiceninja`, v5-develop):

1. `POST /api/v1/<entities>/bulk` with `action: template`, `ids`,
   `template_id` and `send_email`. Every controller that supports it
   (`InvoiceController`, `QuoteController`, `CreditController`,
   `PurchaseOrderController`, `ProjectController`, `ExpenseController`, and
   `ClientController` / `PaymentController` / `TaskController`) dispatches
   `App\Services\Template\TemplateAction` and answers `{message: <hash>}` — a
   `Str::uuid()`, or the words `"email sent"` when `send_email` is true.
2. `TemplateAction` renders the records (several ids → one PDF) and either
   writes `templates/<hash>.pdf` to the default disk or mails the PDF as an
   attachment to **the user who ran it** (`$user->email` — never a client).
3. `POST /api/v1/templates/preview/<hash>` (`TemplatePreviewController`)
   answers **409** `{"message":"Still working....."}` until the file exists,
   then streams it as `application/pdf` **and deletes it**. A second read of
   the same hash 409s forever.

Neither step writes a record, so there is nothing for the outbox to make
durable — and an outbox row has no caller left to hand the PDF to. React
(`ChangeTemplate.tsx`) and admin-portal (`RunTemplateDialog`,
`lib/utils/dialogs.dart`) both run it synchronously: post, then poll.

**What the app does.** `RunTemplateApi` (`lib/data/services/run_template_api.dart`,
`Services.runTemplate`) is the two calls; `runTemplate(context, entity:, ids:)`
(`run_template_dialog.dart`) is the flow. It is offered on all nine record
types the server runs templates on (`RunTemplateEntity`: invoice, quote,
credit, purchase order, project, expense, client, payment, task), from the
record's actions menu and from its list's bulk bar:

- The picker lists `templatesFor(designs, entity)` (`lib/domain/run_template.dart`):
  `is_template`, the record type ticked in the design's `entities`, not
  deleted / archived, and not a `tmp_` design the server has never seen. That
  is the server's own filter (`DesignFilters::entities` is `FIND_IN_SET` on the
  column), and React asks `/designs?template=true&entities=<type>`. With no
  match the dialog says where to make one instead of showing an empty picker.
- **Send Email** off → the result opens in the shared document viewer
  (`showDocumentViewer`) with Download; the viewer owns the spinner, the error
  and Retry. Closing it stops the polling (`isCancelled`). Retry starts a
  *fresh job*, because the hash it polled may already have been consumed.
- **Send Email** on → one call, then a toast; there is no hash to poll.
- **Reading the PDF back needs more than starting the job.** The bulk action
  asks only `can('view')` of the records; `templates/preview/<hash>` is guarded
  by `ReportPreviewRequest`, which admits an admin or a `view_reports` holder
  and refuses a free hosted account (`isFreeHostedClient()`: a free / empty
  plan slug or an expired plan, no trial exemption). `runTemplatePdfBlock`
  asks the same questions up front; when either fails, Send Email is switched
  on and locked, with the reason under it. A 403 that gets through anyway is
  shown as `DocumentFetchRefused` — a sentence and no Retry, since every Retry
  would queue another job nobody can read.
- **A record with unsynced edits is refused** (`sync_first_generic`), and is
  not eligible in a list. The server would render its older copy: the outbox
  row this replaced waited behind the record's own save, a direct call does
  not. "Unsynced" is the `is_dirty` flag **and** the outbox: `runTemplate`
  asks `OutboxDao.hasActiveRowsForEntity` (pending, in flight or unconfirmed)
  for every id, because the flag and the queue can disagree and a list's
  `eligible` is synchronous and sees only the flag. One queued record refuses
  the whole run, and the selection is kept.
- **An email run succeeds only on the words `"email sent"`.**
  `RunTemplateApi.start` throws a `FormatException` on any other 200, which
  surfaces as the Run Template error toast instead of "emailed".
- A list selection is one call with every id (one merged PDF), through
  `EntityListBulkAction.onSelection` — never the per-id loop. Unsynced
  (`tmp_`) and dirty rows are not eligible. Backing out of the picker returns
  `SelectionActionOutcome.cancelled`, which keeps the selection, as a
  cancelled `prepare` does.
- Poll budget: 60 × 2 s. A 409 is "not yet". Up to three connection failures
  in a row are ridden out — the job keeps running while the network blinks,
  and giving up would throw it away. Anything else stops at once, a bare 404
  included (`ApiClient` maps it to `ServerException`, not to a
  `ConflictException`).
- The action is offered whether or not a template exists yet (React hides it
  until one does; admin-portal per record type). The menus are built
  synchronously and the designs live in a Drift stream, and an entry that
  explains how to make a template is more discoverable than a missing one.

**Recurring invoices have no `template` action** (`BulkRecurringInvoiceRequest`
whitelists none), so `RunTemplateEntity` has no recurring value and the
recurring-invoice menu offers nothing — BACKEND.md § Recurring-invoice
`template` bulk action unsupported.

**`MutationKind.runTemplate` stays, unused.** A row an older build queued must
still decode. `legacyRunTemplateHandler` settles it without a request —
sending it would render a PDF nobody reads (or 422, for a recurring invoice) —
rather than leaving it to dead-letter in the Outbox for want of a handler.

**Tests:** `test/data/services/run_template_api_test.dart` (the wire shape, 409
retry, riding out network drops, timeout, cancel, a 500 or 403 not retried),
`test/domain/run_template_test.dart` (the entity filter, the PDF gate),
`test/ui/features/invoices/widgets/detail/run_template_dialog_test.dart`
(the empty state, the single-template preselect, Send Email, the locked
email-only state).
