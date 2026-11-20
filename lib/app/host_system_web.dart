import 'package:web/web.dart' as web;

/// Web half of the [host_system] seam: `navigator.userAgent`, or `''` when it
/// cannot be read.
String hostSystemDescription() {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    return '';
  }
}
