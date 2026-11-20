# In-app purchases

Companion to CLAUDE.md § Strict rules. How the store builds sell a hosted plan in-app and deliver it to the account: which builds sell, what the app waits for before it posts or finishes a purchase, which answers finish one, which key a purchase is posted under, and where the copy lives. The code is `lib/domain/upgrade/` (`store_build.dart`, `upgrade_route.dart`, `upgrade_launcher.dart`, `purchase_delivery.dart`, `purchase_service.dart`) over `StoreBilling` in `packages/store_services` (docs/fdroid.md for the FOSS twin).

## Store builds never link to an external purchase

A store build is `isStoreBillingBuild`: a store package build (`StoreReview.isStoreBuild`, false in the FOSS twin) on iOS, Android or macOS. Such a build may not send anyone to a purchase outside the store (App Store 3.1.1(a), Play Payments policy 4), so:

- `resolveUpgradeRoute` never answers `billingPortal` on a store build. A trial or a web-billed plan (`AuthSession.isWebBilled`) goes to the Plan screen, which says the plan is managed on the web, and every upgrade prompt (`PlanGateBanner`, `TrialFooter`, `PlanExpiredFooter`, the Plan card) shows that line with no button (`planManagedOnWeb`). A long-expired web plan has a blank slug and is a free account again: it is offered the purchase sheet.
- The white-label checkout, the PEPPOL credit packs and any off-origin page the DocuNinja embed hands over are refused when `isExternalPurchaseUri` says they sell something: Stripe's payment pages, the billing host (`kInvoiceNinjaBillingHost`), a client-portal subscription checkout, the pricing pages.
- Desktop, the web and the F-Droid / GitHub APKs keep the billing portal. An in-app plan is still managed only in its store there, and a lapsed one is not sold a web plan for `kIapRebuyAfter` (60 days) while the store may still renew it.
- `upgrade_launcher.dart` opens a server-sent portal URL only when it is http(s) (`isSafeWebUrl`).

Tests: `test/domain/upgrade/upgrade_route_test.dart`, `test/ui/features/settings/widgets/plan_gate_copy_test.dart`, `test/ui/features/settings/views/basic/account_management/plan_hosted_actions_test.dart`.

## Nothing is posted or finished until the config answers 200

`PurchaseDelivery` (built by `Services` on a store build only, and started at app launch so StoreKit hands over `Transaction.updates`) owns the hosted config, `GET kIapConfigPath`. It asks once per signed-in user (base URL and user id: a purchase goes to the user's own account, whichever company is active), keeps an answer that names an `account_key`, and asks again after any failure, after a sign-out and when the app returns to the foreground. The purchase sheet (`PurchaseService.loadConfig`) reads the same answer: there is no second request.

Until that answer is a 200 with an `account_key`, nothing paid is posted and nothing is finished with the store. A 404 (a server without the route), a 5xx, no network or an answer without `account_key` leaves every purchase unfinished, said as `retryLater`. `purchases_enabled` gates only the sale (the sheet fails closed without it, a UUID `app_account_token` and an `account_key`); a purchase already paid for is always delivered, and Restore is never gated.

Before posting, a purchase is skipped, and left unfinished, when its own account token (Apple's `appAccountToken`, Play's `obfuscatedAccountId`, read from the store's transaction JSON) is set and is not the config's `app_account_token`: it was bought for another account on the same store account. A revoked or upgraded-away Apple transaction is finished without a post and without a word. A purchase with no transaction id is never finished; Play's is posted by its purchase token alone.

A purchase not applied yet is swept again while the app runs, after 30 seconds, 2 minutes, then every 10 minutes (`kPurchaseRetryBackoff`), and on every return to the foreground (`PurchaseResumeObserver`). A Google acknowledgement Play did not confirm (`StoreBilling.completePurchase` answers false) is logged and swept again.

Tests: `test/domain/upgrade/purchase_delivery_test.dart`.

## Which answers finish a purchase

`POST kSubscriptionPath`:

| Answer | Apple | Google |
|---|---|---|
| 200 | finished, then `auth.refresh()` | acknowledged, then `auth.refresh()` |
| 409 / 422 with a final `reason` (`kFinalRejectionReasons`: `sandbox`, `expired`, `revoked`, `upgraded`, `linked`) | finished, the server's message shown | left unacknowledged, so Play refunds it |
| 409 / 422 with any other `reason` (`account`, `token_mismatch`, `no_token`, `unverified`) or none | left unfinished, the message shown | left unacknowledged |
| 403, 429, 5xx, a 400 entity-missing, no network | left unfinished and tried again | left unacknowledged and tried again |

Finished too early, a purchase the account never got is gone: StoreKit never hands back a finished transaction, and Play never refunds an acknowledged one.

## The delivery key is the config's account_key

Every delivery posts `key` = the config's `account_key`, exactly: the account the hosted service applies the user's purchases to. The session's account keys are never used for it (`AuthSession.userAccountKey` names only the realtime channel). The sheet sells only when that key is the active company's account key (`IapConfig.sellsTo`); with a company of another account active it says plans are applied to the user's own account and opens no store sheet.

## Where the translations live

The purchase copy is app-local, in `assets/i18n/_app_pending.json` (`store_*`, `plan_billed_in_app_store`, `plan_managed_on_web`, `in_app_purchases_unavailable`, `restore_purchases_help`), with each shipped locale's translation in `_app_pending_<locale>.json` (docs/translated-string-rendering.md). A store's own name appears only in the copy for that store's build (`storeOfBuild`): App Review rejects a build that names another platform's store.
