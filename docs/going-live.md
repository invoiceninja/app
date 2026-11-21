# Going live

Companion to CLAUDE.md § Release Notes. The checklist for taking the app out of beta on every store: the app changes that ship in the one launch release, the console step each store needs, and the decisions that sit outside the code. Tick items off here as they land. The deploy mechanics are in `docs/store-deployment-setup.md`, and its § 7 (Beta → GA flips) lists the beta-posture settings this checklist changes.

## Where each store stands

Updated 2026-11-12, after 5.1.25. Update this table whenever a store moves; the sections below hold the steps. The other goal running alongside is the Flutter 3.50 upgrade (`docs/upgrading-to-flutter-3-50.md` § Upgrade day, in order).

| Store | Production? | Ships to today | Next step |
|---|---|---|---|
| Flathub | ✅ since 5.1.23 (2026-11-10) | stable, as an update to v1's listing | the follow-ups in § Flathub |
| F-Droid | ✅ | f-droid.org | nothing until the app rename |
| Snap | ✅ since 5.1.25 (2026-11-13, revision 80) | `stable` and `edge`, replacing v1 | nothing until the app rename |
| Android (Play) | ❌ | Open testing | § Google Play |
| iOS | ❌ | TestFlight, external beta | § App Store (iOS and macOS) |
| macOS | ❌ | TestFlight | § App Store (iOS and macOS) |
| Windows | ❌ | Microsoft Store, Private audience | § Microsoft Store |
| Web | ❌ | built and checked by Deploy to Web; Pages and the release tarball wait on the Cloudflare project and the backend PR | `docs/web-deploy.md` § Going live |

Going live is one app release with the beta flag off, plus a store-console step on each store. Today every pipeline ships to testers: Play Open testing, TestFlight (iOS and macOS), and a restricted Microsoft Store listing. F-Droid, Flathub, the Snap and the GitHub Releases are already public.

On Play, the App Store and Microsoft the new app (`com.invoiceninja.admin`) has its own listing, so going live there leaves the v1 app (`com.invoiceninja.app`) untouched. **The Snap is the exception:** both apps are the `invoiceninja` snap, so releasing to `stable` replaces v1 for every snap user.

**The launch is decided (2026-11-19):** the new app goes live as its own listing on the App Store, Play and Microsoft; v1 is renamed **Invoice Ninja Legacy** (`IN Legacy` under the icon), carries a move prompt for about six months, and then retires (§ Sunsetting v1). A paid plan lives on the Invoice Ninja account, not in a store, so it carries over the moment someone signs in to the new app; v1's store subscriptions keep renewing on v1's records. The order of everything is § Launch day and § Sunsetting v1; normal beta releases keep going until three weeks before launch (§ Release freeze).

## App changes in the launch release

These ship together in one version to every store, so each store's first public build is already out of beta.

- [ ] Set `kAppIsBeta` to `false` in `lib/app/version.dart`. This switches on the store review prompt, which stays silent during the beta (`docs/review-prompt.md` § GA launch checklist).
- [ ] Set `kAppStoreId` in `lib/domain/review_prompt.dart`: the Apple ID in App Store Connect → App Information. iOS and macOS share one record.
- [ ] Swap the phone-app promo links from TestFlight and Play testing to the store listings (`docs/mobile-app-promo.md` § Swap the links at launch):
    - `kMobileAppIosUrl` → `https://apps.apple.com/app/id<number>`;
    - `kMobileAppAndroidUrl` → `https://play.google.com/store/apps/details?id=com.invoiceninja.admin`;
    - reword the `mobile_app_promo_testflight_step` and `mobile_app_promo_play_step` captions, and drop the "Beta" label.
- [ ] Give the web build's "other apps" banner its Windows link: set `kWindowsAppUrl` in `lib/domain/web_app_banner.dart` to `https://apps.microsoft.com/detail/$kMicrosoftStoreId` once the listing is Public. Its iPhone, Mac and Android links follow the promo's constants above.
- [ ] Rename the app from "Ninja Beta" to "Invoice Ninja":
    - `CFBundleDisplayName` in `ios/Runner/Info.plist` and `android:label` in `android/app/src/main/AndroidManifest.xml`;
    - drop " - Beta" from `msix_config` `display_name` in `pubspec.yaml` and from the `README.md` title;
    - update the v1 app's beta invitation (`kBetaAppNameMobile` in admin-portal) at the same time, since it names "Ninja Beta".
- [x] Snap: change `grade: devel` to `grade: stable` in `snap/snapcraft.yaml` (done 2026-11-12, ahead of the launch release, § Snap).
- [ ] Write the release notes, bump the version and run **Deploy to all** (`docs/release-notes.md`).

