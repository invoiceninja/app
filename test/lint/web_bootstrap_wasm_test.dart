import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI lint: `web/flutter_bootstrap.js` opts Firefox and Safari into the
/// WebAssembly build, and Deploy to Web's JS smoke test can still rewrite it.
///
/// Flutter 3.50's loader allows dart2wasm on Chromium only unless the load
/// call's `wasmAllowList` says otherwise (docs/web-platform-differences.md).
/// The smoke test (`.github/workflows/web.yml`) forces the CanvasKit build by
/// sed-replacing the start of that one-line call; if the call's shape drifts,
/// the sed silently matches nothing and the following `grep -q` fails the
/// whole deploy.
void main() {
  final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
  final workflow = File('.github/workflows/web.yml').readAsStringSync();
  const callStart = '_flutter.loader.load({config: {';

  test('Firefox and Safari are allowed the WebAssembly build', () {
    final allow = RegExp(r'wasmAllowList:\s*\{([^}]*)\}').firstMatch(bootstrap);
    expect(allow, isNotNull, reason: 'no wasmAllowList in the load config');
    for (final engine in ['blink', 'gecko', 'webkit']) {
      expect(allow![1], contains('$engine: true'), reason: engine);
    }
  });

  test('the bootstrap keeps Flutter\'s two template tokens', () {
    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
  });

  test('the load call is one line starting where the smoke sed expects', () {
    final calls = bootstrap
        .split('\n')
        .where((l) => l.contains('_flutter.loader.load('))
        .toList();
    expect(calls, hasLength(1));
    expect(calls.single.trimLeft(), startsWith(callStart));
    expect(calls.single.trimRight(), endsWith('});'));
  });

  test('both smoke rewrites in web.yml match that call', () {
    final seds = RegExp(r"sed 's/([^/]+)/").allMatches(workflow).toList();
    final loaderSeds = seds.where((m) => m[1]!.contains('loader')).toList();
    expect(loaderSeds, hasLength(2));
    for (final m in loaderSeds) {
      // The workflow escapes the dots for sed; unescape them to compare.
      expect(m[1]!.replaceAll(r'\.', '.'), callStart);
    }
  });
}
