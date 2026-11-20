import 'dart:ui' show Color;

/// Native half of the [browser_chrome] seam: there is no browser wrapped
/// around a desktop or mobile binary, so the app's own history arrows are
/// always the only ones.
bool browserProvidesHistoryControls() => false;

/// Native half of [applyBrowserChromeColor]: there is no browser chrome to
/// paint (a desktop window's frame is `NativeWindowTheme`'s).
void applyBrowserChromeColor(Color color) {}

/// Native half of [browserUserAgent]: no browser, so no user agent.
String browserUserAgent() => '';
