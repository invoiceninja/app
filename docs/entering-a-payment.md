# Entering a payment

Companion to CLAUDE.md § Sync — non-obvious rules. How the payment create / edit form (`lib/ui/features/payments/widgets/edit/payment_edit_layout.dart`) is laid out, how a new payment is applied to invoices, and how its receipt is sent. Payment types have their own doc: `docs/payment-types.md`.

## A payment's receipt is sent by the bulk email action, and email_receipt only rides a create

The server reads `?email_receipt=` in exactly one place: `PaymentRepository::applyPayment` on the server sends the receipt `if (! $is_existing_payment && ...)`. A `PUT /payments/{id}?email_receipt=true` sends nothing. For a long time the record's Send Email action did exactly that — re-saved the payment with `sendEmail: true` — and toasted "Emailed" for a receipt that never went (the PUT also echoed the whole cached record back).

So:

- **An existing payment's receipt** is `PaymentRepository.emailReceipt` → an outbox row of `MutationKind.emailEntity`, payload `{id}` → `POST /payments/bulk {action: 'email', ids: [id]}` (the handler is in `_wirePayment`). This is the route React (`bulk([id], 'email')`) and v1 (`EmailPaymentRequest` → `bulkAction`) use. A payment still being created is fine: the row waits behind the create, and its temp id is rewritten when the create lands.
- **A new payment's receipt** rides the create: the form's Email receipt switch (`PaymentEmailReceiptSwitch`) sets `sendEmail`, which `PaymentsApi.create` lifts to `?email_receipt=true|false` — always sent, so the server's own default never applies.
- **`PaymentEditViewModel.performSave` sends `sendEmail: false` on every update**, and `sendEmail: isCreate && …` on a create (a failed create re-saved from its record has no switch).
- **The new-payment form offers no Send Email action** (`PaymentActions.editScreenItemsFor`). The edit scaffold runs an action by saving first and then dispatching it, so on a new payment Send Email would have created the payment — with the switch's receipt — and then sent another. The edit form of an existing payment keeps the action and has no switch.

Tests: `test/ui/features/payments/widgets/payment_actions_test.dart` (the edit screen's action bar), `test/ui/features/payments/payment_edit_view_model_test.dart` (email receipt group), `test/data/repositories/payment_repository_test.dart` (`emailReceipt enqueues an email row, not a re-save`).

## The Email receipt switch starts at client_manual_payment_notification

`seedPaymentReceiptDefault` resolves the settings cascade's `client_manual_payment_notification` (Settings → Online Payments → Emails) for the chosen client — client, group, company — and the company's before a client is chosen; it re-seeds on every client change until the user flips the switch (`PaymentEditViewModel.seedSendEmail`). React seeds the company's. Switching it on checks the client's primary contact has an address (`ensureRecipientEmail`, `invitations: null` = the primary contact, which `EmailPayment` mails) and offers to add one; declined, the switch stays off.

## A new payment is applied through the Apply to invoices table

Once a client is chosen, `PaymentApplyInvoicesSection` (`payment_apply_invoices.dart`) lists the client's open invoices as ticked rows — number, due date (the partial due date first, red in `overdue` ink once past due), balance, and an editable applied amount per ticked row — with Select All. It replaced a picker row per invoice and a Select Invoices dialog. Before a client is chosen, the Received from card's invoice picker (`PaymentInvoicePicker`) is the way in: picking an invoice picks its client, and the table opens with that invoice ticked — as does an invoice's Enter Payment (`stageCreateDraft`).

- **Ticking goes through `applyInvoiceSelection`**: a ticked row starts at the partial when the invoice has one, else the balance, capped by what is left of an amount the user typed. While the Amount is untouched it follows the ticks (`replacePaymentables`).
- **An allocated row always shows** (`payableInvoicesForApply`), even an invoice archived since or not cached on the device — what the payment applies is never hidden.
- **The list is what the device has cached after `ensureUnpaidForClientLoaded` and a drafts fetch.** When either did not fit one page the table says "Not every open invoice is shown", offers a filter that also searches the server (`client_status` draft + unpaid, the typed text), and runs the record's oldest-first fetch (`sort: date|asc`, as `oldestUnpaidInvoice` does).
- **Auto-apply oldest is offered only once "oldest" is known** — the answer was complete, or the oldest-first fetch landed — and is disabled at a zero amount. It skips drafts (nothing is owed on an unsent invoice), pays every partial before any full balance, then the balances oldest first (`autoApplyOldestFirst`), and sets the rows exactly (`setInvoiceAllocations`).
- **Edit mode applies nothing.** The server treats every `invoices[]` entry on an update as a new application, so the edit form hides the table, and `PaymentRepository.save` strips `invoices` / `credits` from the PUT. The record's Apply action is the way to apply an existing payment's unapplied money.

## Applied and Unapplied, never credit

The footer under the table shows **Applied** (the invoices net of the credits that pay them too, `netApplied`) and **Unapplied** (what the amount received leaves over, `unappliedAmount`). Money left on a payment stays on the payment; it is not a credit note, so it is never labelled "credit". The save rules it shows in error are the ones `validateForSave` enforces: credits outweighing invoices (`credit_payment_error`), invoices outweighing the amount plus credits (`amounts_do_not_balance`, the server's `PaymentAmountsBalanceRule`), and — while the company has Manual Overpayments (`enable_applying_payments`) off — any amount left unapplied (`over_payments_disabled`). v1 hid the Amount field in that state, so a payment was always the sum of what it applied; the company flag is read once the form opens.

## The form is laid out for the slide-over panel

`/payments/new` opens in a 440–560 px slide-over by default (`_kEditDefaultsToSlide`), so the single column is the layout most users see. Main column: Received from, Details (Amount | Currency, Date | Type, Number | Transaction reference, each a `FormFieldPair`), the create-only Apply to invoices table, Credits and the Applied / Unapplied footer, Tags, and the create-only Email receipt switch. On a new payment with a client chosen, the Apply to invoices block moves up between Received from and Details: picking invoices is the next step after the client, and below Details it sat a phone screen down (invoiceninja/app#213). Both blocks are keyed (`payment-apply`, `payment-details`), so the move reorders them rather than remounting the Details fields. The sidebar (below the main column when narrow): Currency conversion, Notes (private, with the "Only your team sees this" hint), Documents (`FormDocumentsCard` and its plan gate), Custom fields.
