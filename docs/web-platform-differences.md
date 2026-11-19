# Web platform differences

Companion to CLAUDE.md § Web. What changes when the app runs in a browser: persistence, the conditional-import seams, the vendored WASM assets, the URL strategy, what is disabled, the missing `Idempotency-Key`, and the demo build. CLAUDE.md keeps one line per rule.

## Web is a supported target

Web is a supported target (`flutter run -d chrome`, `flutter build web`). Native (iOS/macOS) behavior is **byte-identical** — every platform difference is a `kIsWeb` branch or a conditional-import seam that resolves to the unchanged native code on native.

## Persistence is unencrypted IndexedDB

**Persistence.** drift WASM over IndexedDB/OPFS, unencrypted (no SQLCipher, no `PRAGMA key`) — the browser origin sandbox is the trust boundary, a locked product decision; don't add a web encryption layer without re-deciding. The auth token lives in `window.localStorage` (`LocalStorageTokenStorage`), not `flutter_secure_storage`. IndexedDB eviction (storage pressure / private mode) surfaces as the existing `dbWasReset` "fresh sync" flow, not a crash.

- **A web database reset must be verified, and a store the browser won't delete is abandoned (generation-bumped), never reopened.** → `docs/architecture.md` § Why the web database reset needs a store it can abandon

## Conditional-import seams

**Conditional-import seams** (default file = web, `if (dart.library.io)` override = native):
- `lib/data/db/database_opener.dart` → `_io` (SQLCipher file + keychain key + `.broken.<ts>` recovery) / `_web` (`WasmDatabase` + IndexedDB delete on reset). `pruneBrokenDbFiles` is native-only (`database_opener_io.dart`); `sweepAbandonedStores()` does work only on web, after the first frame (`docs/migrations.md` § Abandoned web stores are swept after the first frame).
- `lib/data/services/token_storage_factory.dart` → `defaultTokenStorage()`: `SecureTokenStorage` (native) / `LocalStorageTokenStorage` (web).
- `WebBiometricService` (`biometric_service.dart`) — `isAvailable() => false`; selected via `kIsWeb` in `Services.build`. Biometric/lock UI hides itself.

## Vendored WASM assets are regenerated on every drift or sqlite3 bump

