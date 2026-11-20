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

  // The escape hatch (docs/web-platform-differences.md § A browser that
  // crashes on WebAssembly has a way back): ?renderer=canvaskit forces the
  // JavaScript build and is remembered, ?renderer=auto forgets it, and the
  // 30-second boot watchdog sets the same key after a WebAssembly boot that
  // never painted.
  group('the CanvasKit escape hatch', () {
    const key = 'invoiceninja.web.renderer.v1';
    final index = File('web/index.html').readAsStringSync();

    test('the bootstrap reads ?renderer= and the remembered key', () {
      expect(bootstrap, contains("'$key'"));
      expect(bootstrap, contains("get('renderer')"));
      expect(bootstrap, contains("asked === 'canvaskit'"));
      expect(bootstrap, contains("asked === 'auto'"));
      expect(bootstrap, contains('localStorage.removeItem(key)'));
      expect(bootstrap, contains('{renderer: forced}'));
    });

    test('it is spread last, so the smoke rewrite still forces CanvasKit', () {
      final call = bootstrap
          .split('\n')
          .singleWhere((l) => l.contains('_flutter.loader.load('))
          .trim();
      // The smoke sed inserts `renderer: "canvaskit", ` at the front; a later
      // `renderer` key would override it, a spread of `{}` cannot.
      expect(call, endsWith('...inRendererConfig()}});'));
      expect(call, isNot(contains('renderer:')));
    });

    test('the watchdog pins a WebAssembly boot that never painted', () {
      expect(index, contains("var RENDERER_KEY = '$key';"));
      expect(index, contains('if (bootIsWasm())'));
      // Pinned for this deploy only: the value names the build ...
      expect(
        index,
        contains('localStorage.setItem(RENDERER_KEY, watchdogTag())'),
      );
      // ... and unpinned if that boot paints after all.
      expect(index, contains('localStorage.removeItem(RENDERER_KEY)'));
    });

    test('a watchdog fallback lasts only for the deploy that set it', () {
      // index.html and flutter_bootstrap.js name the deploy the same way,
      // and the bootstrap drops a fallback another deploy set.
      const tag =
          "return 'watchdog ' + (s ? s.src : '') + ' ' + document.baseURI;";
      expect(index, contains(tag));
      expect(bootstrap, contains(tag));
      expect(bootstrap, contains('stored === inBuildTag()'));
      expect(
        bootstrap,
        contains('else if (stored) localStorage.removeItem(key)'),
      );
    });
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
