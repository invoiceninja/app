# A self-hosted server behind Cloudflare's "Verify you are human"

Companion to CLAUDE.md § Sync — non-obvious rules. How the app gets past a Cloudflare zone that challenges visitors, which a browser passes and `package:http` cannot (invoiceninja/invoiceninja#13484), and what is still unproven against a live zone.

## A challenge is recognised in the transport, by `cf-mitigated: challenge` with a `cf-ray`, and is a not-sent error

**`CloudflareClearanceClient` (`lib/data/services/cloudflare/`) wraps the client `ApiClient` and `AuthService` send through — login, `/refresh`, the outbox, uploads, downloads — and turns a response carrying `cf-mitigated: challenge` and a `cf-ray` into `CloudflareChallengeException` before anything reads its HTML as JSON or its 403 as a refusal.** `cf-mitigated` is Cloudflare's documented signal for every challenge page, whatever the status (403, 429, 503) or language ([Detect a Challenge Page response](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/)); the `cf-ray` requirement keeps a proxy that is not Cloudflare from making a write it forwarded look unsent.

- **A `RequestNotSentException`.** Cloudflare serves the challenge without forwarding the request, so the outbox re-parks the row with its attempts unchanged (`SyncRepository`'s not-sent arm): never `dead`, never `unconfirmed`. It is thrown before `_postFlight`, so no 401 / 403 "Invalid token" sign-out can see it.
- **Both catch chains let it through untouched** — `ApiClient._sendNoRedirect` and `AuthService._post` would otherwise wrap it as an outcome-unknown network error (the body was read). The upload paths already rethrow what they don't recognise.
- **While an origin waits, requests fail at once** (`CloudflareClearanceStore.mayProbe`), but for one real probe every 20 s: a queue of offline edits is not a burst of challenged requests per drain, and a network the zone allows is still noticed. **Any unchallenged answer ends the wait** (`noteReached`).
- **On the web too**, for classification only: the browser holds the clearance, so nothing is ever replayed there, and the strip says to reload the page.
- **Not wrapped, deliberately:** DocuNinja (its own host), the hosted realtime socket, `PasskeyReadiness` (a challenge leaves passkeys hidden, not cached), and `Image.network` logos (initials).

## A passed check is the web view's `cf_clearance` and its exact User-Agent, replayed per origin

**The check screen (`showCloudflareCheck`, `lib/ui/core/widgets/cloudflare_check.dart`) loads the server's `/api/v1/ping` in a real web view; once the main frame is on the server's origin, loaded, not the challenge (`window._cf_chl_opt`, `#challenge-form`, a "Just a moment" title), and the native cookie store holds `cf_clearance`, it reads `navigator.userAgent` and hands both to `CloudflareClearanceStore`.** The client adds them to every request to that origin (scheme + normalised host + port), and to no other.

- **`/api/v1/ping`, never the challenged request** (`cloudflareCheckUrl`): that may be a POST route (Laravel's 405 page; with `APP_DEBUG`, a stack trace), a download the web view never finishes, or an upload.
- **Only Cloudflare's cookies** (`cf_clearance`, `__cf*`, `_cfuvid`), never a web session the server set. `__cf_bm` rotates in ordinary responses; `noteResponseCookies` keeps the set current — only for the clearance that request carried.
- **`cf_clearance` is HttpOnly**, so it comes from the native store (`WebViewCookieManager.getCookies` reads WKWebView's default `WKWebsiteDataStore`, the one `WebViewController` loads into; Android's `CookieManager`; WebView2's `getCookies`), never `document.cookie`.
- **Android**: third-party cookies are switched on for the check's web view (Cloudflare's widget is a frame on `challenges.cloudflare.com`; Android refuses them by default), and only `cf_clearance` is read from its cookie string, which the plugin splits at every `=` — the rest arrive through `Set-Cookie`. Android asks the navigation guard only for GETs, so a form POSTed off the origin is not caught.
- **The User-Agent must look like a browser engine's** (`isUsableUserAgent`): the page's script can override `navigator.userAgent`, and a value `dart:io` refuses as a header would fail every request.
- **A zone that let the web view through unchallenged** (a rule on the Dart client's User-Agent) sets no `cf_clearance`; after three clean looks the User-Agent alone is adopted (`CloudflareCheckProbe`).
- **Https only** (`canVerify`): over http a network attacker can inject the header, and the check would put their page full screen inside the app and send `Secure` cookies in the clear.
- **Memory only** in the app. The web views' own stores keep `cf_clearance` across launches (and, on iOS, macOS and Android, across a sign-out — it names no person; Windows deletes its WebView2 folder at sign-out), so a later check usually loads straight through and closes on its own.

## The check opens only when the user asks, and a zone that refuses the replay is said so, never looped

**Nothing opens the check on its own: the shell's `CloudflareBanner` offers Verify, and the login screen opens it from the step the user just took.** A background sync can be challenged at any moment (Challenge Passage defaults to 30 minutes), and an automatic full-screen page would land over a dialog or a half-typed edit, re-open on every rotation across the 600 px breakpoint, and — on a zone that refuses the app's requests even after a pass — pass at once from the web view's cookie and open again, forever.

**A clearance challenged within three minutes of its pass marks the origin `CloudflareWait.refused`** (`refusedWithin`): the zone binds more than the cookie and the User-Agent. The strip and the login toast then say the server's Cloudflare settings turn the app away and give the Ray ID for the administrator; the login screen does not open another check. A clearance that worked longer simply expired (`CloudflareWait.expired`, usually a new network: the cookie is bound to the IP), and the strip asks again. A challenge on a request that left before the current clearance was adopted is stale and ignored, so it can neither drop the new clearance nor reopen the wait.

Hosted Invoice Ninja and the demo (`isHostedOrDemoHost`) never get a web view; the login screen says Cloudflare is checking the connection. Linux has no web view the app ships, so the strip explains and offers nothing; a Windows without WebView2's runtime says the same on the check screen.

## What only a device on a challenged zone can settle

The issue's reporter offered to test off the allowlist with a TestFlight build. Ask for each platform tried, the first replayed request's status, its `cf-ray`, and whether `cf-mitigated` is on it.

- **Whether the replay is accepted at all.** Cloudflare documents `cf_clearance` only as tied to "the specific visitor and device it was issued to". Copying it with the same User-Agent and IP works on typical zones (FlareSolverr relies on it), but `dart:io` speaks HTTP/1.1 with its own TLS handshake (JA3/JA4), lowercase header names and no `sec-ch-ua` / `sec-fetch-*` / `Accept-Language`, which Bot Fight Mode, Super Bot Fight Mode or Bot Management may score. That is what `refused` reports. **The next step for a refused zone** is the issue's spike option 2: run `/api/v1/*` through `fetch()` inside the web view and return status, headers and body to Dart.
- **`cf_clearance` is set `Partitioned`** (CHIPS). Whether each platform's cookie API returns a partitioned cookie is unverified; if not, the probe adopts the User-Agent alone and the zone reports `refused`.
- **Turnstile inside an Android web view** with third-party cookies on.
- **IDN hosts:** `Uri.origin` is Unicode where `location.origin` is punycode, so the check never passes for a server on an internationalised domain (it fails closed).
- **Challenge Passage**: an administrator who raises it (15–45 minutes is Cloudflare's advice; longer is allowed) means fewer checks in the app.

Pinned by `test/data/services/cloudflare_clearance_test.dart` (detection, replay, fail-fast, the refused breaker, stale challenges, `ApiClient` classification) and `test/ui/core/widgets/cloudflare_check_test.dart` (when the check counts as passed).
