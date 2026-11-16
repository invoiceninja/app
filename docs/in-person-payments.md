# In-person card payments (Stripe Terminal)

Companion to CLAUDE.md § Strict rules (the store-SDK bullet, whose general evidence is in
`docs/fdroid.md`; this doc is Stripe Terminal's part of it). Taking a card in person — Tap to Pay on
the phone or a Stripe M2 Bluetooth reader — and paying an invoice with it. The server half is
invoiceninja/invoiceninja#13435 (gateway type 32, `card_present`): it creates every PaymentIntent
and records every payment, and the device only reads the card.

How it is turned on, who sees it, the collection step by step, what a failure looks like at each
step, how support untangles one, and what the SDK costs every store user.

## The SDK is reached only through `StripeTerminal`

`packages/store_services/lib/src/stripe_terminal.dart` wraps `mek_stripe_terminal` in plain value
types; the FOSS twin declares the same API with `isAvailable == false`. Connection-level calls are
static on `StripeTerminal`; each payment is a `TerminalPayment` from `beginPayment(clientSecret)`.

- **No mek object crosses the boundary.** A mek `PaymentIntent` and a mek `TerminalException` both
  print the PaymentIntent's client secret in `toString()`, so every result is copied and every
  error becomes a `TerminalError(code, message)`. A `PlatformException` keeps only its code and
  message — its details can carry the PaymentIntent.
- **A payment is one object, and its steps are guarded.** `collect()` reads the card without
  charging; after the server changes the PaymentIntent, `collect()` again (Stripe needs a fresh
  read). `confirm(paymentIntentId:, amount:)` charges only the card `collect()` read, for that
  PaymentIntent at that amount, so a stale read or a read made before the server raised the amount
  can never be charged. One payment at a time; a second `beginPayment` while one is unfinished
  throws `readerBusy`, and a step while another runs throws `invalidState`.
- **A cancel is never lost.** `cancel()` works until `confirm()` starts. Between steps it marks the
  payment cancelled, so every later step throws `canceled`; during a read it also cancels the SDK
  operation, which is started at once — mek's `CancelableFuture` starts lazily on its first
  `await`, and a cancel before that does nothing. The SDK's cancel can hang forever, so it is fire
  and forget, bounded at 5 seconds; the server's cancel is what closes the PaymentIntent.
- **A confirm is never cancelled, and an unclear failure says so.** A declined card (or a
  PaymentIntent back in `requires_payment_method`) leaves the payment open for another card; any
  other confirm failure is `outcomeUnknown` — the card may have been charged, and only the server
  can say.
- **A token source belongs to one account.** `initialize(account:, fetchToken:)` keeps the SDK's
  cached token and reader session for the same account and `reset()`s for another. `reset()`
  abandons the payment in progress, drops the source (a token still being fetched for the old
  account is thrown away: `_generation`), bounds every step, never throws, and if Stripe couldn't
  clear its credentials the next `initialize` tries again. Every token failure reaches the SDK as
  a `TerminalError` — the plugin relays it to native code, which can't take a null message.
- **`connect` always passes `tosAcceptancePermitted`** — the SDK defaults it to true, which would
  let a non-admin accept Apple's Tap to Pay terms.
- **A reader's kind is the kind `discover` looked for**, not its `deviceType`, which the SDK leaves
  null for a type it doesn't know.
- **Reader prompts go to `StripeTerminal.events`**, read when each event arrives. Its one slot
  belongs to `TerminalController`, which sets it once and fans each event out
  (`addEventListener`); screens subscribe and never set it. The controller keeps the
  configuration progress (`setupProgress`), drops the reader on a disconnect, and notes Apple's
  terms being accepted (`onAcceptTermsOfService` → `onTermsAccepted`).
- **Error codes are matched on mek's enum**, so a renamed code fails to compile instead of
  becoming `unknown`. Apple's four terms outcomes stay apart, each with its own words and a
  Retry: `termsCanceled`, `termsNeedsAppleAccount`, `termsNotAccepted` (a connect that may not
  show them: a non-admin, or a warm-up) and `termsFailed`. Brands and statuses come back in Stripe's own spelling (`mastercard`,
  `requires_capture`).

## Who sees "Collect card payment", and what the app asks the server

- **The server decides.** `TerminalController.ensureConfig` asks `GET /terminal/config` only after
  the cheap gates pass (`kCardPresentEnabled`, the mobile app with Stripe's SDK, not the demo,
  `create_payment`) — a user without that permission would get a 401. An answer stands for five
  minutes (an admin who turns Card present on sees it without a restart); a failed fetch keeps the
  last answer and is tried again after a minute; an older server's 404 is remembered as "not here"
  for the session. None of it toasts or reports.
- **`terminalAvailability`** (`lib/domain/terminal/terminal_eligibility.dart`, pure) adds the
  invoice (not deleted, paid, cancelled, reversed or unsaved; drafts are fine — the server marks
  them sent) and how this phone can read a card: Tap to Pay when the phone can and the gateway's
  Stripe account is in `kTapToPayAndroidCountries`, else a Bluetooth reader only once one has been
  connected in this app (`DevicePrefKeys.cardReaderUsed`, account scope) — not on every phone that
  merely has Bluetooth. A hosted plan below Pro shows it as an upgrade.
- **Build switches**: `IN_CARD_PRESENT`, `IN_CARD_PRESENT_BLUETOOTH`, `IN_CARD_PRESENT_SURCHARGE`
  (all default true) pull the feature or one part of it without a code change.
- **The server offers no surcharge for now.** It was taken out of invoiceninja#13435 before the
  merge (2026-11-16): nothing reported the surcharge to the card networks, and a debit card could be
  surcharged and then refunded. `terminal/config` carries no `surcharge` key, so
  `TerminalSurchargeConfig` parses as not allowed and every surcharge surface stays hidden; `quote`
  answers `total == amount` and `finalize` always answers `recollect: false`. The app's surcharge
  flow below is kept for when the server offers one again.