## Per-store steps

Each store needs its console step after the launch release is uploaded. Only the Snap and GitHub Releases need a workflow change.

### Google Play

`playstore.yml` releases to Open testing (`beta`) and can't reach production: the service account holds only "Release apps to testing tracks".

- [ ] Check that the store listing, Data safety, content rating and target audience are complete for `com.invoiceninja.admin`.
- [ ] Promote the launch release from Open testing to Production in the Play Console. Google reviews it.
- [ ] Optional: to release to production from CI, add `production` to the `track` options in `playstore.yml` and grant the service account "Release to production".

**In-app purchases (`com.invoiceninja.admin`):**

- [ ] The ten subscription products with v1's ids (Play ids are per app).
- [ ] Real-time developer notifications to the hosted billing topic, and the Play service account the hosted billing uses granted access to this package.
- [ ] App content: Data safety (crash logs, and the account-deletion web link reused from v1), App access (the review account), Financial features, Ads.
- [ ] Turn managed publishing on before the launch build is promoted, so it is held after review (§ Launch day).
- [ ] Check Play Console orders for this package from the beta: any real purchase was never applied to an account (the beta sent the wrong account field), so apply the plan or refund it by hand and tell the buyer.

### App Store (iOS and macOS)

`appstore-ios.yml` and `appstore-macos.yml` upload to TestFlight and never submit for review. iOS and macOS are one App Store record.

- [ ] Fill in the iOS version page in App Store Connect: screenshots, description, keywords, privacy details, and a demo login for the reviewer.
- [ ] Pick the launch build from TestFlight and Submit for Review.
- [ ] Do the same for the macOS version.
- [ ] Release each version once approved, or set it to release automatically.

**In-app purchases (the new record, iOS and macOS share it):**

- [ ] Try creating the product id `pro_plan` on the new record. If App Store Connect accepts it, keep v1's ten ids (`lib/domain/upgrade/purchase_service.dart`); if it refuses, the new app uses `v2_`-prefixed ids and the hosted billing strips the prefix.
- [ ] One subscription group with v1's levels and prices, attached to the launch version.
- [ ] App Store Server Notifications V2: the Production URL is the hosted billing endpoint (as on v1's record); set a **Sandbox** URL that is not production, on both records.
- [ ] Privacy Policy URL, and the Terms of Use link in the description (or a custom EULA); the description names the subscriptions; the subtitle never names the other app.
- [ ] App Privacy answers: crash data, contacts, photos, precise location (Tap to Pay), financial info, purchases, user content. Export compliance: the app encrypts its database (`sqlite3mc`), so answer the encryption questions deliberately and keep `ITSAppUsesNonExemptEncryption` in step.
- [ ] A review account on every submission of both apps: a hosted owner on the Free plan with one company, no two-factor, password login; reset it to Free before each submission.
- [ ] Sandbox-test buy, renew, change level, cancel (the plan stays until it expires), refund and Restore on iOS and macOS before submitting.

### Microsoft Store

`microsoft-store.yml` already publishes each build once Microsoft certifies it, to the restricted `InvoiceNinja.AdminPortal` listing (v1 is `InvoiceNinja.InvoiceNinja`). What restricts it is the **Audience**: Pricing and availability → Visibility → **Private audience**, the "Beta Testers" group. The submission API can't see the audience (its `visibility` is the Discoverability option and reads `Public` under a Private audience), so `tools/msstore_release_notes.py` can't check it; each CI submission copies the last, so the audience carries forward until someone changes it here.

- [ ] Partner Center → the app → Pricing and availability → Visibility → Audience: switch **Private audience** to **Public audience**. This is the Microsoft Store's go-live switch; nothing in CI makes it.
- [ ] Remove "Beta" from the Store listing name.
- [ ] The name: first ship v1's package as "Invoice Ninja Legacy" (reserved on 9N3F2BBCFDR6 before that build), then delete "Invoice Ninja" from 9N3F2BBCFDR6 and reserve it on 9NG93WNXN797 in one sitting; a deleted name is free to anyone at once.
- [ ] The description opens with "Requires an Invoice Ninja account (hosted or self-hosted)", lists the plans and their price range, and the submission declares the third-party purchase API (Stripe, desktop only).
- [ ] Dispatch the launch build with `publish_mode: Manual` (and `commit` ticked) so it waits for the launch-day click (`microsoft-store.yml`).

### Snap

Both apps are the `invoiceninja` snap, so this replaces v1 for every snap user.

v1's snap (admin-portal's `snap/snapcraft.yaml`, 5.0.204 on `stable`) plugs only `network`, `home` and `desktop`; it never used the keyring. A refresh to this app adds `password-manager-service`, which snapd doesn't auto-connect, so a build that needed that plug would have put every v1 user on the "Secure storage unavailable" screen. The database key now goes through the desktop's Secret portal instead, through the launcher `snap/local/keyring-backend` (`docs/setup.md` § Linux desktop / Snap). Docker has no AppArmor, so that was tested on the plugin's own code with a faked snap identity; the real snap is checked by the smoke test below.

