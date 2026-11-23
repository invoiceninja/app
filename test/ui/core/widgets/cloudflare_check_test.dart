import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/core/widgets/cloudflare_check.dart';

/// How the Cloudflare check screen decides it passed (invoiceninja/invoiceninja#13484,
/// docs/cloudflare-challenge.md) — pure, so no web view is needed.
void main() {
  group('the check page', () {
    test('reads the page state each web view returns', () {
      const json = '{"o":"https://invoice.example.com","c":false,"r":true}';
      for (final raw in <Object>[
        json,
        '"${json.replaceAll('"', r'\"')}"', // Android: quoted again
        {'o': 'https://invoice.example.com', 'c': false, 'r': true}, // WebView2
      ]) {
        final page = CloudflarePageState.parse(raw)!;
        expect(page.origin, 'https://invoice.example.com', reason: '$raw');
        expect(page.challenge, isFalse);
        expect(page.loaded, isTrue);
      }
      expect(CloudflarePageState.parse('not json'), isNull);
      expect(CloudflarePageState.parse(null), isNull);
    });

    test('unquotes the User-Agent Android returns JSON-encoded', () {
      expect(
        unquoteJavaScriptString('"Mozilla/5.0 \\"x\\""'),
        'Mozilla/5.0 "x"',
      );
      expect(unquoteJavaScriptString('Mozilla/5.0'), 'Mozilla/5.0');
      expect(unquoteJavaScriptString(42), isNull);
    });

    test('passes on the server\'s own page holding cf_clearance — never on '
        'the challenge, another origin, or a page still loading', () {
      const origin = 'https://invoice.example.com';
      CloudflarePageState page({
        String o = origin,
        bool c = false,
        bool r = true,
      }) => CloudflarePageState(origin: o, challenge: c, loaded: r);
      const cookie = {'cf_clearance': 'x'};

      final probe = CloudflareCheckProbe(origin: origin);
      expect(probe.passed(null, cookie), isFalse);
      expect(probe.passed(page(o: 'about:blank'), cookie), isFalse);
      expect(probe.passed(page(r: false), cookie), isFalse);
      expect(probe.passed(page(c: true), cookie), isFalse);
      expect(probe.passed(page(), cookie), isTrue);
    });

    test('a zone that never challenged the web view passes on the '
        'User-Agent alone, after a few clean looks', () {
      const origin = 'https://invoice.example.com';
      const clean = CloudflarePageState(
        origin: origin,
        challenge: false,
        loaded: true,
      );
      const challenged = CloudflarePageState(
        origin: origin,
        challenge: true,
        loaded: true,
      );
      final probe = CloudflareCheckProbe(origin: origin, graceProbes: 3);
      expect(probe.passed(clean, const {}), isFalse);
      expect(probe.passed(challenged, const {}), isFalse, reason: 'resets');
      expect(probe.passed(clean, const {}), isFalse);
      expect(probe.passed(clean, const {}), isFalse);
      expect(probe.passed(clean, const {}), isTrue);
    });
  });
}