- **The SDK session is one Stripe account and Location** (`account: company/gateway/location`): a
  connection token belongs to exactly one.
- **A session end or a company switch resets it** (`onBeforeLogout`, `onActiveCompanyChanged`):
  the session's own state goes at once, then the SDK is reset once no charge is in flight
  (`guardCharge`, from a card's finalize to the server's answer), waiting up to 150 seconds — longer
  than the facade's 2-minute bound on a confirm — unless a newer session was prepared meanwhile.
- **`TerminalRepository` is online-only** (the CLAUDE.md outbox exception): every call in the
  company's `RequestScope`; a refusal the screen branches on comes back as a
  `TerminalServerError(code, message, data)` read from the body's `error_code` — 409 and 403 bodies
  are kept on `ConflictException.body` / `ServerException.body` for this — and a plain 422 is
  `field_errors` with its first message. `apply_fee` goes in the quote's query as `1` / `0`, and at
  create only with a fee the quote actually came to (one that rounds to nothing is `fee_not_allowed`).
  `finalize` times out at 12 s for the answer to start and 12 s more for its body, so it can take
  about 24 s; what keeps a charge inside Stripe's 30 s between reading a card and charging it is the
  25 s staleness check below, not this timeout. A refused connection token (a gateway an admin just
  switched off, say) reaches the SDK as its own generic error, so the controller keeps the server's
  reason for the screen (`takeTokenError`) and re-reads the config. A collection's finalize, complete,
  cancel and receipt are addressed under its invoice (`invoices/{invoice}/terminal/payment_intents/
  {pi}/…`): the server keeps a collection on the invoice's payment hash and finds it by the invoice. The invoice is re-read after a create (a draft was marked
  sent) and after every `complete` / `cancel`; a recorded payment also re-reads its client and the
  payment.

## A collection, step by step

"Collect card payment" is on the invoice's record screen only (`InvoiceActions.itemsFor` /
`quickItemsFor` take a `TerminalAvailability`; lists, the dashboard and the editor pass none), as a
`Card` tile that leads on a draft too. It opens `showCollectCardPaymentScreen`, a full-screen route on
the root navigator that is never saved as a route; `CollectCardPaymentViewModel` drives it.