- [x] Route the key through the Secret portal while the plug is unconnected (2026-11-12, in Docker on Ubuntu 22.04). An auto-connect request to the store is no longer needed.
- [x] Set `grade: stable`, so a tested `edge` revision can be promoted as it is.
- [x] Release it to `edge`: revision 80 (5.1.25), 2026-11-13.
- [x] Run **Snap smoke test** (`snap-smoke.yml`) on `edge`: on GitHub's Ubuntu 22.04 and 24.04 runners (real snapd and AppArmor) it checks a fresh install and a refresh from v1's `stable`, with no plug connected by hand. Run 43390912853 passed all four jobs: the plug unconnected, `default.keyring` written, the portal holding a secret for `snap.invoiceninja`, AppArmor denying only the Dart VM's harmless `/proc/sys/vm/max_map_count` read, and the sign-in screen on both launches.
- [x] Promote that revision: `snapcraft release invoiceninja 80 stable` (2026-11-13). To roll back, release revision 76 (v1, 5.0.204) to `stable`.
- [x] Make Deploy to all publish to `stable`: `snapcraft.yml` releases to `stable,edge`. A change to confinement, plugs or `snap/local/keyring-backend` is dispatched with `channels: edge` and passes `snap-smoke.yml` before it reaches `stable`.

### Flathub

**Flathub goes first** (decided 2026-11-08): the new app goes to Flathub straight into production, ahead of the other stores. Flathub's stable repo takes only stable software. It ships as an **update to v1's listing**, `com.invoiceninja.InvoiceNinja`, the way the Snap does (decided 2026-11-09, after the submission's reviewer asked for an ID named after the app: `docs/flatpak.md` § The Linux app ID is v1's Flathub ID). v1's Flatpak users are moved over by the update itself, and sign in again. **Hillel does every step here by hand.** Flathub's AI policy bars agents from its manifests and PRs, so an agent can explain a step but never take it. The background is in `docs/flatpak.md`.

