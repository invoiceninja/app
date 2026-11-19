{{flutter_js}}
{{flutter_build_config}}

// Flutter 3.50's loader serves the WebAssembly build (dart2wasm + skwasm) only
// to Chromium unless told otherwise; Firefox 147+ and Safari 26.2+ have every
// feature it needs. The loader still checks each one in the browser, and its
// own Firefox floor (147) stays in force, so an older or incapable browser
// falls back to the JavaScript build (dart2js + CanvasKit) on its own.
// docs/web-platform-differences.md § WebAssembly runs in Firefox and Safari too.
//
// Keep the load call on one line: Deploy to Web's JS smoke test rewrites it
// with sed to force the CanvasKit build (.github/workflows/web.yml), and
// test/lint/web_bootstrap_wasm_test.dart holds the two in step.
_flutter.loader.load({config: {wasmAllowList: {blink: true, gecko: true, webkit: true}}});
