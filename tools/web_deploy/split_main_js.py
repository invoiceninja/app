#!/usr/bin/env python3
"""Keeps the hosted tree under Cloudflare Pages' 25 MiB per-file limit:
python3 split_main_js.py <dir> [--over <bytes>] [--part <bytes>]

<dir> is the Pages tree (web.yml's `pages/`). When its main.dart.js is larger
than --over (default 24 MiB, a margin under the limit), the file is cut into
parts of at most --part bytes (default 16 MiB) in main.dart.js.parts/, named
for the whole file's hash, and main.dart.js becomes a short loader that fetches the parts, joins
their bytes and runs the result as one script. A smaller file is left alone.

Only the dart2js build is touched (Firefox and Safari; Chromium loads
main.dart.wasm), and only on Pages: the self-hosted tarball ships the file
whole. Run it after tools/stamp_web_cache_bust.sh, whose ?v= on main.dart.js
is the whole file's hash and so still changes with every build. The parts are
ordinary fetches, so the browser's HTTP cache holds them like any other file.
docs/web-deploy.md. Stdlib only.
"""

import hashlib
import json
import pathlib
import sys

MIB = 1024 * 1024
MARKER = "/* split_main_js */"
PARTS_DIR = "main.dart.js.parts"

# The Flutter loader adds main.dart.js as a <script> and waits for the app to
# call _flutter.loader.didCreateEngineInitializer, so the app may start from a
# second script added here. The parts are joined as bytes (a cut can fall
# inside a UTF-8 sequence) and resolved against this script's own URL.
LOADER = """%(marker)s
(function () {
  var parts = %(parts)s;
  var base = (document.currentScript && document.currentScript.src) || document.baseURI;
  function part(name) {
    return fetch(new URL(name, base)).then(function (response) {
      if (!response.ok) throw new Error(name + ' answered ' + response.status);
      return response.arrayBuffer();
    });
  }
  Promise.all(parts.map(part)).then(function (buffers) {
    var script = document.createElement('script');
    script.src = URL.createObjectURL(new Blob(buffers, { type: 'text/javascript' }));
    document.head.appendChild(script);
  }).catch(function (error) {
    console.error('main.dart.js could not be loaded: ' + error);
  });
})();
"""


def option(args, name, default):
    if name not in args:
        return default
    i = args.index(name)
    value = int(args[i + 1])
    del args[i : i + 2]
    return value


def main():
    args = sys.argv[1:]
    over = option(args, "--over", 24 * MIB)
    size = option(args, "--part", 16 * MIB)
    if len(args) != 1 or size <= 0:
        sys.exit(__doc__.splitlines()[1])
    main_js = pathlib.Path(args[0]) / "main.dart.js"
    data = main_js.read_bytes()
    if data.startswith(MARKER.encode()):
        sys.exit("split_main_js: main.dart.js is already split")
    mib = len(data) / MIB
    if len(data) <= over:
        print(f"main.dart.js is {mib:.1f} MiB: left whole.")
        return

    digest = hashlib.sha256(data).hexdigest()[:12]
    # One folder, so _headers can give the parts a year's cache with one rule:
    # their names carry the whole file's hash, so a new build has new URLs.
    (main_js.parent / PARTS_DIR).mkdir(exist_ok=True)
    names = []
    for n, start in enumerate(range(0, len(data), size)):
        name = f"{PARTS_DIR}/{digest}.{n}.js"
        (main_js.parent / name).write_bytes(data[start : start + size])
        names.append(name)
    main_js.write_text(LOADER % {"marker": MARKER, "parts": json.dumps(names)}, encoding="utf-8")
    print(f"main.dart.js is {mib:.1f} MiB: split into {len(names)} parts ({', '.join(names)}).")


if __name__ == "__main__":
    main()
