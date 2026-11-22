# Free plan limits: saying them before anyone meets them

Companion to CLAUDE.md § Strict rules. CLAUDE.md is at its size cap, so the rule below has no bullet there yet; this doc carries it, and what the hosted Free plan limits are, where the server enforces them, where the app says so, and why the count comes from the server.

The previous app's one-star reviews were mostly people surprised that it was not really free: a sixth client was refused, and one reviewer with eleven clients (a plan that had lapsed) was told they had "reached a 5 client limit" with no way forward. This app says the limits plainly, before they bite, and never as a dead end.

| Piece | File |
|---|---|
| Who is limited, the quota, a hosted trial's end, the 422 match (pure) | `lib/domain/upgrade/client_limit.dart` |
| The count (server total + queued creates) | `lib/domain/upgrade/client_usage.dart` (`Services.clientUsage`, provided as `ClientUsage?` by `main.dart`) |
| The dialog, the gate, the list line, the form banner | `lib/ui/features/clients/widgets/client_limit.dart` |
| Signup line | `lib/ui/features/auth/views/signup_screen.dart` |
| Plan screen card and trial line | `lib/ui/features/settings/views/basic/account_management/plan_screen.dart` |
| First-run mention | the checklist's clients row, `lib/ui/features/dashboard/widgets/setup_checklist_card.dart` |

## The server's rules

- **Clients.** `CreateAccount` sets `accounts.hosted_client_count` to `config('ninja.quotas.free.clients')`, 5. `StoreClientRequest` adds `CanStoreClientsRule` on the `id` key when `Account::isFreeHostedClient()`; the rule passes while `$company->clients()->count()` is below the cap, and `clients()` is `withTrashed()`, so **archived and deleted clients count too**. A refusal is a 422 with `errors.id = [texts.limit_clients]` ("You've hit the :count client limit on Free accounts…"), translated into the user's language. The import is capped as well (`ValidatesClientImportLimit`).
- **Who is free.** `isFreeHostedClient()`: hosted only, and a plan that is `free` / blank, or whose `plan_expires` is more than 12 hours past. `getPlan()` blanks the slug once `plan_expires` is past, which is how a lapsed plan reaches the app.
- **Companies.** `quotas.free.max_companies` is 1; `hosted_company_count` carries it (`AuthSession.canAddCompany` already gates New Company on it).
- **Emails.** About 20 a day (`Account::getDailyEmailLimit`). The app does not say this: it reads no `email_quota`, and the free figure changes after an account's first two weeks.
- **Self-hosted** has no client limit at all.

## A hosted Free plan's client cap is read only through `freePlanClientLimit` / `ClientUsage` (the server's total plus queued creates, never a Drift count), is never shown to self-hosted, and every blank New client passes `interceptNewClientAtLimit` first

**Who.** `freePlanClientLimit(session)` mirrors `isFreeHostedClient()`: hosted, and `!isPaidPlanSlug || isPlanExpired`. It is null on self-hosted, on a live paid plan or trial, and when `hosted_client_count` is 0 (unknown). Every surface draws nothing when it is null, so nothing here can reach a self-hosted session.

**The count is the server's.** `ClientUsage` asks `GET /clients?status=active,archived,deleted&per_page=1` for `meta.pagination.total` (`BaseEntityApi.count`), the same set `CanStoreClientsRule` counts. A Drift row count would under-report: lists page in fifty at a time, and a fresh device holds a handful. To that it adds the client creates still `pending` / `in_flight` in the outbox (`OutboxDao.watchQueuedCreateCount`), so an offline sixth client is stopped before it becomes a dead row. When that number falls, a create has reached the server, and the total is asked for again. It asks once per session key (server, account, company, user, cap), again on the clients list or Plan screen when older than a minute, and never for a session without a cap.

**Unknown never blocks.** Offline before the first answer, or a failed request, leaves the quota null and New client goes through as it always did. The server's 422 is still behind it, and it is handled (below).

**The gate.** `interceptNewClientAtLimit(context)` reads the held quota synchronously (no request, so the tap stays instant) and, at or over the cap, opens the Upgrade dialog instead of the form. It is called from `goToCreateRoute` (the FAB, `N`, the dashboard's `+` sheet and checklist, the sidebar's hover `+`), the list's wide New button (`EntityListTopRow`), the shell's create shortcut, Clone, and `showClientCreateDialog` (the pickers' inline create). Any other way in (a deep link, the command palette, a group's Clients tab) lands on the form, where `ClientLimitFormBanner` says the same thing with Upgrade. A new create path for clients must call the gate.

**Over the cap.** An account can hold more clients than the cap: a paid plan or trial lapsed after they were added. `ClientQuotaState.overLimit` words it as "You have 11 clients. The Free plan allows 5, so your existing clients are kept, and adding more needs an upgrade." Never "11 of 5", never a negative remainder. Its Upgrade is an ordinary free-account Upgrade: the billing portal off the stores, the purchase sheet for the owner on a store build (`client_limit_test.dart` pins both).

**The 422.** `isClientLimitRejection` matches the `id` key, never the translated text. The new-client form shows `ClientLimitFormBanner` with Upgrade under the rejection banner (which keeps Retry and Discard), including when a dead offline create is reopened. The inline-create dialog, which has no `id` field to show the error on, opens the Upgrade dialog.

**Upgrade** always goes through `launchUpgrade`, so a store build never links to an outside purchase.

## A hosted trial, and how the app recognises one

A hosted trial is `plan: pro`, `trial_started`, and `plan_expires` 14 days on (`NinjaPlanController::finalizeTrialAccount`). The transformer sends `trial_days_left` as a literal 0 on hosted and never sends `is_trial`, so `AuthSession.isTrial` cannot see it (a separate, known defect; `trial_footer.dart` explains). `hostedTrialEndsOn` reads the shape instead: a live pro slug with `trial_started` and a `plan_expires` no more than `kHostedTrialMaxDays` (21) after it. A plan paid after the trial moves `plan_expires` a month or more on and stops matching. During the trial the account is not limited; the Plan screen says "Your Pro trial ends on <date>. Without a paid plan after that, the Free plan allows 5 clients." The wording allows for the card on file: hosted bills the trial's recurring invoice at its end, so the cap applies only if that does not happen.

## Where it is said

- **Signup** (hosted-only by construction): "Free plan: up to 5 clients and one company. Upgrade any time for unlimited clients." There is no account yet, so the figure is `kFreePlanClientLimit`, which mirrors `config/ninja.php`.
- **First run**: the dashboard checklist's clients row adds "The Free plan includes 5 clients." while that step is open. A new email sign-up gets `/setup` and the checklist, not the Welcome (docs/first-run-welcome.md), so the checklist is the first-run spot.
- **Plan screen**: a "Free plan limits" card with "3 of 5 free clients used", a bar, the companies, and "Archived and deleted clients count toward the limit."
- **Clients list**: a quiet line above the list, "3 of 5 free clients used · Upgrade", tinted only at the cap. Not over a group's Clients tab or an embedded list.

Tests: `test/domain/upgrade/client_limit_test.dart` (who, quota, trial, 422 key, the session field, Upgrade for a lapsed account), `test/domain/upgrade/client_usage_test.dart` (server total, queued creates, refetch, company switch), `test/ui/features/clients/client_limit_test.dart` (the gate, the dialog, the list line).
