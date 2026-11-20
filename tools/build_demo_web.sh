#!/usr/bin/env bash
set -euo pipefail

# Build (and optionally deploy) the pre-authenticated demo web app.
#
# Produces the Flutter WASM web build, based at /admin/ for GitHub Pages and
# pre-authenticated against demo.invoiceninja.com via the public system token
# `TOKEN` (see docs/probing-the-demo-api.md). On a fresh browser the build
# boots straight to the dashboard instead of /login — see `Env.demoApiToken`
# and the bootstrap hook in lib/main.dart.
#
# Usage:
#   tools/build_demo_web.sh [deploy_dir]
#
#   deploy_dir   Directory to rsync build/web/ into. Defaults to the sibling
#                checkout ../hillelcoren.github.io/admin. Pass "-" to build
#                only and skip the deploy.
#
# After deploying, commit & push the deploy repo to publish (GitHub Pages).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

deploy_dir="${1:-$repo_root/../hillelcoren.github.io/admin}"

echo "==> flutter build web --wasm (demo, base-href /admin/)"
# --no-web-resources-cdn bundles the CanvasKit/skwasm engine into build/web/
# (served from /admin/) instead of fetching it from www.gstatic.com at runtime,
# so the demo loads entirely from our own origin.
# --pwa-strategy=none: the bootstrap registers no service worker. Flutter's is
# only a stub that unregisters itself, but it reloads the page as it goes, and
# a reload during boot can wedge the web database (docs/web-deploy.md).
flutter build web --wasm --release \
  --no-web-resources-cdn \
  --pwa-strategy=none \
  --base-href /admin/ \
  --dart-define=IN_DEMO_API_TOKEN=TOKEN \
  --dart-define=IN_GIT_COMMIT="$(git rev-parse --short HEAD)"

# Cache-bust the app entrypoints so a single browser refresh picks up a new
# deploy. GitHub Pages serves every file with `Cache-Control: max-age=600` and
# can't set custom headers, and the Flutter entry files have fixed names — so a
# fresh deploy would otherwise stay hidden behind the browser cache for up to
# 10 minutes. Stamp a content-hash token onto `flutter_bootstrap.js` and the app
# entrypoints (main.dart.{wasm,mjs,js}) as a `?v=` query: a new build yields
# brand-new URLs no cache can satisfy, so one refresh — which revalidates
# index.html via the Pages ETag — loads the new bootstrap + app code. The engine
# files under canvaskit/ are immutable per Flutter SDK, so they're left as-is
# (busting them every deploy would force a needless multi-MB re-download).
# The bootstrap half is shared with Deploy to Web (tools/stamp_web_cache_bust.sh);
# index.html is the demo's own page, so its stamp stays here.
token="$("$repo_root/tools/stamp_web_cache_bust.sh" build/web)"
V="$token" perl -pi -e 's#src="flutter_bootstrap\.js"#src="flutter_bootstrap.js?v=$ENV{V}"#' \
  build/web/index.html
# Fail loudly if a future Flutter output change breaks the rewrite above,
# rather than silently shipping an un-busted (cache-stale) build.
grep -q "src=\"flutter_bootstrap.js?v=$token\"" build/web/index.html \
  || { echo "!! cache-bust failed: index.html not stamped" >&2; exit 1; }

# Pages' 100 MB-per-file ceiling is far off, but the demo is also where the
# hosted split is tried by the browsers that load main.dart.js: an older
# Firefox or Safari the loader sends to the JavaScript build, or any browser
# opened with ?renderer=canvaskit (docs/web-deploy.md § On Pages main.dart.js
# ships in parts).
python3 "$repo_root/tools/web_deploy/split_main_js.py" build/web

# Every file but the page lives in b/<id>/, <id> a hash of the whole build, and
# the page's <base href> names that folder: the layout the self-hosted server
# uses (docs/web-deploy.md). GitHub Pages caches every file for ten minutes and
# takes no headers, and only the entrypoints carry a ?v=, so a build on a new
# Flutter used to meet the last one's cached engine (canvaskit/skwasm.*) and
# stop at a LinkError until the cache ran out. A new build now has new URLs for
# everything; only index.html is ever revalidated.
build_id="$(cd build/web && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-12)"
perl -pi -e 's#<base href="/admin/">#<base href="/admin/b/'"$build_id"'/">#' build/web/index.html
grep -q "<base href=\"/admin/b/$build_id/\">" build/web/index.html \
  || { echo "!! index.html has no <base href=\"/admin/\"> to point at the build folder" >&2; exit 1; }
# An installed copy opens the site, not the build folder.
python3 - build/web/manifest.json <<'PY'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path))
manifest["start_url"] = "/admin/"
manifest["scope"] = "/admin/"
json.dump(manifest, open(path, "w"), indent=2)
PY

if [[ "$deploy_dir" == "-" ]]; then
  echo "==> build complete: build/web/ (build $build_id, deploy skipped)"
  exit 0
fi

if [[ ! -d "$deploy_dir" ]]; then
  echo "!! deploy dir not found: $deploy_dir" >&2
  echo "   build is in build/web/ — copy it manually or pass a valid path." >&2
  exit 1
fi

echo "==> deploying build $build_id to $deploy_dir"
mkdir -p "$deploy_dir/b"
rsync -a --delete --exclude /index.html "$repo_root/build/web/" "$deploy_dir/b/$build_id/"
# The previous build stays, for a page a browser cached in the last ten
# minutes; older ones go, and so does everything from before this layout.
# (The directory's mtime is the build's: rsync -a carries it over.)
touch "$deploy_dir/b/$build_id"
ls -1t "$deploy_dir/b" | tail -n +3 | while read -r old; do rm -rf "${deploy_dir:?}/b/$old"; done
find "$deploy_dir" -mindepth 1 -maxdepth 1 ! -name b -exec rm -rf {} +
cp "$repo_root/build/web/index.html" "$deploy_dir/index.html"
# An earlier deploy's service worker is registered at /admin/ and looks here
# for its update: the stub that unregisters it.
cp "$repo_root/build/web/flutter_service_worker.js" "$deploy_dir/" 2>/dev/null || true

# GitHub Pages runs Jekyll, which drops files whose names start with "_" —
# including assets/i18n/_app_pending.json (app-local strings). A .nojekyll at
# the Pages repo root disables Jekyll. Warn if it is missing.
pages_root="$(cd "$deploy_dir/.." && pwd)"
if [[ ! -f "$pages_root/.nojekyll" ]]; then
  echo "!! WARNING: $pages_root/.nojekyll is missing." >&2
  echo "   GitHub Pages will strip _app_pending.json and untranslated keys" >&2
  echo "   will render raw. Create an empty .nojekyll at that repo root." >&2
fi

echo "==> done. To publish, commit & push the deploy repo:"
echo "     git -C \"$pages_root\" add ."
echo "     git -C \"$pages_root\" commit -m 'Update admin demo build'"
echo "     git -C \"$pages_root\" push"
