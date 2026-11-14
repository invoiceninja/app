#!/usr/bin/env bash
set -euo pipefail

# The listing checks the backend's react_release.yml runs before it unpacks
# the self-hosted tarball (docs/web-deploy.md § Going live), run here first so
# a build the server would refuse fails this workflow instead of shipping a
# server release without the new app. Keep the patterns identical to the
# backend's. It extracts only public/flutter and the boot page, which must be
# present.
#
# Usage: tools/web_deploy/check_server_tarball.sh <invoiceninja-web-x.y.z.tar.gz>

archive="${1:?usage: check_server_tarball.sh <archive>}"
fail() { echo "!! $1" >&2; exit 1; }
# Listed once: `tar | grep -q` would die of SIGPIPE under pipefail.
list=$(tar -tzf "$archive") || fail "can't be read"

tar -tvzf "$archive" | awk '$1 !~ /^[-d]/ { bad = 1 } END { exit bad }' \
  || fail "a link or a special file"
if grep -E '(^|/)\.\.?(/|$)' <<< "$list"; then
  fail "a relative path"
fi
if grep -E '/\.' <<< "$list" | grep -Ev '/\.gitkeep$'; then
  fail "a dotfile"
fi
if grep -Ei '\.(php[0-9]?|pht|phtml|phar|phps|cgi|pl|shtml)(\.|/|$)|^public/.*\.html?$' <<< "$list"; then
  fail "a file the web server could run"
fi
for part in public/flutter/flutter_bootstrap.js resources/views/flutter/index.html; do
  grep -qxF "$part" <<< "$list" || fail "no $part"
done
echo "The server will accept $archive."
