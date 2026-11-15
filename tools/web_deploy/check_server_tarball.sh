#!/usr/bin/env bash
set -euo pipefail

# The checks the backend's react_release.yml ("Prepare Flutter FrontEnd") runs
# before it installs the self-hosted tarball (docs/web-deploy.md § Going live),
# run here first so a build the server would refuse fails this workflow instead
# of shipping a server release without the new app. Keep every pattern and test
# identical to the backend's: the listing checks, then the same extraction of
# public/flutter and the boot page, and the same tests on what landed.
#
# Usage: tools/web_deploy/check_server_tarball.sh <invoiceninja-web-x.y.z.tar.gz>

archive="${1:?usage: check_server_tarball.sh <archive>}"
fail() { echo "!! $1" >&2; exit 1; }
work=$(mktemp -d)
trap 'chmod -R u+rwX "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

# Listed once: `tar | grep -q` would die of SIGPIPE under pipefail.
list=$(tar -tzf "$archive") || fail "can't be read"
tar -tvzf "$archive" | awk '$1 !~ /^[-d]/ { bad = 1 } END { exit bad }' \
  || fail "a link or a special file"
if grep -E '^/|(^|/)\.\.?(/|$)' <<< "$list"; then
  fail "an absolute or relative path"
fi
if grep -E '/\.' <<< "$list" | grep -Ev '/\.gitkeep$'; then
  fail "a dotfile"
fi
if grep -E '^public/' <<< "$list" | grep -Ev '/$' \
  | grep -Eiv '(/[^/.]+|/\.gitkeep|\.(js|mjs|wasm|json|css|png|jpg|jpeg|gif|webp|svg|ico|ttf|otf|woff|woff2|frag|bin|txt|map))$'; then
  fail "a file type a web build doesn't have, under public/"
fi
if grep -Ei '\.(php[0-9]*|pht|phtml|phar|phps|cgi|fcgi|pl|plx|ppl|perl|py|rb|sh|shtml?|stm|html?|asp|aspx|jsp|cfm)([^[:alnum:]]|$)' <<< "$list" \
  | grep -Ev '^resources/views/flutter/index\.html$'; then
  fail "a name the web server could run"
fi

mkdir "$work/out"
tar -xzf "$archive" -C "$work/out" --no-same-owner --no-same-permissions \
  public/flutter resources/views/flutter/index.html \
  || fail "a missing part"
chmod -R u+rwX,go+rX "$work/out" || fail "files that can't be made readable"
page="$work/out/resources/views/flutter/index.html"
[ -f "$page" ] || fail "a boot page that isn't a file"
awk '{ n += gsub(/<[Bb][Aa][Ss][Ee][^A-Za-z0-9_-]/, "") } END { exit n != 1 }' "$page" \
  || fail "a boot page without exactly one <base>"
id=$(sed -nE 's#.*<base href="__IN_BASE_HREF__([0-9a-f]{8,64})/">.*#\1#p' "$page") || id=""
[ -n "$id" ] && [ -f "$work/out/public/flutter/$id/flutter_bootstrap.js" ] \
  || fail "a boot page that names no build folder holding flutter_bootstrap.js"
echo "The server will accept $archive."
