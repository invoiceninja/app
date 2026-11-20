import 'dart:io';

/// Native half of the [host_system] seam: `Platform.operatingSystemVersion`
/// (e.g. `Version 26.4 (Build 25E246)` on macOS), or `''` when it cannot be
/// read.
String hostSystemDescription() {
  try {
    return Platform.operatingSystemVersion;
  } catch (_) {
    return '';
  }
}
