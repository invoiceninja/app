# Free plan limits: saying them before anyone meets them

Companion to CLAUDE.md § Strict rules. CLAUDE.md is at its size cap, so the rule below has no bullet there yet; this doc carries it, and what the hosted Free plan limits are, where the server enforces them, where the app says so, and why the count comes from the server.

The previous app's one-star reviews were mostly people surprised that it was not really free: a sixth client was refused, and one reviewer with eleven clients (a plan that had lapsed) was told they had "reached a 5 client limit" with no way forward. This app says the limits plainly, before they bite, and never as a dead end.

| Piece | File |
|---|---|
| Who is limited, the quota, a hosted trial's end, the 422 match (pure) | `lib/domain/upgrade/client_limit.dart` |
| The count (server total + queued creates − queued purges and merges) | `lib/domain/upgrade/client_usage.dart` (`Services.clientUsage`, provided as `ClientUsage?` by `main.dart`) |
| The dialog, the gates (New, the form's Save, an import's 422), the list line, the form banner | `lib/ui/features/clients/widgets/client_limit.dart` |
| Signup line | `lib/ui/features/auth/views/signup_screen.dart` |
| Plan screen card and trial line | `lib/ui/features/settings/views/basic/account_management/plan_screen.dart` |
| First-run mention | the checklist's clients row, `lib/ui/features/dashboard/widgets/setup_checklist_card.dart` |

## The server's rules

- **Clients.** `CreateAccount` sets `accounts.hosted_client_count` to `config('ninja.quotas.free.clients')`, 5. `StoreClientRequest` adds `CanStoreClientsRule` on the `id` key when `Account::isFreeHostedClient()`; the rule passes while `$company->clients()->count()` is below the cap, and `clients()` is `withTrashed()`, so **archived and deleted clients count too**. A refusal is a 422 with `errors.id = [texts.limit_clients]` ("You've hit the :count client limit on Free accounts…"), translated into the user's language. The import is capped as well (`ValidatesClientImportLimit`).
- **Who is free.** `isFreeHostedClient()`: hosted only, and a plan that is `free` / blank, or whose `plan_expires` is more than 12 hours past. `getPlan()` blanks the slug once `plan_expires` is past, which is how a lapsed plan reaches the app.
- **Companies.** `quotas.free.max_companies` is 1; `hosted_company_count` carries it (`AuthSession.canAddCompany` already gates New Company on it).
- **Emails.** About 20 a day (`Account::getDailyEmailLimit`). The app does not say this: it reads no `email_quota`, and the free figure changes after an account's first two weeks.
- **Per company.** The rule counts `$company->clients()`, so each company of an account (a lapsed plan can hold several) has its own 5. The app counts the active company's.
- **Only a purge frees a place.** Archive and delete keep the row (`withTrashed`); a purge (`ClientRepository::purge`) and a merge (`Merge.php`, the merged-away client) `forceDelete` it. A purge also force-deletes the client's invoices, payments, quotes, credits, tasks and expenses.
- **A missing cap refuses everything.** `hosted_client_count` is nullable with no default, and `CreateAccount` is the only writer. The transformer sends a null as 0, and `count < 0` (or `< null`) never passes, so such a free account cannot add any client. Measured 2026-11-23 on staging: `large@example.com` (seeded by `ninja:create-test-data`) is `plan: ''`, `hosted_client_count: 0`, 4,523 clients; `small@` and `medium@` are `enterprise` to 2032 with `hosted_client_count: 0`. The app shows no cap for a 0 (unknown), and a refusal there says the server's own words with Upgrade.
- **Who sees the count.** The list route narrows a user without `view_client` to their own and assigned clients, so such a user's total under-reports. Under-reporting never blocks; the 422 is still behind it.
- **The 12 hours.** `getPlan()` blanks the slug the moment `plan_expires` passes, while `isFreeHostedClient()` waits 12 hours more, and `isPlanExpired` waits for the next UTC day. A session refreshed in that window can read Free while the server still takes a sixth client, or the reverse; the 422 and the gate's refetch settle it.
- **Self-hosted** has no client limit at all.

## A hosted Free plan's client cap is read only through `freePlanClientLimit` / `ClientUsage` (the server's total plus queued creates, never a Drift count), is never shown to self-hosted, and every blank New client passes `interceptNewClientAtLimit` first