1. **Configure.** The gateway whose Stripe account charges in the client's currency (the client's
   own, else its group's, else the company's — Stripe Terminal takes only the account's own
   currency; `TerminalConfig.gatewayFor`, the first usable one when the client isn't known) and its
   Location; a config that never loaded is a connection problem with a Retry that loads it again,
   never "Card present is off". The amount (a deposit if one is due, a
   draft's amount, else the balance); the surcharge switch only when the gateway allows it (an admin
   acknowledges the rules first, `surcharge_acknowledgement`). Every figure is the server's `quote`,
   shown in the currency the quote names (`currency_id`, which the server resolves through the
   client's group) — before the first quote, in the client's or its group's currency.
   Permissions, the SDK and the reader start in parallel, so nothing waits after "Collect".
2. **Create.** A new `collection_id` per attempt; the same one only to retry a create whose outcome
   is unknown (the server answers the same PaymentIntent). `collection_closed` gets a new id once;
   `collection_open` offers **Cancel it and start again** (the server's cancel records the payment
   instead if it was charged after all).
3. **Read, then finalize — after every read.** `finalize` may raise the PaymentIntent for a credit
   card's surcharge, or lower it again for a debit card on the next read: then the card is read
   again (at most four reads in a row: base, raised, lowered, and one that went stale). A read more than 25 s old by the time finalize answers is read again
   too (Stripe allows 30 s), and a finalize that fails cancels — a charge is never made on a guess.
4. **Confirm** at the latest `amount_minor`. From finalize to the server's answer everything runs
   inside `TerminalController.guardCharge`: nothing — not Cancel, Back, a company switch or a
   sign-out — interrupts it. A company switch (a deep link's) is refused outright while any payment
   is under way on the screen — every call that settles it is bound to this company — through the
   unsaved-changes guard's `blockedMessage`. A screen that closes before the charge gives the payment up (after
   finalize answers, if it was deciding); a charge already under way finishes, and the server
   records it.
5. **Result.** One table maps `complete` (and `cancel`):

| Answer | Screen |
|---|---|
| `recorded`, `unapplied` | Approved (and the unapplied note), receipt by email or QR |
| `recording` (the server holds the charge and is recording it) | Recording — "Charged. The payment is being recorded." + Check again |
| `requires_payment_method` after a confirm | Declined — the charge failed; another card on a new payment session |
| Stripe's own `processing`, other `requires_*` after a confirm started, a confirm with an unknown outcome, `complete` failing (asked 3 times) | Checking — "We couldn't confirm whether the card was charged. Don't take another card for this invoice yet." + Check again, or Cancel the payment (the server records it instead if it was charged) |
| `rejected`, `orphaned` | Charged, couldn't be recorded — contact support (the server alerted) |
| `canceled`, `failed` | Cancelled — the only screen that says the card wasn't charged, with a decline. Pay another way is offered here too |

A decline leaves the PaymentIntent open: **Try another card** reads again and finalizes again. Every
SDK and server code has words (`terminal_error_text.dart`, tested exhaustively).

Before a second tap that raises the amount, the screen stops on the surcharge (`surchargeNotice`:
"Credit card: $103.00, including a $3.00 surcharge…") with Continue / Cancel — the customer may
decline it and pay another way (a debit card isn't surcharged: Continue, then present it). **Try
another card** on a PaymentIntent the surcharge already raised shows the notice again first: the
next card is read at the raised amount. "Charging" is shown only during a confirm; asking the server about a
payment (Check again, a cancel) is `settling` ("Checking with Stripe…").

**A charge the app never heard back about isn't forgotten.** From the moment a confirm starts until
the server answers for good, the PaymentIntent is kept on the device
(`DevicePrefKeys.pendingCardPayments`, account scope). Opening the invoice asks the server again
(`recoverPending`, every pending charge on the invoice, not just the first). Every way of recording
a payment by hand checks first — `InvoiceActions.cardPaymentsSettled`, from Mark Paid and Enter
Payment on the record screen, Mark Paid in the editor (`confirmSaveParam`), a bulk Mark Paid
(`preflight`), a payment's Save that applies it to the invoice (`confirmSave`, whichever screen
opened it) and both one-tap Applies of an unapplied payment (the invoice's Unapplied payments tab,
the payment's Apply to the oldest invoice): a charge that
turns out recorded stops the action and says so (the balance it was about to pay is gone); one
that still can't be answered is warned about every time a payment would be recorded over it — Enter
Payment only recovers, and the warning comes at the payment's Save. A Save the check is still
asking about is never run twice. "Cancel it and start
again" that lands on Checking or Recording notes the other attempt's PaymentIntent too. A
deliberate sign-out forgets the list (account scope), as it forgets everything else on the device.
**Known limit:** the list is this device's. Another phone, the web app or another user can still
record a payment on the invoice by hand while a charge is unanswered; the server then records the
card payment as unapplied client money (`unapplied`), and support refunds one of the two. The Checking, Recording and "couldn't be
recorded" screens show the PaymentIntent as a copyable reference.

## A card that wasn't charged has three ways on

App PR 4 (App Review 4.8, 5.10, 5.12). All three are for every reader, on every platform; only the
names differ (Tap to Pay on iPhone on an iPhone, plain "Tap to Pay" or "the card reader" elsewhere).

**Pay another way is offered only where no card was charged.** `CollectCardPaymentViewModel.canPayAnotherWay`
is true on `declined` and `cancelled` and nowhere else — never on `recording`, `checking` or
`unrecorded`, where the card was, or may have been, charged. `payingAnotherWay` re-checks the stage on
every read, so a cancel that turns up a charge after all (`recorded`) hands the screen to that answer.

- **It shows at once and cancels behind it.** `payAnotherWay()` flips to the fallback and, from
  `declined`, starts `_abandon()` without waiting: the PaymentIntent is cancelled in the background,
  which frees the invoice for the portal's own payment. From `cancelled` there is nothing left to
  cancel.
- **The code is the invoice's own portal link** — the first non-empty `invitations[].link` — drawn by
  `QrCodeImage` (always black on white). The sentence names no amount: the portal pays the invoice
  (its balance or deposit, its own fees), so a figure here could disagree with it. **Share link** goes
  through `shareOrCopyLink`; **Done** closes the screen.
- **No link, or no online payment type switched on, is "can't be paid online".** The signal is
  `canTakeOnlinePayments` (`lib/domain/terminal/online_gateways.dart`), over one Drift read of the
  company's gateways as the fallback opens (no request, and no live watch — a watch on this screen
  hung its widget tests): an active gateway with a type enabled other than Card present (32). The
  Stripe gateway that takes the card in person also takes cards online, so a bare gateway count would
  never be zero here; what can be false is every online type switched off. A gateway that lists no
  types counts as able, and so does **a read that fails or times out**: the portal says so itself if
  it can't take the payment. Which gateways the portal offers one client in one currency isn't
  modelled locally. The variant offers **Enter Payment**, which is the invoice's own action
  (`InvoiceActions.dispatch`, handed in as `enterPayment`), after this screen has closed, with every
  check that action already makes.
- **Enter Payment opens only on a confirmed no-charge answer.** `settledWithoutCharge()` is true once
  the server answered the cancel `canceled` (or nothing was ever created). A cancel every attempt of
  which failed is asked again, and while nobody knows the screen says "We couldn't confirm the card
  payment was cancelled…" and stays. One press runs it once: the button is busy while it waits.
- **"Back to …" starts a collection of its own, after the old one has gone quiet.** `backToReader()`
  first waits for everything the ended collection still has on its way (`_inFlight`: its run — a
  create, a reader that stops — and its one `_abandon()`), then fetches the invoice again
  (`refetchInvoice`: the server's copy into Drift, then read), quotes again, and only then collects —
  a new `collection_id`, a new PaymentIntent.
  - **An old answer never lands on the new collection.** Each collection has a generation
    (`_startOver` bumps it): a cancel's answer, a create's, or a reader error from an older one is
    dropped — it used to stamp Cancelled onto the new collection and clear the new PaymentIntent's
    crash record. A create answered late is closed (`_cancelStray`), never adopted; `_settle` clears
    the pending record of the PaymentIntent the answer is about.
  - **A changed invoice is never collected automatically.** If `balance`, `paidToDate`, `partial` or
    `amount` differ from the invoice collected against (a deposit just paid online), the amount
    becomes `defaultAmount(fresh)`, the checkout shows "The invoice changed. Check the amount." and
    waits for a fresh press; the amount field is re-seeded whenever the view model's amount changes
    outside it. An invoice that couldn't be fetched waits for a press too ("The invoice couldn't be
    checked again…"). One paid in full stops on Cancelled with "A previous card payment for this
    invoice was recorded." and offers no fallback.
  - The row carries its caution: "If the customer started paying online, wait for it to finish first."
- **Cancel on a declined card stays on Cancelled**, which says the card wasn't charged and still
  offers Pay another way; its own Close leaves.

**A decline receipt needs a declined charge.** `declineReceiptAvailable` is true only after a confirm
that Stripe declined (or a `complete` answering `requires_payment_method`) — never for a card that
merely couldn't be read, which has no charge for the server to write a receipt about. It is the same
`receipt` endpoint as a paid one's: the server answers a collection that is open or cancelled with its
own decline receipt, a few per collection. **Try another card** forgets it: the next card is a new
story. The states are the view model's (`DeclineReceiptState`: idle, sending, sent, failed with its
reason, limit) and the email's controller is the screen's, so the row — and what was typed in it —
is the same on the declined stage and on the fallback; the field shows only after the press. `receipt_limit` is a **429 with a
body**: `RateLimitedException` carries it, and `TerminalServerError.from` reads its `error_code` — a
plain throttle (no code) is a failure that may be tried again, never the limit.

On Approved, **Share receipt** hands Stripe's `receipt_url` to `shareOrCopyLink`; it is there only
when the server sent one. The card reads as a receipt names it — "Visa •••• 4242" (`cardLabel`:
Stripe's brand code in the network's own spelling).

**A decline nobody saw is told once.** A charge under way when the app closed leaves its PaymentIntent
in `pendingCardPayments`. At company activation — after the same `terminal.reset()` the warm-up waits
for, so never while a card is being charged — `TerminalDeclineNotices.sweep` asks `complete` about
every pending payment of that company (`TerminalController.sweepPending`):

| Answer | What happens |
|---|---|
| final (`recorded`, `canceled`, …) | nothing: the entry stays for the invoice's own check (`recoverPending`), which stops a payment entered by hand over a recorded charge and says "The card payment went through" — clearing it here silently took that warning away (`card_payment_settled_test`) |
| `declined: true` (with `brand`, `last4`; `status` stays `requires_payment_method`) | told, then `cancel`; the entry is cleared once the cancel's answer is final |
| anything else, or a server from before decline answers (no `declined` key) | nothing is told; the entry waits for the invoice's own check |

- **One toast for everything found**: "Card declined on invoice N. The customer wasn't charged." with
  **Open** to the invoice, or "N card payments were declined…" with Open to the invoices — a phone
  shows only the newest toast, so one each would hide all but the last. It stays up at least
  `shownAtLeast` (12 s).
- **Told first, cancelled after.** The server stops its own email about a decline once the app's
  `complete` was answered with it, so a notice dropped here would be told to nobody. A notice that
  can't show — the app locked (`ArrivalGate`), not `resumed` (the class observes the lifecycle and
  shows on the way back), no localization yet — is held and the entry stays pending, so a closed app
  finds it again.
