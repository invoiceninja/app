#!/usr/bin/env bash
set -euo pipefail

# Writes the invoicing.co landing page into an invoiceninja/invoiceninja
# checkout, where it is committed (docs/web-deploy.md § The landing page):
# hosted deploys with a git pull, so the page has to be in the backend's git.
# Replaces public/landing/ whole, so a renamed or dropped asset leaves nothing
# behind. Review the diff and commit it there as a backend PR.
#
# Usage: tools/web_deploy/export_landing.sh <invoiceninja checkout>

server="${1:?usage: export_landing.sh <invoiceninja checkout>}"
[ -f "$server/artisan" ] && [ -d "$server/resources/views" ] \
  || { echo "!! $server is not an invoiceninja checkout" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$server/public/landing"
mkdir -p "$server/resources/views/landing"
python3 "$here/render_landing.py" --assets-base /landing/ \
  --assets-dir "$server/public/landing" -o "$server/resources/views/landing/index.html"
echo "Wrote the landing page into $server. Review with: git -C '$server' status"