**Who.** `freePlanClientLimit(session)` mirrors `isFreeHostedClient()`: hosted, and `!isPaidPlanSlug || isPlanExpired`. It is null on self-hosted, on a live paid plan or trial, and when `hosted_client_count` is 0 (unknown). Every surface draws nothing when it is null, so nothing here can reach a self-hosted session.

**The count is the server's.** `ClientUsage` asks `GET /clients?status=active,archived,deleted&per_page=1` for `meta.pagination.total` (`BaseEntityApi.count`), the same set `CanStoreClientsRule` counts. A Drift row count would under-report: lists page in fifty at a time, and a fresh device holds a handful. To that it adds the client creates still `pending` / `in_flight` in the outbox and takes off the purges and merges there (`OutboxDao.watchQueuedCountChanges`), so an offline sixth client is stopped before it becomes a dead row, and a client purged offline makes room for one queued behind it (the outbox sends them in order). When any of those rows leaves the outbox the total is asked for again. It asks once per session key (server, account, company, user, cap), again on the clients list or Plan screen when older than a minute, again when the gate refuses with a count older than ten seconds, and never for a session without a cap.

**Asked with the company's own token, after the switch.** `AuthRepository` sets the session and then the credentials in one synchronous run, so a request sent from the session listener carried the last company's token, and the answer was filed under the new company: switching from a company at 5 to an empty one blocked the empty one. The fetch now runs in a microtask, `Services` refuses to ask when the credentials name another company, and `quota` reads null between a session change and `ClientUsage`'s own listener (`client_usage_test.dart` pins all three).

**Unknown never blocks.** Offline before the first answer, or a failed request, leaves the quota null and New client goes through as it always did. The server's 422 is still behind it, and it is handled (below).

**The gate.** `interceptNewClientAtLimit(context)` reads the held quota synchronously (no request, so the tap stays instant) and, at or over the cap, opens the Upgrade dialog instead of the form. It is called from `goToCreateRoute` (the FAB, `N`, the dashboard's `+` sheet and checklist, the sidebar's hover `+`), the list's wide New button (`EntityListTopRow`), the shell's create shortcut, Clone, a group's Clients tab, and `showClientCreateDialog` (the pickers' inline create). Any other way in (a deep link, the command palette) lands on the form, where `ClientLimitFormBanner` says so with Upgrade, and Save goes through `confirmNewClientSave`: a create at the cap opens the dialog and is not queued, and the form keeps what was typed. Before that, such a form queued a create the server refused, the dead row the feature exists to prevent. A new create path for clients must call the gate. The banner is not shown on the form whose own save reached the cap (its create is counted while it saves).

**An import.** `ValidatesClientImportLimit` refuses the whole file under `files.client` or `column_map.client`. For a session with a cap, `showImportClientLimit` opens the same dialog with "This import would take you past the 5 clients the Free plan allows, so nothing was imported. Upgrade to import them all." It used to be a toast of the server's "You've hit the 5 client limit", wrong for a file that only would have, and with no way on.

**Over the cap.** An account can hold more clients than the cap: a paid plan or trial lapsed after they were added. `ClientQuotaState.overLimit` words it as "You have 11 clients. The Free plan allows 5. All your clients are kept. Upgrade to add new ones." Never "11 of 5", never a negative remainder. Its Upgrade is an ordinary free-account Upgrade: the billing portal off the stores, the purchase sheet for the owner on a store build (`client_limit_test.dart` pins both).

**The 422.** `isClientLimitRejection` matches the `id` key, never the translated text. The new-client form shows `ClientLimitFormBanner` with Upgrade under the rejection banner (which keeps Retry and Discard), including when a dead offline create is reopened. The inline-create dialog, which has no `id` field to show the error on, opens the Upgrade dialog. Where the cap is unknown (`hosted_client_count` 0), both say the server's own message instead of the app's sentence.

**Upgrade** always goes through `launchUpgrade`, so a store build never links to an outside purchase.

## A store build that sells nothing still states every limit, and only drops the Upgrade

While the hosted service does not sell in-app to the account (`purchasesWithheld`, docs/in-app-purchases.md), a store build may not show Upgrade or ask anyone to buy. The limit stays as plain as before, so nobody meets it as a surprise; only the sentence after it and the button go:

