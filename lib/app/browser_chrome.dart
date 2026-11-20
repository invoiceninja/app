/// Whether the host browser is showing its own back/forward controls.
///
/// Conditional-import seam in the house style (default file = web, the
/// `dart.library.io` override = native — see CLAUDE.md § Web).
///
/// Exists so the sidebar can drop its own history arrows as duplicated chrome
/// in an ordinary tab **without** dropping them in an installed PWA, where
/// `manifest.json`'s `"display": "standalone"` means there is no toolbar at
/// all and those arrows are the only way back.
///
/// Also paints the browser's toolbar tint and page background in the app's
/// background colour (`applyBrowserChromeColor`), following the user's theme,
/// and reads the browser's user agent (`browserUserAgent`), which is how the
/// web banner tells a Chromebook from Linux.
library;

export 'package:admin/app/browser_chrome_web.dart'
    if (dart.library.io) 'package:admin/app/browser_chrome_io.dart';