- **Never twice.** Telling writes `told` onto the entry (`markDeclineTold`) and the id is held in
  `_settling` from before anything is awaited: a company switched away and back mid-cancel, or a
  cancel that failed, finds the entry again and only settles it.
- **Cleared only on a final answer** (`settleUnseenDecline`): `canceled`, or `recorded` if the card
  turned out charged. On `recording` / `processing`, or an error, the entry stays for the next sweep.
- The invoice's number rides in the entry (`notePending(invoiceNumber:)`); one from before that reads
  "A card payment was declined…". Open goes nowhere if the company changed.

**Ready says when nothing can be paid online.** Apple wants every merchant to have another way to be
paid. When the enable screen reaches Ready it reads the gateways once and, if `canTakeOnlinePayments`
is false, adds a row — "Invoices can't be paid online yet…" — that opens `/settings/company_gateways`.
Unknown (a failed read) shows nothing.

### Themes

The app's themes are the six `InTheme` presets — light Sand, Mist and Paper; dark Espresso, Midnight
and Carbon; one per side, chosen in Device Settings — plus the per-user accent colour over either
side. `terminal_themes_test` (`kAllAppThemes`: the six, and a pale and a near-black accent) pumps
every collect stage, the fallback, the enable screen, the Card readers tile and the location
pre-alert under each; fails on a colour literal in those files (tokens only); and checks contrast
from the tokens. Two things it pins:

- **The primary stage button's label is `InTheme.onAccent`**, not the theme's white: white on a pale
  accent reads 1.8:1.
- **The payment code is black on white in every theme** (`QrCodeImage`).

Known and left alone: a near-black accent on a dark theme dims every accent mark (accent on
`accentSoft` reads about 2.5:1) — that is the accent's derivation, app-wide, and the user's own
choice of colour.

## Support runbook

