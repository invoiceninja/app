# Desktop-app promo: telling phone users about the desktop app

Companion to CLAUDE.md § Strict rules (the promo rule, which covers both directions). This doc carries the reverse of `docs/mobile-app-promo.md`: who on a phone is offered which computer, the store-policy evidence behind each call, and what changes at launch. Everything not said here (the schedule, the quiet-moment check, the holds with What's New, the review prompt and the Welcome) is the mobile-app promo's, shared on purpose.

A one-screen dialog on native iOS, iPadOS and Android that pitches the desktop app: the same account and data on a bigger screen, with room to work and keyboard shortcuts. Not "works offline" or "pick up where you left off": the phone app already does both, so they sold nothing to the person reading it (cut in the review after launch). A phone can't install a desktop app, so it hands the download link over: **Share link** opens the system share sheet (AirDrop to a Mac, Mail or a message to yourself, a note), and **Copy Link** puts it on the clipboard. A self-hosted account also gets the server address to copy, with a same-network note when it is private.

| Piece | File |
|---|---|
| The rules: targets per platform, links, captions, eligibility | `lib/domain/desktop_app_promo.dart` |
| The schedule (shared controller, its own key) | `lib/app/mobile_app_promo_controller.dart` with `prefKey: DevicePrefKeys.desktopAppPromo`, chosen in `Services.build` when `Env.isMobile` |
| The dialog, and `showAppPromoDialog` (whichever promo this build runs) | `lib/ui/features/mobile_promo/desktop_app_promo_dialog.dart` |
| The automatic opener (shared) | `lib/ui/features/mobile_promo/mobile_app_promo_host.dart`, gated on `currentAppPromoKind` |
| Device Settings card (Phone tab) | `lib/ui/features/settings/widgets/desktop_app_section.dart` |
| Integrations row ("More from Invoice Ninja") | `lib/ui/features/settings/views/basic/account_management/integrations_screen.dart` |
| About entry | `lib/ui/features/shell/widgets/about_dialog.dart` (`onShowDesktopApp`) |
| Settings search gate | `settings_search_catalog.dart` (`showsDesktopApp`, `kDesktopAppSearchKeys`) |
| Tests | `test/domain/desktop_app_promo_test.dart`, `test/ui/features/mobile_promo/desktop_app_promo_dialog_test.dart`, `test/ui/features/mobile_promo/desktop_app_promo_entry_test.dart`, `test/app/mobile_app_promo_controller_test.dart` |

## The desktop-app promo shows no more than the Mac on iOS, never gates anything, and never carries purchase copy

- **Mac only on Apple's builds.** `desktopPromoTargets(platform: iOS)` is `[mac]` whatever links exist, so no launch switch can widen it; the dialog names only the computers it was handed. `desktop_app_promo_dialog_test` pumps the iOS surface and checks every string, tooltip, semantics label and copied or shared link, and every locale's translation of every key that surface renders, for Android, Google, Windows, Linux, Microsoft, Flathub and Snap. The reasoning is § Store-policy review below.
- **Never a gate.** The ✕, Esc and a labelled close are always there, and nothing waits on the dialog.
- **No purchase copy.** Every link is a free download.

## What each platform shows

| Surface | Targets | Link |
|---|---|---|
| Native iOS / iPadOS (App Store, TestFlight) | **Mac only** | `nativeAppUrl(mac)`: TestFlight's public link today, `invoiceninja.com/apps/mac/` after the launch switch |
| Native Android (Google Play, F-Droid) | Windows, Mac, Linux, each once it has a public listing | `nativeAppUrl(...)`: Windows waits for `kWindowsAppUrl` (null until the Microsoft Store audience is Public); Linux is Flathub |
| Native macOS, Windows, Linux, and the web | none | (the mobile-app promo runs there; the web's banner offers the native app) |

The links are the web banner's (`lib/domain/web_app_banner.dart`), never a second copy, so the launch switch that sets `kMacAppUrl` and `kWindowsAppUrl` (`~/.claude/plans/launch-switches/0003`) switches this promo too: Windows appears on Android, and the Mac link moves off TestFlight. The Mac caption follows the link (`desktopPromoStepKey`: a `testflight.apple.com` link gets the TestFlight caption, anything else the App Store one), so it can't go stale at that moment.

Snap is in production too, but the promo hands out one link per computer and the Linux one is Flathub (v1's listing, which Linux users already update from); the caption mentions the Snap Store.

## Store-policy review

Reviewed November 2026 against [Apple's App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), the [Google Play Developer Policy Center](https://play.google.com/about/developer-content-policy/) and [F-Droid's anti-features](https://f-droid.org/docs/Anti-Features/).

| Rule | Source | How the promo complies |
|---|---|---|
| "don't include names, icons, or imagery of other mobile platforms or alternative app marketplaces in your app or metadata, unless there is specific, approved interactive functionality" | Apple 2.3.10 | Mac only on the Apple builds (below). Nothing on the iOS surface names Android or Google Play, and `desktop_app_promo_dialog_test` checks every string, tooltip, semantics label and copied link of the iOS surface, and every locale's translation of every key it renders, for Android, Google, Windows, Linux, Microsoft, Flathub and Snap. |
| "Displaying your own apps for purchase or promotion within your app" is acceptable | Apple 3.2.1(i) | Our own app, in one dialog. |
| Apps must not "force users to … download other apps … in order to access functionality" | Apple 3.2.2(x) | Always dismissible; gates nothing. |
| Apps "shouldn't primarily be marketing materials" | Apple 4.2.2 | At most three automatic opens ever, none before the third day of use: the mobile-app promo's schedule. |
| No buttons or links to purchasing outside in-app purchase | Apple 3.1.1(a) / 3.1.3, Play Payments policy | Every link is a free download; no plan, price or upgrade copy. |
| An app "may not download executable code (such as dex, JAR, .so files) from a source other than Google Play", nor update itself outside it | Play Device and Network Abuse | It downloads nothing to the phone: the link is for another computer. |
| No disruptive or unexpected full-screen interstitials | Play Ads policy | Not an ad; a dialog at a quiet moment, at most three times, with a ✕, Esc and a labelled close. |
| NonFreeAdd: an app that promotes non-free apps or add-ons | F-Droid anti-features | The desktop apps are this app's own source (AAL, OSI-approved), the Linux one built from source by Flathub; nothing non-free is promoted, so no new anti-feature. |
| Third-party names and logos only as their owners permit | Apple, Microsoft and Google trademark guidelines | Plain-text platform names on a text-only segmented control and Material glyphs (`laptop_outlined`); no store badges, no Apple, Windows or Tux marks. |

### Why the Apple builds offer only the Mac

Windows and Linux are not mobile platforms, so the first half of 2.3.10 doesn't reach them, and many App Store apps say "also on Windows". The call is about the second half and about how reviewers apply it, literally (`docs/mobile-app-promo.md` § Store-policy review cites the rejections):

- **The links name marketplaces.** Windows installs from the Microsoft Store and Linux from Flathub or the Snap Store. The promo's whole job is handing over a link, so the copied or shared URL (`flathub.org/...`, `apps.microsoft.com/...`) and its caption would put an app marketplace's name on an iPhone screen. Whether Apple's "alternative app marketplaces" means only the EU's iOS marketplaces or any app store is exactly the doubt a reviewer resolves against us.
- **No neutral page exists yet.** `invoiceninja.com/apps/windows/` and `/apps/linux/` are store-button pages that name the Microsoft Store, Flathub and the Snap Store, and the invoicing.co landing page that lists every platform isn't served yet (`HOSTED_LANDING` off, `docs/web-deploy.md`) and today links v1's Windows and Mac listings.
- **The gain is small.** An iPhone owner's computer is likeliest a Mac, and the Mac is the one computer Apple's own store serves.

So the Apple builds name the Mac and say "your computer" everywhere else. Revisit after launch: once `invoiceninja.com/apps/windows/` links the new app, offering "Windows" through that page is a defensible next step, decided then, not slipped in by the launch switch, which never changes `desktopPromoTargets`' Apple branch.

## The card fits an iPhone SE, and lays out in the room the route gives it

- **Measured with a `LayoutBuilder`, never `MediaQuery.size`.** On a foldable held half-open, `showDialog` puts the card in one half (`DisplayFeatureSubScreen`), but `MediaQuery.size` is still the whole window, so the 720-wide tablet layout was drawn into a ~420 half (docs/foldables.md).
- **Room is counted in lines of text** (`height / textScale`). Below 700 the laptop glyph goes and the vertical inset drops to 16; below 560 (a 4-inch phone, or a big phone at 200% text) the features keep their titles only (`FeatureRow` with an empty body).
- **Share and Copy sit side by side, and so do the footer buttons, until they don't fit**: both are `OverflowBar`s, stacking with Share and Remind me later on top. A `Row` of `Flexible`s ellipsized the footer to "Don't sho…" / "Remind m…" at a large text size.
- **The platform segments scale down rather than wrap** (`FittedBox`, one line per label); "Windows" broke across two lines at 200%.
- **Copy link is its own key** (`desktop_app_promo_copy`), in the Share button's case: the shared `copy_link` is title case and untranslated in about a dozen locales, which put English beside a translated Share.
- `desktop_app_promo_dialog_test` § layout loads Inter Tight (the test font wraps everything) and pins each of these.

## Who sees it, and when

Exactly the mobile-app promo's rules (`docs/mobile-app-promo.md` § Who sees it, and when), through the same `MobileAppPromoController` and `MobileAppPromoHost`:

- **Eligibility** (`desktopPromoEligible`): a signed-in, non-demo session whose server isn't loopback. A private-network server is offered, with "Your computer needs to be on the same network as the server".
- **Not before the third day** of use, **at most three automatic opens** (+7, then +30 days), **never in a launch that already showed an automatic dialog**, a day behind What's New, a week apart from the review prompt both ways (the review prompt runs on exactly these store builds, so this hold matters more here), never in a first-run Welcome's week, and only at a quiet moment.
- **Share or Copy Link ends the automatic opens**, as taking the app does in the other direction; "Don't show again" too. About, Device Settings and Integrations open it on request forever.
- **Its own key.** `desktop_app_promo_json` (device scope), so the reverse promo starts its own count on a phone and never inherits the other's answer. The two promos never run on one device (`currentAppPromoKind`), which is why one controller instance serves either.
- **No sidebar card.** A phone's sidebar is a drawer, and the card's job (a way back on a big screen) is done by About, Device Settings and Integrations.

## Launch switch

Nothing in this promo needs its own launch patch: it reads `nativeAppUrl`, which patch 0003 updates. After that patch, Android offers Windows (`invoiceninja.com/apps/windows/`) and both phones' Mac link is `invoiceninja.com/apps/mac/`, whose store buttons must name the new app's listings by launch day (they already must, for the web banner). `kDesktopPromoEnabled` switches the whole promo off in the next build.