- the list line: "3 of 5 clients on the Free plan", no Upgrade button;
- the dialog: "You have used all 5 clients on the Free plan." (`free_plan_client_limit_reached_info`), the archived-and-deleted note, **Close** only (the primary, so Enter takes it);
- the form notice: the same sentence, no Upgrade (Save still opens the dialog and is not sent);
- over the cap: "You have 11 clients. The Free plan allows 5. All your clients are kept." (`free_plan_clients_over_info`);
- the import: "…so nothing was imported." (`free_plan_import_too_many_info`);
- the Plan tab's Free plan limits card is unchanged; the signup note on a store build is "Free plan: up to 5 clients and one company." (`free_plan_signup_note_info`);
- the company limit: New company is disabled and says "You have reached the Free plan's company limit."

A cap the app does not know still shows the server's own `limit_clients` message, which may say "upgrade": it is the server's text, not ours. Tests: `test/ui/features/store_purchases_withheld_test.dart`.

## A hosted trial, and how the app recognises one

A hosted trial is `plan: pro`, `trial_started`, and `plan_expires` 14 days on (`NinjaPlanController::finalizeTrialAccount`). The transformer sends `trial_days_left` as a literal 0 on hosted and never sends `is_trial`, so `AuthSession.isTrial` cannot see it (a separate, known defect; `trial_footer.dart` explains). `hostedTrialEndsOn` reads the shape instead: a live pro slug with `trial_started` and a `plan_expires` no more than `kHostedTrialMaxDays` (21) after it. A plan paid after the trial moves `plan_expires` a month or more on and stops matching. During the trial the account is not limited; the Plan screen says "Your Pro trial ends on <date>. Without a paid plan after that, the Free plan allows 5 clients." The wording allows for the card on file: hosted bills the trial's recurring invoice at its end, so the cap applies only if that does not happen.

## Where it is said

Reviewed 2026-11-23 against goldens on phone, tablet and desktop, light and dark, German at 1.6x and Arabic: calm, never red, Upgrade always at the end of the line or as the dialog's primary.

- **Signup** (hosted-only by construction): "Free plan: up to 5 clients and one company. Upgrade any time for unlimited clients." There is no account yet, so the figure is `kFreePlanClientLimit`, which mirrors `config/ninja.php`.
- **First run**: the dashboard checklist's clients row adds "The Free plan includes 5 clients." while that step is open. A new email sign-up gets `/setup` and the checklist, not the Welcome (docs/first-run-welcome.md), so the checklist is the first-run spot.
- **Plan screen**: a "Free plan limits" card with "3 of 5 clients on the Free plan", a bar, the companies, and "Archived and deleted clients count toward the limit. Only purging a client frees its place, and purging also deletes its invoices and payments." This is the only place purge is mentioned: in the add-a-client flow it would invite deleting invoices to make room.
- **Clients list**: a quiet line above the list, "3 of 5 clients on the Free plan", with an accent Upgrade button at its end (44 px on touch), tinted only at the cap. Shown only within `kClientUsageLineFromRemaining` (2) of the cap: further off, the surfaces above have said it, and a line on every visit was clutter on a phone. Not over a group's Clients tab or an embedded list. ("free clients used" read as clients who are free.)
- **The dialog**: title "Client Limit" (the server's translated string), "You have used all 5 clients on the Free plan. Upgrade to add more.", the archived-and-deleted note, Close and Upgrade. Close, not Cancel: nothing was started.
- **The form notice**: "You have used all 5 clients on the Free plan. Upgrade to save this client.", Upgrade in accent ink.

Open: Transifex's Arabic `upgrade` is "يرقي" (a third-person verb, "he upgrades"), and `plan` / `free` read as the verb "plans" and "free" as in liberty, the "100% free" misreading. They are Transifex keys, so `_app_pending` cannot override them; they need fixing upstream.

Tests: `test/domain/upgrade/client_limit_test.dart` (who, quota, trial, 422 key, the session field, Upgrade for a lapsed account), `test/domain/upgrade/client_usage_test.dart` (server total, queued creates, purges and merges, refetch, company switch and the token race), `test/data/db/dao/outbox_dao_test.dart` (the queued counts), `test/ui/features/clients/client_limit_test.dart` (the gate, the form's Save, the form notice, the dialog, the import, the list line and its threshold), `plan_status_card_test.dart` (the Plan card and the trial line).