**Vendored WASM assets** (committed in `web/`, served from app root): `web/sqlite3.wasm` (plain unencrypted build, from the [sqlite3.dart releases](https://github.com/simolus3/sqlite3.dart/releases) — must match the resolved `sqlite3` Dart package version) and `web/drift_worker.js` (`dart compile js -O4 -o web/drift_worker.js web/drift_worker.dart`). **Regenerate both on any `drift`/`sqlite3` bump** — version skew between the vendored assets and the Dart packages is the #1 web runtime failure mode. `database_opener_web.dart` logs `WasmDatabase` `missingFeatures` at boot.

## Re-vendor web/pdfjs on any printing bump

**pdf.js is vendored too, and moves with `printing`, not with drift.** The web PDF preview rasterises through pdf.js, which `printing` loads with a dynamic `import()` from `window.dartPdfJsBaseUrl` — set in `web/index.html` to `web/pdfjs/`, resolved against the document base URI so a non-root `--base-href` works — instead of from unpkg. A third-party script host at runtime is the same trade the bundled fonts and the self-hosted CanvasKit already declined, and printing 5.15's pdf.js 6 also closes CVE-2024-4367 (a crafted PDF running script), which matters for a viewer of uploaded documents. pdf.js 6 calls `Promise.withResolvers` throughout (27 sites in `pdf.min.mjs`), so its floor is Safari 17.4 / Chrome 119 / Firefox 121; an older browser gets no raster preview, self-hosted or not. Version rule and re-vendor steps: `docs/setup.md` § Web setup notes.

## The URL strategy stays hash

**URL strategy: hash (`/#/clients`), the Flutter default.** Intentionally left as-is (no `setUrlStrategy`) so the build deploys to any static host with no rewrite-to-index config. Locked decision (see the comment near `runApp` in `main.dart`) — don't switch to `PathUrlStrategy`.

## `dart:io` compiles on web

**`dart:io` compiles on web.** Flutter's web toolchain provides a compile-time `dart:io` stub; `import 'dart:io'` does **not** break `flutter build web` — the classes (`File`, `Directory`, `Platform`) throw `UnsupportedError` only when *used* at runtime, so a `kIsWeb` guard before the call suffices (no conditional-import file needed just for the compiler). Prefer `defaultTargetPlatform` + `kIsWeb` over `Platform.isX` in new code (`env.dart` / `support_api.dart` are the reference).

## WebAssembly runs in Firefox and Safari too

**`web/flutter_bootstrap.js` passes `wasmAllowList: {blink: true, gecko: true, webkit: true}`, so every browser that can run the WebAssembly build (dart2wasm + skwasm) gets it.** Flutter 3.50's loader allows it on Chromium alone by default (`flutter.js`: `{blink: true, gecko: false, webkit: false}`), which sent every Firefox and Safari visitor to the slower JavaScript build (dart2js + CanvasKit). A self-hosted beta user on Safari reported high CPU while navigating and scrolling (November 2026), and the benchmark in `docs/web-benchmarks.md` measured navigation frames about twice as fast under WebAssembly in Chrome. The loader still checks each feature it needs (WasmGC, SIMD, js-string builtins, try_table) in the browser and keeps its own Firefox floor of 147, so an older Firefox or Safari falls back to the JavaScript build by itself.

The load call stays on one line: Deploy to Web's JS smoke test rewrites it with `sed` to force the CanvasKit build (`.github/workflows/web.yml`), and `test/lint/web_bootstrap_wasm_test.dart` fails if the two drift apart. The custom bootstrap passes no `serviceWorkerSettings`, so no build registers Flutter's deprecated service worker (the deploy already built with `--pwa-strategy=none`; the demo and `ci.yaml` builds now match it).

## The browser's toolbar takes the app's background colour, and the app sets it

Safari tints its toolbar (and an installed PWA its title bar, Android Chrome its status bar) from `<meta name="theme-color">`, or, where it ignores the tag, by sampling the page itself. Both pages (`web/index.html`, `tools/web_deploy/boot_page.html`) ship the default pair, lightSand `#F6F4EF` / darkEspresso `#15140F`, keyed on `prefers-color-scheme`, and paint `html, body` the same colours in the shared `loader-style` glue block. Before November 2026 the body was `#888888`, so Safari's toolbar came out grey over a cream app (a self-hosted beta user's report).

The tags can only follow the **system** theme. The user's own choice, an explicit dark theme on a light system or the White (`#FFFFFF`) and Grey (`#ECEEF2`) light backgrounds, is known only to the running app. So `main.dart`'s `MaterialApp.router` builder calls `applyBrowserChromeColor(tokens.bg)` (`lib/app/browser_chrome_web.dart`) beside `NativeWindowTheme.apply`: it rewrites every theme-color tag to the current background, drops their `media`, and sets the page background. It dedupes on the colour, and the native half is a no-op.

The boot spinner's dots are `ink3` (`#857F73`, the same in both themes) and the 30-second "taking longer" text inherits the page's ink. On the old grey both were white, which is invisible on cream.

## Disabled on web

**Disabled on web** (already guarded): native splash/window theming, biometric, in-app purchase (upgrade routes web→Stripe portal via `upgrade_launcher`), Google, Microsoft and Apple sign-in go through the providers' own scripts in a window instead of the native SDKs, offered only where the page names a client ID (docs/web-deploy.md § Web sign-in).

## Web does not send `Idempotency-Key`

**Web does not send `Idempotency-Key`.** The API's CORS allow-list omits it, so the browser's preflight rejected every web write — while the server ignores the key anyway. `ApiClient(sendIdempotencyKey:)` defaults to `!kIsWeb`; re-enable it on web once the server allows **and** honours the header (`BACKEND.md` § Web platform CORS).

## Demo build

**Demo build.** The pre-authenticated GitHub Pages demo (`https://hillelcoren.github.io/admin/`) is produced by `tools/build_demo_web.sh` — a `--wasm` build based at `/admin/` with a baked demo token (`Env.demoApiToken` → `AuthRepository.loginWithToken`, inert in any build without the `--dart-define`). Full procedure + the `.nojekyll` requirement: `docs/setup.md` § Demo web build. CI builds web with `--wasm` so WebAssembly compatibility stays gated. The deploy script cache-busts the app entrypoints (not `canvaskit/`) — keep that if you edit `build_demo_web.sh`.
