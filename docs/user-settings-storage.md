# Where a synced preference lives

Companion to CLAUDE.md § Strict rules. The rule is one line there; this file carries what the server does with each object, why this app stays out of React's, and how a change travels.

## A synced preference lives only in company_user.settings, under a flutter_ key, never in react_settings

**A synced preference lives only in `company_user.settings`, under a `flutter_`-prefixed key, written through `UserSettingsRepository.patchSettings` — never in `react_settings`, which is React's.**

The server keeps two per-(user, company) objects, and each has an owner:

| Object | Owner | Route | What this app does |
|---|---|---|---|
| `company_user.settings` | the Flutter apps (admin-portal's `UserSettingsEntity`) | `PUT /company_users/{id}` | reads and writes: `table_columns` in the old app's own format, plus its `flutter_` keys |
| `company_user.react_settings` | the React web client | `PUT /company_users/{id}/preferences` | **never writes, never stores.** Reads two keys at sign-in (below) |

Hillel's ruling, November 2026: this app must not be able to cause the React team a problem, so it keeps nothing in their blob — not under its own key, and not in theirs. Until then the dashboard wrote React's `dashboard_fields` and `preferences.dashboard_charts.default_view` and kept `flutter_dashboard` / `flutter_welcome` beside them; all of it moved.

**The keys today:**

- `table_columns` — shared with the old app, byte-compatible (`'EntityType.client'` keys). The one key without the prefix, because it is the old app's.
- `flutter_dashboard` — `{cards, grouping, panels, chart_series}` (`docs/dashboard-panels.md`).
- `flutter_welcome` — `{v, at}`, written when the first-run Welcome closes (`docs/first-run-welcome.md`).

A new synced preference takes a new `flutter_<name>` key. `patchSettings` asserts the prefix: the object is shared with the old app, and the prefix is what keeps a key of ours from meeting a field of theirs (`dashboard_fields` is the old app's, in another format).

**What is still read from `react_settings`.** `SignInFacts.serverSaysWelcomed` looks for `flutter_welcome` / `flutter_dashboard` in the sign-in response's `react_settings` as well as its `settings`, so a user an earlier build welcomed is not greeted again on a new device. That is a read of this app's own old keys out of a response already in hand. Those keys are left where they are: removing them would mean writing the blob.

## The server replaces the object, so an outbox row carries only its change

`CompanyUserController::update` sets `settings` to whatever the request holds (an admin through `fill`, a non-admin by assignment). A body built when the change was made is stale by the time it is sent if anything else changed meanwhile, and would put the old value back. So:

- **A `user_settings` outbox row holds a `UserSettingsChange`** — `{patch: {<dotted path>: value}, columns: {<table_columns key>: [...] | null}}`. Column keys contain dots (`EntityType.client`), so they cannot be paths. Rapid changes merge into the one pending row.
- **The dispatcher builds the body when it sends** (`putBodyFor`): the freshest local settings with the change laid over them.
- **A login or `/refresh` lays every waiting change over the server's copy** (`applyServerSettings`), so a queued change does not visually revert and a key another client changed still lands. Before this the capture was skipped outright while a row waited, and the queued body overwrote whatever had changed on the server since.
- **The local copy is written at once**, so the UI reacts before the row drains. `patchSettings` is a no-op until a login has stored the settings row.

**A row an earlier build queued** holds the whole body (`company_user` in its payload). It is sent as it is, a capture leaves the local copy alone while one waits (the contract it was queued under), and a new change queues behind it rather than merging into it. A `user_preferences` row — an earlier build's `react_settings` patch — is never sent: its `flutter_` keys are moved to `settings` and React's keys in it are dropped (the dashboard re-seeds its own copy from `nav_state`).

## A profile save replaces the same object, so the two saves hand each other what they changed

`PUT /users/{id}` (User Details: the accent colour, notifications) also sets `company_user.settings` whole (`UserRepository::save`, both the admin and the non-admin branch), from a body built when the profile was edited out of the `users` row's copy. Two copies of one server object, each sent whole, overwrite each other:

- **The profile save takes this app's keys from the freshest settings.** `UserSyncDispatcher` passes its body through `withFreshAppKeys` before sending: every `flutter_` key and `table_columns` come from the `user_settings` row, everything else stays as the profile edit had it. Without it a profile save put the dashboard and the list columns back to where they stood at the last `/refresh`, and the dashboard then adopted that as another device's change.
- **Its reply is stored as the settings** (`applyProfileSaveSettings`), so the next settings PUT does not send the accent colour as it stood before the save.

Both are for this company's signed-in user only. An admin editing **another** user in User Management still sends that user's settings as the roster last had them (at most one `/refresh` old), which can put back a change that user made in the meantime; nothing on this device knows their fresher copy.

## A non-admin's body has to carry notifications

The non-admin branch of `CompanyUserController::update` reads `$request->input('company_user')['notifications']` unguarded, so a body without that key is a PHP warning, which Laravel raises as a 500. `putBodyFor` therefore adds `notifications` for a company where the user is not an admin, from the copy the login captured into the auth user's `users.payload` (`company_user.notifications`). Admins are sent no `notifications`, so a copy that is minutes old is never laid over a change made elsewhere. If the copy is not there yet (a store written by an earlier build, before its first `/refresh`), the body goes without it and the server's answer stands. This is read from the server source, not measured against a live server.

## The old Flutter app erases keys it does not model

admin-portal serializes its typed `UserSettingsEntity` and the server stores exactly that, so a settings save made in the old app (a column change, the accent colour) drops every `flutter_` key. Nothing can prevent that from this side. What recovers it: the dashboard re-seeds `flutter_dashboard` from the device's `nav_state` the next time it opens (`docs/dashboard-panels.md` § Adopting is not writing), and a lost `flutter_welcome` costs at most one more Welcome on a new device. A new `flutter_` key needs the same answer — a device-local copy to re-seed from — or to be safe to lose.

Tests: `test/data/repositories/user_settings_patch_test.dart`, `test/data/repositories/user_settings_repository_test.dart`, `test/ui/features/dashboard/dashboard_synced_prefs_test.dart`.
