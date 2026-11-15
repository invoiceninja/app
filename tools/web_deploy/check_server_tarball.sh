#!/usr/bin/env bash
set -euo pipefail

# The listing checks the backend's react_release.yml runs before it unpacks
# the self-hosted tarball (docs/web-deploy.md § Going live), run here first so
# a build the server would refuse fails this workflow instead of shipping a
# server release without the new app. Keep the patterns identical to the
# backend's. It extracts only public/flutter and the boot page, which must be
# present and agree on the build's folder.
#
# Usage: tools/web_deploy/check_server_tarball.sh <invoiceninja-web-x.y.z.tar.gz>

archive="${1:?usage: check_server_tarball.sh <archive>}"
fail() { echo "!! $1" >&2; exit 1; }
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
if grep -Ei '\.(php[0-9]?|pht|phtml|phar|phps|cgi|pl|shtml)([^[:alnum:]]|$)|^public/.*\.html?([^[:alnum:]]|$)' <<< "$list"; then
  fail "a file the web server could run"
fi
# The boot page names the build's folder (<base href="__IN_BASE_HREF__<id>/">), and the backend
# serves the app only when that folder holds the bootstrap (Ninja::flutterWebBuildId).
grep -qxF resources/views/flutter/index.html <<< "$list" || fail "no resources/views/flutter/index.html"
id=$(tar -xzOf "$archive" resources/views/flutter/index.html \
  | sed -nE 's#.*<base href="__IN_BASE_HREF__([0-9a-f]{8,64})/">.*#\1#p' | head -1)
[ -n "$id" ] || fail "a boot page that names no build folder"
grep -qxF "public/flutter/$id/flutter_bootstrap.js" <<< "$list" || fail "no public/flutter/$id/flutter_bootstrap.js"
echo "The server will accept $archive."
