# The soft lock

Companion to CLAUDE.md § Architecture — at a glance. CLAUDE.md has no bullet for it (the file is at its size cap); every rule lives here, each heading worded as the rule. Device Settings → Security → **Lock after inactivity** locks the app after a span of no use **without signing out**, and the device's own authentication unlocks it. Beta feedback asked for exactly that: "locks the application after a period of inactivity without signing the user out … a Logout option should also be available from the lock screen."

Where things live:

- `lib/app/user_activity_tracker.dart` — the one activity clock (shared with the web's idle sign-out).
- `lib/app/soft_lock_controller.dart` — *when* it locks.
- `lib/app/lock_after_inactivity_controller.dart` — the setting (`DevicePrefKeys.lockAfterInactivity`).
- `AuthRepository.softLocked` / `appLocked` / `engageSoftLock` — the lock state.
- `lib/ui/features/auth/views/soft_lock_host.dart` — what it looks like and what it blocks.
- `lib/ui/features/auth/widgets/lock_panel.dart` — the panel and the Sign out flow, shared with the cold-launch `/lock` screen.
- Tests: `test/app/soft_lock_controller_test.dart`, `test/ui/features/auth/soft_lock_host_test.dart`, and the `lock after inactivity` group in `test/ui/features/settings/views/basic/device_settings_screen_test.dart`.

## The soft lock is passed with the device's own authentication, never the Invoice Ninja password

Unlocking calls `BiometricService.authenticateOwner`: `local_auth` with `biometricOnly: false`, so the OS offers Face ID / Touch ID / a fingerprint and falls back to the device passcode, Mac login password, Android lock-screen PIN or Windows Hello PIN by itself. The Invoice Ninja password was ruled out:

- the server has no endpoint meant for verifying a password outside a login (`/login` would mint a new token and run the 2FA flow; the 412 password gate exists for destructive calls, not as an oracle),
- a user who signs in with Google / Microsoft / Apple has no password to type,
- a 2FA account would need the second factor too.

The cold-launch lock keeps `authenticate` (biometric only, except on Windows), because its toggle is named Biometric Authentication; `LockViewModel.allowDeviceCredential` is the only difference between the two.

## It is offered only where the device can verify its owner, and it re-checks before it locks

The row is mounted only when `BiometricService.canAuthenticateOwner()` is true — `local_auth`'s `isDeviceSupported`: `LAPolicy.deviceOwnerAuthentication` on iOS / macOS (true with just a passcode or login password), `isDeviceSecure() || canAuthenticateWithBiometrics()` on Android, Windows Hello on Windows. Linux has no `local_auth` implementation and the web's `WebBiometricService` says false, so neither shows the row; its subtitle says how it is unlocked. That is wider than `isAvailable()` (which also needs enrolled biometrics), so a Mac without Touch ID gets the lock — passed with its login password.

`SoftLockController` asks again on every resume and never locks while the answer is not `true`: a passcode removed in the OS settings would otherwise leave a lock nobody can pass, with Sign out — a full wipe — as the only way on. Turning the setting on from Never asks for the device authentication first (`LockAfterInactivityTile`), so nobody sets a lock they can't pass; changing the span or turning it off doesn't ask.

## The setting is a device-scope preference

`DevicePrefKeys.lockAfterInactivity` (`lock_after_inactivity_minutes`, minutes as a decimal, `0` / no row = Never; offered: Never, 1, 5, 15, 30, 60). `PrefScope.device`, so a sign-out keeps it: the lock proves that whoever holds *this device* is its owner — it never asks who is signed in — so it is a property of the device, like the trusted certificates. An account scope would let every deliberate sign-out quietly drop a security choice, and a stricter lock inherited by the next sign-in on the same device costs nobody anything. Pinned in `device_pref_keys_test.dart` and probed in `device_prefs_wipe_test.dart`.

## Inactivity is the shared activity clock, and a running timer is not activity

`UserActivityTracker` is the single source both `IdleTimeoutController` (the web's idle sign-out) and `SoftLockController` read; it was carved out of the idle controller rather than duplicated. Its sources: the root pointer `Listener` in `main.dart` (down, move, hover, scroll), every hardware key event, edits to the focused `TextEditingController` (a soft keyboard sends no key events), and the `UserActivityNotification` a `MarkdownTextField` bubbles up. Each consumer measures idle time from the later of the tracker's last activity and its own arming moment, so arming one never resets the other's clock.

A running task timer pokes nothing, so it never holds the lock off — and it keeps running under the lock, because locking disposes nothing (next section). The same goes for sync, the outbox drain and the company row re-emitting on every `/refresh`.

Time in the background counts. `lastActivity` is a wall-clock stamp, and `SoftLockController.didChangeAppLifecycleState` checks on every transition — `hidden` and `inactive` come before `resumed` on the way back on iOS and Android, so the lock is already up when the first resumed frame is drawn. Its periodic check runs every quarter of the span, 5–15 s. Passing a lock (or signing in) restarts the span: a Face ID unlock involves no touch, and without that the app would lock again on the next tick.

## The soft lock is an overlay above the router, never a route

A redirect to `/lock` — what the cold-launch gate does — disposes everything under the router: an open edit screen and its unsaved changes, the scroll positions, a half-filled dialog. So `SoftLockHost` wraps the routed app in `main.dart`'s `MaterialApp.router` builder (inside `NativeSplash.wrap`, around the Stack that holds the router, the toast host and the shortcut-hint bar) and, while `AuthRepository.softLocked` is true, adds an opaque `LockPanel` as a later Stack child. The wrappers around the app — `TapRegionSurface`, `ExcludeFocus`, `ExcludeSemantics` — are always there and only their flags change, so nothing beneath is rebuilt into a new element (CLAUDE.md § Forms: a focused field never changes its place in the tree). The router does not watch `softLocked`.

Because the panel is above the router's Navigator, every dialog, menu, sheet and toast the app had open is under it, and stays open for after the unlock. The panel's own dialogs (the sign-out confirmation, the unsynced-work prompt) open in a Navigator the panel owns, and its toasts in its own `ToastHost` with its own `ToastController` (provided above it, which `Notify` prefers to `Services.toasts`). That Navigator's `NavigationNotification`s are swallowed: `WidgetsApp` applies the last one it sees, and the panel's single page announcing "cannot pop" would leave Android's back with the OS after the unlock (docs/architecture.md § Why Android system back needs three things to keep working).

Pinned by `soft_lock_host_test` — "locks in place" (the `EditableText` State is the same object after the unlock, with the text) and "a dialog open in the app stays under the lock".

## Nothing reaches the app beneath while it is locked

- **Pointer.** A `Stack` hit-tests its last child first and stops at the first hit, so the opaque panel takes every tap, hover and scroll. The app sits in its own `TapRegionSurface`: without it a tap on the panel would be an outside tap to every `TapRegion` in the app (`MenuAnchor` closes on one; picker fields run their `onTapOutside`).
- **Keyboard.** `ExcludeFocus` over the app lets go of whatever it had focused — and with it the soft keyboard's text connection, which would otherwise keep typing into the hidden field — and stops anything in it taking focus back. The panel puts focus on Unlock (or on its own scope while a prompt has Unlock disabled), takes it back post-frame if anything moves it, and ends every key it doesn't use in a trap `Focus` above its scope; WidgetsApp's default shortcuts are re-declared inside the trap so Tab, Enter, Space, Escape and the arrows still work on the panel. A ⌘ / Ctrl chord is passed up to the OS rather than swallowed (⌘Q, ⌘H). The app's whole keyboard layer hangs off focus inside the shell (docs/keyboard.md § The whole keyboard layer hangs off one focus node), so none of it is consulted; `FocusOwnerKeeper` leaves focus that went *beside* it alone (§ A keeper reclaims focus only when it escaped upward). The four global `HardwareKeyboard` handlers in the app (`AutomaticDialogs`, `ShortcutHintOverlay`, `FormSaveScope`, `DesignCodeField`) still see keys — all four are passive or cosmetic, and the hint bar they drive is under the panel.
- **Focus comes back.** The node that had focus when the lock went up is taken before the `ExcludeFocus` lets it go, and asked for focus again in the frame after the unlock — so the user is back in the field they were typing in.
- **Back.** Android's back reaches the router's `RootBackButtonDispatcher` before any widget; the panel registers a child dispatcher that takes priority and swallows it (closing its own dialog first), the `BackDismissibleMenuAnchor` pattern.
- **Screen readers.** The app is under `ExcludeSemantics`; the panel's title is a level-1 heading.
- **The frameless title bar.** On Windows (and Linux, which never gets the lock) `WindowFrame` paints the title bar inside the app. The panel leaves that band uncovered so the window can still be moved, minimised and closed, and `WindowFrame` hides its history arrows while locked — the one control there that acts on the app.

Pinned by `soft_lock_host_test` — "no key reaches the app", "a dialog … no tap reaches it", "Android back is swallowed".

## Anything that arrives from outside waits for the unlock

`AuthRepository.appLocked` is true under either lock, and `Services` hands it to the `ArrivalGate` behind `DeepLinkRouter`, `SharedFileIntake` and `TerminalDeclineNotices` (as their `requiresBiometricUnlock` argument), so a deep link, a file shared in, a home-screen widget's Start (a deep link) and a declined-card notice are held and replayed after the unlock — never a navigation behind the lock, which could close an editor. The review prompt and the reset notice (`LocalDataNoticeHold`) wait on it too: the native review sheet would otherwise open over the lock.

A widget's **Stop** is applied while locked, as it is behind the cold-launch lock: it carries the time of the tap, writes through the outbox and navigates nowhere — and once in the outbox it is counted by the sign-out prompt, where a held one would not be.

## Sign out from the lock confirms, and never drops unsynced work

The lock's Sign out is a full logout (`LocalDataPolicy.destroy`), which wipes every company's local data and outbox. It goes through `signOutFromLock` (`lock_panel.dart`), shared with the cold-launch `/lock` screen: `showConfirmSignOutDialog` (the one confirmation the Confirm actions preference cannot switch off), then `confirmPendingOutboxIfAny(checkAllCompanies: true)` — Sync first / Discard / Cancel over every company's pending rows, then the review of failed and unconfirmed ones (CLAUDE.md § Sync — non-obvious rules: a failed `dead` change is still unsynced work). From the soft lock it passes `canOpenOutbox: false`, dropping the review's View: there is no router above the router, and the app under the lock must not move — Cancel, Unlock and the Outbox get the user there. `sign_out_confirm_coverage_test` maps `LockViewModel`'s logout to `lock_panel.dart`.

The cold-launch lock screen already did all of this before the soft lock existed (it gained the outbox prompt with the idle-timeout preserve path; `lock_screen_sign_out_test`); the flow moved into the shared function unchanged.

## It prompts when it appears and when the user comes back — never in a loop

The panel calls the OS prompt once as it appears if the app is in front, else on the next resume. After that it prompts again only on a resume that follows a real trip to the background (`hidden` or `paused` while no prompt was in flight). `inactive` never arms it: the Face ID sheet and the macOS Touch ID panel make the app inactive themselves, and Android's device-credential screen is its own activity, so arming on those would reopen the prompt every time the user cancelled it. On a desktop the lock can engage while another app is in front; it then waits for the window to come back rather than putting a system prompt over someone else's work.

## What it does not do

- **The OS app switcher still shows the last frame.** The app has no mechanism that blanks its window when it goes to the background (`FLAG_SECURE`, an iOS privacy overlay), so a snapshot taken before the span ran out shows the content. The lock is up before the first frame after a return that crosses the span.
- **Focus-bound popovers close.** An open picker's options list closes when its field loses focus to the lock; the field keeps its value. A field that commits on blur (`InDateField`) commits.
- **A toast raised in the app while locked** shows under the panel and may time out unseen.
