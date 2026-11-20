{{flutter_js}}
{{flutter_build_config}}

// Flutter 3.50's loader serves the WebAssembly build (dart2wasm + skwasm) only
// to Chromium unless told otherwise; Firefox 147+ and Safari 26.2+ have every
// feature it needs. The loader still checks each one in the browser, and its
// own Firefox floor (147) stays in force, so an older or incapable browser
// falls back to the JavaScript build (dart2js + CanvasKit) on its own.
// docs/web-platform-differences.md § WebAssembly runs in Firefox and Safari too.
//
//
// The escape hatch, for a browser that passes those checks and still crashes:
// ?renderer=canvaskit forces the JavaScript build and is remembered on this
// browser (localStorage invoiceninja.web.renderer.v1); ?renderer=auto forgets
// it. index.html's 30-second boot watchdog sets the same key when a
// WebAssembly boot never painted, so the next load tries CanvasKit.
// docs/web-platform-differences.md § A browser that crashes on WebAssembly
// has a way back.
function inRendererConfig() {
  var key = 'invoiceninja.web.renderer.v1';
  var asked = null;
  try {
    asked = new URLSearchParams(window.location.search).get('renderer');
    if (!asked) {
      // The URL strategy is hash (/#/clients), so a query typed after the
      // route lands in the hash.
      var hash = window.location.hash;
      var q = hash.indexOf('?');
      if (q !== -1) asked = new URLSearchParams(hash.slice(q + 1)).get('renderer');
    }
  } catch (e) {}
  var forced = asked === 'canvaskit' ? 'canvaskit' : null;
  try {
    if (asked === 'canvaskit') localStorage.setItem(key, 'canvaskit');
    else if (asked === 'auto') localStorage.removeItem(key);
    else if (localStorage.getItem(key) === 'canvaskit') forced = 'canvaskit';
  } catch (e) {}
  return forced ? {renderer: forced} : {};
}

// Keep the load call on one line: Deploy to Web's JS smoke test rewrites it
// with sed to force the CanvasKit build (.github/workflows/web.yml), and
// test/lint/web_bootstrap_wasm_test.dart holds the two in step. The escape
// hatch is spread LAST, so it can only ever add renderer: "canvaskit".
_flutter.loader.load({config: {wasmAllowList: {blink: true, gecko: true, webkit: true}, ...inRendererConfig()}});
