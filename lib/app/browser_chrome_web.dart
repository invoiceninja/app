import 'dart:ui' show Color;

import 'package:web/web.dart' as web;

/// Web half of the [browser_chrome] seam.
///
/// `browser` and `minimal-ui` are the two display modes that keep the address
/// bar / navigation controls on screen. `standalone` and `fullscreen` — an
/// installed PWA, which this app's `manifest.json` asks for — show neither, so
/// the in-app arrows have to stay.
///
/// Both failure directions are deliberate: when the query cannot be answered
/// we report `false`, which *keeps* the in-app arrows. A redundant pair of
/// arrows is a cosmetic wart; missing ones strand a touch user who followed a
/// cross-entity link with no keyboard and no toolbar.
bool browserProvidesHistoryControls() {
  try {
    return web.window.matchMedia('(display-mode: browser)').matches ||
        web.window.matchMedia('(display-mode: minimal-ui)').matches;
  } catch (_) {
    return false;
  }
}

/// The browser's `navigator.userAgent`, or `''` when it cannot be read —
/// which the banner (`webAppBannerLinks`) reads as "not a Chromebook".
String browserUserAgent() {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    return '';
  }
}

/// The last colour [applyBrowserChromeColor] wrote, so a rebuild that changes
/// nothing touches no DOM.
String? _chromeColor;

/// Paints the browser's own chrome in the app's background colour: every
/// `<meta name="theme-color">` (the toolbar / title-bar tint in Safari, an
/// installed PWA and Android Chrome) and the page background (which Safari
/// samples for its toolbar when it ignores the meta tag).
///
/// The boot page ships the default light / dark pair keyed on the system
/// theme. Only the running app knows the user's choice — an explicit dark
/// theme on a light system, or the White / Grey light backgrounds — so the
/// app overrides both here and drops the tags' `media` so the system theme no
/// longer picks between them.
void applyBrowserChromeColor(Color color) {
  final hex =
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  if (hex == _chromeColor) return;
  _chromeColor = hex;
  try {
    final document = web.document;
    final metas = document.querySelectorAll('meta[name="theme-color"]');
    if (metas.length == 0) {
      final meta = document.createElement('meta') as web.HTMLMetaElement
        ..name = 'theme-color'
        ..content = hex;
      document.head?.append(meta);
    } else {
      for (var i = 0; i < metas.length; i++) {
        final meta = metas.item(i) as web.HTMLMetaElement;
        meta.removeAttribute('media');
        meta.content = hex;
      }
    }
    (document.documentElement as web.HTMLElement?)?.style.backgroundColor = hex;
    document.body?.style.backgroundColor = hex;
  } catch (_) {
    // Cosmetic: a page without a head or body keeps the boot page's colours.
  }
}