- [x] Before launch: prove the offline build on a fork, for both arches, with `flatpak-builder-lint` clean (`docs/flatpak.md` § Submitting). Commit screenshots of the Flatpak and name them in the metainfo by URLs pinned to a commit SHA. Record the video.
- [x] Close the new-app submission (`flathub/flathub#11087`), since the app now ships under v1's ID. Closed 2026-11-09.
- [x] Cut a hand tag carrying the rename (`docs/flatpak.md` § Submitting), and open a PR on `flathub/com.invoiceninja.InvoiceNinja` that replaces v1's manifest with the from-source build of that tag. Drop `only-arches` from its `flathub.json` (this build has aarch64) and add `disable-external-data-checker`. The changed `finish-args` need a Flathub admin's approval on that PR, so justify each one there. Done 2026-11-09: tag `v5.1.23-flathub.2`, [com.invoiceninja.InvoiceNinja#31](https://github.com/flathub/com.invoiceninja.InvoiceNinja/pull/31).
- [x] Merge #31. Merged 2026-11-10.
- [ ] On a real x86_64 machine, install v1 from Flathub, update it to this app (the published build, or any test build's `.flatpakref` from flathubbot), and check that it launches to sign-in with its own dock icon and reopens without asking for the keyring again. Only an arm64 Docker run with v1-shaped leftovers has taken that path so far (2026-11-09).
- [ ] Add the update workflow to `flathub/com.invoiceninja.InvoiceNinja`: [#32](https://github.com/flathub/com.invoiceninja.InvoiceNinja/pull/32), open, then dispatch it once by hand and check it finds no update.
- [ ] Ask Flathub to enable auto-merge there: [flathub/flathub#11108](https://github.com/flathub/flathub/issues/11108), open. v1's verification already covers the ID, so `invoiceninja.com/.well-known/org.flathub.VerifiedApps.txt` needs no new token.
- [x] Set the repo variable `FLATHUB_ENABLED` to `true`, so Deploy to all follows each release onto Flathub (set 2026-11-10).
- [ ] Add the Flathub install link to `README.md`, and flip the Flatpak row in `FEATURES.md`.

### GitHub Releases

- [x] Releases are full releases: `--prerelease` is gone from `appimage.yml`, and every earlier release was flipped, v5.1.25 marked Latest (2026-11-13).

### F-Droid

Already public on f-droid.org: each tagged release reaches users once F-Droid's rebuild matches ours.

- [ ] Nothing beyond the app-name change. The listing title (`fastlane/metadata/android/en-US/title.txt`) already reads "Invoice Ninja".

## One-click production releases

Today one **Deploy to all** dispatch ships every store to its testing channel with no manual step: Play Open testing (track and rollout chosen in the dispatch form), TestFlight (built, What to Test set, added to "Beta - External" and submitted for beta review by `tools/testflight_release.py`), the restricted Microsoft Store listing (release notes set and committed by `tools/msstore_release_notes.py`), and to production on F-Droid, Flathub, the Snap (`stable`) and a GitHub Release marked Latest. The decision (2026-11-08) is to keep it that way until launch, then make the same single dispatch publish to production. That needs:

- [ ] **Play:** grant the service account "Release to production" (Play Console → Users and permissions), add `production` to `playstore.yml`'s `track` options and to Deploy to all's `play_track`, and make it the default. The `play_rollout` input already stages it.
- [ ] **App Store (iOS and macOS):** after the first version has been submitted and approved by hand (Apple needs its screenshots, description, privacy answers and age rating once), extend `tools/testflight_release.py` or add a sibling to: create the App Store version for the release, attach the build, set "What's New in This Version" from the same digest, and submit it for review with release-after-approval — plus a dispatch input choosing phased release (iOS, 7 days) or everyone at once.
- [x] **GitHub Release:** `--prerelease` dropped from `appimage.yml`, so the Release is marked Latest (2026-11-13).
- [ ] **Microsoft Store:** switch the listing's Audience to Public in Partner Center (§ Microsoft Store); CI needs no change, since `tools/msstore_release_notes.py` already commits a `Public` submission (`ALLOWED_VISIBILITY`). Drop " - Beta" from the listing name with the app rename above.
- [x] **Snap:** `snapcraft.yml` releases to `stable,edge` (2026-11-13, § Snap).
- [ ] Flip each workflow's header comment and `docs/store-deployment-setup.md` from "testers" to "production".

## Decisions outside the code

- [x] **Moving v1 users over.** Decided 2026-11-19: § Sunsetting v1.
- [ ] **Beta links.** Keep the TestFlight and Play testing links working for a while after launch: installed builds still point at them, and Snap, Microsoft Store and AppImage users can run an old build for months.
- [ ] **People who saw the beta promo.** Decide whether those who engaged with or dismissed it should see the public one; that needs a new preference key (`docs/mobile-app-promo.md` § Swap the links at launch).

## Release freeze

From three weeks before launch (the day the launch build is submitted to the App Store, Play and Microsoft) until launch day, no store workflow is dispatched: a new build would replace the one held for review, and Microsoft would open a second submission. A fix needed in that window goes into the held build (reject, rebuild, resubmit) or waits until after launch. Outside that window, beta releases go out the usual way (`.claude/skills/release/SKILL.md`).

## Launch day

The launch build is submitted three weeks ahead, one workflow at a time rather than Deploy to all: `appstore-ios.yml` and `appstore-macos.yml` (submit both version pages with manual release), `playstore.yml` to the beta track then promoted to Production in the Play Console with managed publishing on, and `microsoft-store.yml` with `publish_mode: Manual` after switching the Audience to Public. v1's move release is submitted the same way, held, two weeks ahead.

Two days before: go or no go. Every new-app submission and every v1 move release must be approved; if one isn't, slip the whole launch (the email and the links are global). Microsoft alone may follow later: hold v1's Windows move release until it is certified.

On the day, in this order:

1. Release the new app on the App Store (iOS and macOS), Play and Microsoft.
2. Open each listing logged out, in two storefronts, on a device that isn't a tester's. Wait until all of them load.
3. `appimage.yml` (tag, GitHub Release, the F-Droid APKs), then `snapcraft.yml`, then Flathub's update (merge it by hand if it isn't automatic). `web.yml` only if the web app launches the same day.
4. Turn in-app purchases on for everyone in the hosted billing.
5. Point the redirect links (`https://invoiceninja.com/app/{ios,android,mac,windows}`) at the listings and check each with `curl -sI`.
6. Release v1's move release on every store and tag it for F-Droid. Publish v1's listing text (§ Sunsetting v1).
7. The landing page (`tools/web_deploy/landing/apps.json`, then `export_landing.sh` and a backend PR) and the website's download links.
8. Last, once every link above works: the announcement email, the help-center page, the support macros, the note to testers, and the old repo's README.

| If | Then |
|---|---|
| a listing isn't visible after release | wait; send nothing until every link works |
| the redirect flip fails | the page it points at before launch already lists the store links |
| a GitHub, Snap or Flathub job fails | re-run it; Snap rolls back with `snapcraft release invoiceninja <previous revision> stable` |
| F-Droid lags | expected; the email says "within a few days" |
| purchases fail or crashes spike | turn in-app purchases off in the hosted billing, then fix forward |

A first release has no staged rollout on Play and no phased release on the App Store: a bad launch build is fixed by an expedited review, a fast Play release, or taking it off sale.

## Sunsetting v1

v1 (`com.invoiceninja.app`) becomes **Invoice Ninja Legacy** and keeps working beside the new app for about six months.

**What users are told, everywhere** (v1's prompt and retired screen, the store listings, the email, the help center): their data lives in their Invoice Ninja account in the cloud (or on their own server), so a new app changes nothing about it; they only need the new app on their phone or computer and sign in with the same account; both apps work side by side until the sunset date, so they can switch at their own pace, and their plan comes with them; and if anything works differently than they'd like, they should tell us (Settings → Contact Us in the new app, `contact@invoiceninja.com` from v1).

**Rules:**

- v1's App Store subscription products stay on sale for good: removing one stops its renewals. Never delete either app's store record or its notification setup.
- An App Store v1 subscriber changes level in Apple's subscription settings, inside v1's group. A Play v1 subscriber keeps v1's subscription, and its plan comes with them. Cancelling the v1 subscription with a prorated refund when they buy in the new app applies only once the hosted billing has that migration step; until then, nothing (v1's prompt, the listings, the email, support) may promise it.
- Never stop a v1 that a store still lists: take it off sale first, then raise the minimum version.
- The stop is server-only: a server release sets `minimum_client_version` to `5.1.0` in `config/ninja.php` (every v1 is 5.0.x, the new app 5.1.x). It is a constant, not an env override: David declined one (invoiceninja/invoiceninja#13478), because an override needs another intervention to unset. So the stop reaches self-hosted servers too, when they update past that release. Self-hosted users are told to move to the new app before updating.
- Ask Play support in writing whether unpublishing an app cancels its subscriptions before unpublishing v1 on Play.

**v1's releases** (admin-portal: `develop` → `master` for iOS, macOS, Android and F-Droid; the `flutter-3.19.6` branch for Windows, every change cherry-picked there):

- [x] Its CI can no longer replace the new app: the web build is manual only and the Snap and Flatpak workflows are gone (2026-11-19).
- [x] The rename to Invoice Ninja Legacy, `IN Legacy` under the icon (2026-11-19, not yet released). Release it about five weeks before launch and wait until it is live everywhere: the App Store name and the Microsoft name can move to the new app only after.
- [ ] The move release: the beta invite becomes the move prompt (re-armed for everyone, escalating towards the sunset date, always dismissible), a retired screen when the server's minimum version refuses it, no more in-app sales (Manage subscription and Restore stay), and links through the redirect. Submitted two weeks before launch, held.

**v1's store listings** point at the new app from launch day: App Store promotional text (set by hand) and description, the Play short and full description, the Microsoft description (with the retirement date), and the F-Droid metadata.

**The sunset**, about six months after launch: check v1 traffic by platform two weeks before; take v1 off sale on every store (its subscriptions stay); ask F-Droid to archive it; then raise the hosted minimum version; remove the Snap rollback-to-revision-76 note above (revision 76 is v1); archive the admin-portal repo.


## The privacy manifests declare SQLite's disk-space call

`ios/Runner/PrivacyInfo.xcprivacy` and `macos/Runner/PrivacyInfo.xcprivacy` declare `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1`.
- **Why it's needed:** the bundled SQLite (`native/sqlite3mc/sqlite3mc_amalgamation.c`) is built with `SQLITE_ENABLE_LOCKING_STYLE` on Apple platforms. Its locking-style finder calls `statfs` / `fstatfs` (about lines 46795, 47574 and 48999), and both are on Apple's disk-space list.
- **Why the app declares it:** the framework built from that source ships no manifest of its own, so without this entry an App Store upload gets ITMS-91053.
- **The other entry:** `stat` / `fstat` / `lstat` are file-timestamp APIs, already covered by `C617.1`.
- **macOS:** Apple doesn't enforce the macOS manifest at upload today; it carries the same entry so the two stay in step.