- **Find it.** The screen's reference is the Stripe PaymentIntent id. Without it: Stripe's payments
  search by the invoice number (the PaymentIntent's description is "Invoice N · client", its metadata
  holds `invoice_number`, `collection_id` and `payment_hash`). On the server a collection is that
  `payment_hashes` row (`hash` = the metadata's `payment_hash`; `fee_invoice_id` = the invoice).
- **Read the row.** The collection's own state is in `data->terminal`; the invoice, fee and payment
  are where every payment hash keeps them (`data->invoices`, `fee_total`, `payment_id`).
  `terminal.status_id`: 1 creating (Stripe hadn't answered the create), 2 open, 3 recorded,
  4 cancelled, 5 failed (never got a PaymentIntent, or it no longer exists at Stripe), 6 orphaned,
  7 rejected. `surcharge_path`, `surcharge_refunded` (minor units) and `receipts_sent` explain the
  money around it.
- **Checking / Recording.** Nothing to do by hand: the server records every charge from Stripe's
  webhook, `complete`, and its reconciliation job (one per collection, queued when its PaymentIntent
  opens and again on a resumed create, except on the `sync` queue driver, where a delayed job would
  run at once and never again; it first looks after 5 minutes, then every 10 while the
  collection is open, records a charge nobody recorded, and cancels one untouched for 20 minutes, for
  up to 30 days). Auto-bill settles an invoice's open collections the same way before it charges
  anything. Recorders take turns on a lock of the payment hash, so each charge is recorded once; one
  that waits too long for its turn answers `recording`.
  `php artisan ninja:terminal-reconcile <payment_hash>` (the hash is in the PaymentIntent's metadata)
  records one now and prints its status; for an uncharged PaymentIntent it prints e.g.
  `requires_confirmation` and leaves the cancel to the job. **Never Enter Payment for a card payment the server is still
  recording** — it would count it twice.
- **Rejected (7) / orphaned (6) — "charged, but couldn't be recorded".** The money is at Stripe and
  the server won't record it on its own: a rejected PaymentIntent didn't match its collection
  (account, mode, currency); an orphaned one lost its invoice and client. Either refund it in Stripe,
  or record it by hand with Enter Payment using the Stripe charge id as the transaction reference. The
  server alerted (System Logs, and Sentry where configured).
- **Alert "the surcharge could not be refunded".** A surcharge charged to a card it doesn't apply
  to (debit, prepaid, Interac, or an invoice paid meanwhile) is refunded by the server; when Stripe
  refuses that refund the payment is recorded anyway, with the surcharge as the client's unapplied
  money. Refund the surcharge in Stripe: the refund comes out of that unapplied money.
- **Alert "reconciliation could not record a charge".** A charged collection that fails to record
  for a reason other than Stripe (a data problem on the invoice or client) stays open; its job keeps
  trying every 10 minutes and alerts once. Fix the cause and it records itself; if you enter the
  payment by hand instead, use the Stripe charge id as the transaction reference.
- **"Still being set up" on a new collection.** Stripe never answered a create; after 2 minutes the
  next attempt marks it failed and goes on.

## Self-hosted and rollout

- **What a self-hosted server needs:** a queue worker for reconciliation (with the `sync` driver the
  job never runs later, though auto-bill and the next collection on the invoice still settle it),
  and Stripe webhooks reaching it for the fast path. Without either, a charge the
  app couldn't report waits until someone collects or checks on that invoice again, or support runs
  the command.
- **Switches.** `NINJA_TERMINAL_ENABLED` (default on) refuses new collections and finalize — a
  collection in progress is cancelled before its charge — while complete, cancel and receipt keep
  working. With `config:cache` an env change needs a re-cache and a php-fpm / worker restart. The app's
  `terminal/config` answer stands for up to 5 minutes. Build-time `IN_CARD_PRESENT*` pull the app side.
- **Order:** migrate the server, deploy it, then ship the app (older servers answer 404 and the
  feature stays hidden). **Rollback:** switch it off, wait until no payment hash has
  `data->terminal->status_id` 1 or 2 (about 25 minutes), then roll back; an older server ignores
  card-present webhooks, and queued reconciliation jobs then fail harmlessly.

## The device check and permissions are ours, not the SDK's

Stripe's Android SDK checks permissions but never asks; its iOS SDK may prompt for location at a
moment the app doesn't choose; and its own `supportsReadersOfType` asks for location and Bluetooth
just to answer. So `StripeTerminal.deviceSupport()`, `requestPermissions(kind)`, `permissionStatus(kind)` and
`openSettings()` go over `invoice_ninja/stripe_terminal`. `requestPermissions` answers `granted`,
`denied` or `blocked` (the system won't ask again — offer Settings), and concurrent calls share one
request. `permissionStatus` gives the same answers without ever prompting (iOS
`authorizationStatus`, with location services off as `blocked`; Android `checkSelfPermission`):
`denied` there means "not asked yet".

- **Android** — `StripeTerminalPlugin` in `packages/store_services/android`. Tap to Pay needs
  Android 13, an ARM processor (Stripe ships its kernels for ARM only), NFC and a hardware
  keystore — Stripe's own preflight, except the key it generates to check; `tapToPayBlocker` says
  what's missing. A Bluetooth reader asks for "Nearby devices" (Android 12+); Tap to Pay asks for
  location only. Precise location is always asked for together with approximate — Android 12+
  ignores a precise-only request — and only precise counts as granted (Stripe takes approximate on
  a device with no GPS; this is stricter). A dialog survives a config change.
- **iOS** — `StripeTerminalBridge` in `ios/Runner/AppDelegate.swift` asks for location while in
  use; for a Bluetooth reader a refused Bluetooth permission is `blocked` (iOS asks for it itself
  when a scan starts). A prompt iOS never shows is answered after 2 minutes. `deviceSupport`
  reports Tap to Pay on iPhone only when the build is signed with
  `com.apple.developer.proximity-reader.payment.acceptance`, on iOS 15.4+ (ProximityReader), on an
  iPhone Apple says can (`PaymentCardReader.isSupported`: XS or later, never the simulator).
  Below iOS 17.6 it also answers `osUpdateRequired`: the action and the button stay, and a press
  says to update iOS (App Review 1.4) instead of trying. `symbolImage` draws an SF Symbol as a
  PNG for the app to tint.

## Tap to Pay on iPhone is signed into Debug builds only, until Apple grants distribution

Apple granted the **development** entitlement on 2026-11-15; TestFlight and the App Store need the
**distribution** one, which Apple grants after reviewing three recordings (new user, existing user,
checkout) and its App Review Requirements Checklist. A profile without it fails every upload, so:

- **Debug signs with `ios/Runner/RunnerDebug.entitlements`** (`Runner.entitlements` plus the key);
  Release and Profile sign with `Runner.entitlements`, which mustn't have it yet.
- **The app learns which from the `IN_TAP_TO_PAY_ENTITLED` build setting** (YES for Debug only),
  through Info.plist `INTapToPayEntitled`; without it `deviceSupport` says `entitlementMissing`
  and the phone offers a Bluetooth reader instead. `ios_entitlements_test` keeps the setting,
  the two files and Info.plist in step.
- **When distribution is granted:** add the key to `Runner.entitlements`, set
  `IN_TAP_TO_PAY_ENTITLED = YES` for Release and Profile (and Debug can sign with
  `Runner.entitlements` again), regenerate the profiles, update the `APPLE_*` signing secrets if the
  profile is stored there.
- **Countries differ by platform:** an iPhone checks `kTapToPayIPhoneCountries`, Android
  `kTapToPayAndroidCountries` (Stripe's two lists).
- **Apple's "How to Tap"** (`showHowToTap`: `ProximityReaderDiscovery` on iOS 18+, our own dialog
  before that) shows right after Apple's terms are accepted (once their sheet has closed and the
  app is back in front), else once per account when the reader first connects on the collect
  screen (`DevicePrefKeys.howToTapShown`, set only when something was actually shown), and from
  Device Settings → Card readers → How to use. App Review requires all three (4.2, 4.3).

## Tap to Pay on iPhone follows App Review's rules, on iPhone only

Apple's "App & Marketing Requirements and Review Guide" decides how the feature looks and behaves
on an iPhone. Everything here is gated on `isIPhonePlatform()` (or the VM's / controller's injected
`iPhone`); Android, the FOSS build, desktop and web are unchanged.

- **Apple's name, never shortened** (5.4). `lib/l10n/tap_to_pay_names.dart` holds the long forms of
  the guide's localization table (pp. 20–21), keyed on the language code, with `fr_CA`, `zh_TW` and
  `zh_HK` overrides; a language Apple doesn't list uses English. A label that is only the name uses
  `tapToPayName(context)` (the Android name, `tap_to_pay`, elsewhere). A sentence carries a `:name`
  placeholder filled by `tapToPayNameFor(context, key)`: while that sentence has no translation in
  the app's language (`Localization.isTranslated`) it renders in English, so it gets Apple's
  English name — never "Tap to Pay auf dem iPhone" inside an English sentence, nor a right-to-left
  name inside a left-to-right one. `terminalProblemText` takes the resolver as `name:`.
  `Localization` also lays the name in as `tap_to_pay_on_iphone` when it loads, so the Device
  Settings row, its settings search hit and the reveal all read the same words.
- **Nothing before general availability.** On an App Store build without Apple's entitlement
  (`entitlementMissing`), Device Settings draws no Tap to Pay row and search doesn't offer one
  (`tapToPayRowShown`), and the gateway's Card present help doesn't name it
  (`card_present_help_neutral`, also on macOS).
- **No Android words on iOS.** iOS has its own permission, insecure-environment, location and
  "this device" strings (`terminalErrorKey(iOS:)`), and the error a Tap to Pay screen shows names
  the action as it is (`terminalServerErrorKey(tapToPay:)`).
- **Apple's symbol, or no icon** (5.5). `TapToPaySymbol.load()` (from `main.dart`) has iOS draw
  `wave.3.right.circle` once; `TapToPayIcon` tints it (`srcIn`), skips screen readers, and keeps
  its square empty until it is drawn. `EntityActionItem.iconBuilder` carries it into the record
  screen's menu, buttons and quick tiles. `Icons.contactless_outlined` never shows on iOS.
- **Who sees the action** (`terminalAvailability`): besides a usable gateway, a Stripe gateway in
  an iPhone country with Card present still off (`terminal/config`'s `setup_gateways`), or — for an
  admin of a company with no Stripe gateway — a company in an iPhone country (`company_country`).
  Both keys are optional; an older server simply leaves them out. The server's `enabled` is the
  release flag.
- **Apple's button from the first frame.** The view model knows it is Tap to Pay on iPhone before
  anything loads (`offersTapToPayOnIPhone`, the invoice action's own test), so the greyed
  "Collect card payment" never draws, and a config that fails to load keeps Apple's button — a
  press loads it again and carries on.
- **The invoice's action is Apple's button too** (5.3): `showCollectCardPaymentScreen` opens with
  `pressOnOpen`, so whatever setup is missing runs at once (the location explanation, Card
  present, Apple's terms). A reader that only had to connect goes straight on to the card —
  Apple's sheet shows the amount, and nothing is charged until a card is read. After the terms or
  the education it waits for a press: "Ready. Press Tap to Pay on iPhone to take the payment."
  Opened any other way the screen only looks (`permissionStatus`, Card present) and connects
  without the terms when location is already allowed.
- **Location.** Location Services off for the whole device (`locationServicesEnabled`) has its own
  words, apart from the app's own permission being blocked; both offer Settings, and a return
  from the background looks again (`appResumed`).
- **The button is never greyed out** (5.3). A press, in order: Card present (an admin turns it on —
  type 32 in the gateway's `fees_and_limits`, saved on the freshly fetched gateway through the
  outbox, then `refreshConfig`; anyone else's press asks the server again first, then reads "Ask an
  admin to turn on Tap to Pay on iPhone", 3.8.1); location services and location permission (the app's own "Allow location access" first,
  then iOS's prompt; Settings when blocked); the Stripe Location (an admin's is created silently);
  then `ensureTapToPay(admin: isAdmin)` straight away, so Apple's terms open. Meanwhile the screen
  shows "Getting Tap to Pay on iPhone ready…" with the reader's own progress (5.7, 3.9.1). Once
  set up, the payment waits for another press.
- **A press while quoting is held**: one at most, run when the figures arrive, and dropped by any
  edit (typing included). A press that commits a changed amount quotes it, then collects. Nothing
  else about the money changes.
- **`ensureTapToPay` is single-flight per account and mode.** The account is company, gateway and
  Location: a call for the same shares the one under way (a quiet call also shares an admin one);
  any other waits for every connect before it, then runs its own — an admin call after a quiet one
  runs again so the terms can open, and a screen's call for another gateway never takes a
  warm-up's reader. Its session and company are taken when it is called: it waits out a `reset()`
  under way, and a reset or a company switch meanwhile ends it (`sessionExpired`) before anything
  connects. A Bluetooth connect in Device Settings holds the warm-up and lets go of a Tap to Pay
  reader first (`releaseTapToPay`).
- **Linked or not is Apple's answer** (1.6): `tapToPayLinked` lives in memory only, is dropped on a
  resume and a reset, and a press always asks again.
- **Warm-up** (1.5, 5.6): `warmUpAfterFirstFrame` after every company activation (chained after
  `reset()` in `Services.build`), and `onResumed` from `TerminalLifecycleObserver` on a return from
  the background. It stops at the first check that fails — a capable iPhone on iOS 17.6+, the
  platform, a usable gateway in an iPhone country with a Location, location already allowed,
  nothing connected or connecting, no collect screen open (`holdWarmUp`), an account not known to
  be unlinked — and never prompts, shows a sheet or toasts. It asks for the config through
  `ensureConfig`, so an older server's 404 is never asked again and a failed fetch waits its minute.
- **An out-of-date iOS keeps its Bluetooth reader.** Below 17.6 a phone that has used a Bluetooth
  reader here takes cards with it (`terminalReaderChoice(osUpdateRequired:)`); one that hasn't keeps
  Tap to Pay on iPhone, which says to update.
- **Education never covers the closing terms sheet**: after the terms it waits for the app to be back
  in front and a moment more, however soon the reader turns ready.
- **Latency** (5.6) is logged by `TapToPayLatency`: the press, the sheet requested (the read
  starts), and the sheet shown (the app goes inactive under it). Pre-creating PaymentIntents is
  deferred unless the p90 on a phone is over a second.
- **No surcharge.** Stripe's iOS SDK can't put one on Apple's sheet, so the switch and the
  surcharge setup are replaced by "Surcharges aren't available with Tap to Pay on iPhone yet." and
  `apply_fee` is never sent.
- **`card_present_help`** never mentions Android on iOS or macOS (`card_present_help_apple`).

## Tap to Pay on iPhone can be turned on outside checkout

App Review 3.4, 3.6 and 3.9 want a way to turn it on away from an invoice, an invitation to try
it once it works, and the offer at the end of onboarding. iPhone only, like everything above.

- **`TapToPayEnableScreen`** (`showTapToPayEnableScreen`, a full-screen step on the root
  navigator, never a saved route) runs the collect button's steps through the same helpers
  (`tap_to_pay_setup.dart`: `requestTapToPayLocation`, `enableCardPresent`; then
  `TerminalController.ensureTapToPay`): Card present (an admin's), location (the shared
  `LocationPreAlertDialog`, then iOS; Open settings when blocked or Location Services are off, and
  it runs again on the way back), the Stripe Location, Apple's terms, the education — then Ready,
  "You're ready to take cards", with [Done] [Open invoices], and `DevicePrefKeys.tapToPayAnnounced`
  (account scope) — only the one-time announcement flag (the awareness modal's), never "it works
  here": that is per company, `tapToPayReadyFor(companyId)` (this company's linked answer, or a
  reader connected for it). An iOS Apple wants updated fails first, with the update message,
  before any prompt or Card present change; Retry looks again. The intro lists only the steps still needed; errors stay inline with Retry; a
  member with Card present off, or an unlinked account, is told to ask an admin. Close is quiet: the
  connect lives in the controller, so setup carries on.
- **Device Settings → Card readers** draws `TapToPayTile` on an iPhone that can: Checking, Not set
  up [Turn on], the reader's progress while it gets ready, Ready [How to use], ask an admin, or
  update iOS — from `TerminalController` (`tapToPayConnecting` notifies). Turn on shows only to
  someone who can finish it (`canSetUpTapToPayOnIPhone`, which includes the Pro plan); anyone else
  reads the status and the server's reason below. Before general availability (no entitlement)
  there is still no row.
- **The setup checklist's optional row**, "Set up Tap to Pay on iPhone", is last and never counted:
  offered only where `canSetUpTapToPayOnIPhone` holds (the invoice action's facts without an
  invoice), done once it works for this company, and it retires with the card. The dashboard asks
  for `terminal/config` only on an iPhone that can take Tap to Pay on iPhone.
- **The end of onboarding.** Only on an iPhone that can take Tap to Pay on iPhone, for someone who
  can finish it (`watchesStripeConnect`), Stripe Connect opens in the in-app browser — everyone
  else keeps the system browser, unchanged. The app polls `company_gateways`
  (`StripeConnectWatcher`, every 3 s for up to 10 minutes, stopping when the screen leaves or the
  company changes) because the browser says nothing when it's done. It compares id → `updatedAt`,
  since the server reuses an existing Stripe Connect gateway; on a change it closes the browser and
  offers the enable screen (`offerTapToPayOnIPhone`, which does nothing — no call, no toast — unless
  the phone can and the user is eligible). A new Stripe gateway saved with API keys gets the same
  offer once the outbox has sent it and the server's config lists that gateway, while the user is
  still on the gateways' pages; an edit never does. While Stripe is still reviewing the account
  (`card_payments_active` false, also read from `setup_gateways` when the server sends it), the app
  says approval is pending instead.
- **Education below iOS 18** (no `ProximityReaderDiscovery`) is the app's own dialog: contactless
  cards and digital wallets, PIN entry and the PIN screen's accessibility options except in Japan
  and Taiwan (the Stripe account's country), and Apple's fixed fallback sentence ("Some cards are
  not able to complete contactless transactions using a PIN…") in every region. The Marketing
  Toolkit's own wording replaces the first two paragraphs when it arrives.

Stripe takes no payment with device location services off (`locationServicesEnabled`). Whether
Stripe accepts iOS's reduced ("approximate") accuracy is untested — check on a phone.

## What the SDK costs the packaging

It ships to every store user, whether or not they ever take a card.

- **minSdk 26 for every build**, F-Droid's included (`android/app/build.gradle.kts`, never below
  Flutter's own floor; `packages/store_services/android/build.gradle`).
- **Merged permissions would make hardware required.** The SDK's `BLUETOOTH*`,
  `ACCESS_*_LOCATION`, `ACCESS_WIFI_STATE` and Tap to Pay's `READ_PHONE_STATE` imply the bluetooth,
  location, wifi and telephony features as required, and Play then hides the app from devices
  without them (checked with `aapt2 dump badging` on a release APK).
  `packages/store_services/android/src/main/AndroidManifest.xml` marks all four `required="false"`.
  Telephony was already implied by the app's own `CALL_PHONE`, so this also makes the store build
  installable on Wi-Fi-only tablets for the first time.
- **Play's listing changes with this release**: new dangerous permissions (precise and approximate
  location, Nearby devices, `READ_PHONE_STATE`) and, once the SDK starts, what it sends Stripe
  (location, a device id, network details, its own crash diagnostics). Update Data safety, and the
  Financial features declaration, before a build with this reaches Play.
- **`gwpAsanMode`.** Tap to Pay's AAR sets `android:gwpAsanMode="always"` on `<application>`, which
  would apply to the whole app and turn any native heap bug anywhere into a crash. The app manifest
  puts it back to `default` (`tools:replace`). Whether Stripe's Tap to Pay checks need "always" is
  untested — check on a phone before the feature ships.
- **The `:stripetaptopay` process.** Tap to Pay's AAR runs an activity there. Content providers
  without a process (ML Kit's, Sentry's, androidx.startup) stay in the main process; only Stripe's
  `TtpContentProvider` runs there. In the main process Stripe's `PaymentMethodSpecsContentProvider`
  starts at every launch, and mek registers lifecycle observers when the activity attaches — both
  cheap.
- **Backup.** Stripe's device id (`stripe_terminal_shared_prefs.xml`), its offline database and
  the Tap to Pay kernel's prefs (`com.visa.vac.tc.sharedPref.xml`) belong to one phone and its
  keystore, so `backup_rules.xml` and `data_extraction_rules.xml` leave them out.
- **Size.** About 19 MB of native code and assets per universal APK (7–8 MB of it per ABI) and
  about 12 MB of dex, roughly +24 MB installed on an arm64 phone. On iOS `StripeTerminal.framework`
  is a 34 MB dynamic framework, loaded at every cold start.
- **R8.** Stripe's consumer rules keep everything under `kotlin.**`, `kotlinx.**`, `okhttp3.**`,
  `okio.**`, `com.google.gson.**`, `dagger.**`, `javax.**` and `com.squareup.**`, and rename every
  frame's source file to `SourceFile` — app-wide, not just for Stripe — so release stack traces need
  the mapping file. `packages/store_services/android/consumer-rules.pro` adds one `-dontwarn`:
  `play:review-ktx` (from `in_app_review`) references
  `com.google.android.gms.common.annotation.NoNullnessRewrite`, which nothing here defines, and
  Stripe's `-keepattributes *Annotation*` made R8 resolve it and fail the release build.
- **iOS** needs `NSBluetoothAlwaysUsageDescription` and `NSLocationWhenInUseUsageDescription`
  (`Info.plist`, `InfoPlist.xcstrings`) as soon as the SDK is linked. Stripe's privacy manifest
  declares coarse location and product interaction as collected, so the App Store privacy answers
  change too. `UIBackgroundModes` has `bluetooth-central`: the SDK checks for it before it discovers a
  Bluetooth reader, and it keeps the reader connected in the background. App Review asks why, so the
  submission notes say: in-person card payments with a Stripe Bluetooth reader, and give a demo path
  (a test-mode gateway with Card present on, and the Debug Panel's simulated reader).
- **USB.** Plugging a Stripe reader in over USB offers to open the app (Stripe's
  `UsbEventReceiverActivity`). Harmless.
- **F-Droid** drops the SDK with the rest of the store graph (`docs/fdroid.md`); the CI classpath
  check also greps for `com.stripe`.
- **The fork.** mek 5.7.3 has no `collectPaymentMethod` / `confirmPaymentIntent`, which the
  surcharge flow needs (read the card, let the server decide, then charge). The app pins
  `hillelcoren/mek-packages@8f815343` (BreX900/mek-packages#171, which also fixes an Android cancel
  that never answered, plus two fixes of ours: a re-created engine's token handler, and an iOS
  cancel race) until a release ships it — `docs/upstream-workarounds.md` entry 19.

## Secrets never reach a log

A PaymentIntent client secret (`pi_…_secret_…`) and a connection token (`pst_live_…` /
`pst_test_…`) are redacted by `redact()` (`lib/app/logging.dart`) by key and by value — quoted,
bare or percent-encoded. The console and the diagnostics log, the debug-capture ring and Sentry all
go through it. In Sentry (`runWithCrashReporting`'s `redact`) it runs over each breadcrumb as it is
recorded and, before an event leaves, over its message, exception values, breadcrumbs and contexts;
an event it can't scrub is dropped. The native SDKs' own network breadcrumbs and failed-request
events are off: they record other SDKs' traffic, Stripe's among them, and never pass those
callbacks. Native crash reports still carry the breadcrumbs synced to the native scope, which is
why scrubbing happens when a breadcrumb is recorded. `test/app/logging_redact_test.dart` pins the
shapes.
