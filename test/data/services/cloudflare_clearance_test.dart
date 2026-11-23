import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:admin/data/services/api_client.dart';
import 'package:admin/data/services/api_credentials.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/cloudflare/cloudflare_clearance.dart';
import 'package:admin/data/services/cloudflare/cloudflare_clearance_client.dart';
import 'package:admin/data/services/password_cache.dart';

/// invoiceninja/invoiceninja#13484: a self-hosted server behind a Cloudflare
/// zone that challenges visitors answers the app with "Verify you are human"
/// (`cf-mitigated: challenge`) instead of JSON. docs/cloudflare-challenge.md.
void main() {
  const server = 'https://invoice.example.com';
  final api = Uri.parse('$server/api/v1/refresh?first_load=true');

  http.Response challenge([int status = 403]) => http.Response(
    '<html><title>Just a moment...</title></html>',
    status,
    headers: {
      'cf-mitigated': 'challenge',
      'cf-ray': '8f1a2b3c4d5e6f70-AMS',
      'content-type': 'text/html',
    },
  );

  CloudflareClearance clearance({Map<String, String>? cookies, DateTime? at}) =>
      CloudflareClearance(
        userAgent: 'Mozilla/5.0 (iPhone) AppleWebKit Safari',
        cookies: cookies ?? const {'cf_clearance': 'abc', '__cf_bm': 'bm1'},
        obtainedAt: at ?? DateTime(2026, 11, 23, 12),
      );

  group('isCloudflareChallenge', () {
    test('needs both cf-mitigated and cf-ray — a proxy that is not '
        'Cloudflare cannot make a forwarded write look unsent', () {
      expect(
        isCloudflareChallenge({'cf-mitigated': 'challenge', 'cf-ray': 'x'}),
        isTrue,
      );
      expect(isCloudflareChallenge({'cf-mitigated': 'challenge'}), isFalse);
      expect(isCloudflareChallenge({'cf-ray': 'x'}), isFalse);
    });
  });

  group('CloudflareClearanceClient', () {
    test('a challenge is its own not-sent error with its Ray ID, and the '
        'origin waits', () async {
      final store = CloudflareClearanceStore();
      final client = CloudflareClearanceClient(
        MockClient((_) async => challenge(503)),
        store,
      );
      await expectLater(
        client.get(api),
        throwsA(
          isA<CloudflareChallengeException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.rayId, 'ray', '8f1a2b3c4d5e6f70-AMS')
              .having((e) => e.url, 'url', api),
        ),
      );
      final waiting = store.outstandingFor(Uri.parse(server))!;
      expect(waiting.url.toString(), '$server/api/v1/refresh');
      expect(waiting.wait, CloudflareWait.challenged);
      expect(
        CloudflareChallengeException(url: api, statusCode: 403),
        isA<RequestNotSentException>(),
        reason: 'the outbox re-parks it, never marks it failed or unconfirmed',
      );
    });

    test('an origin without a clearance is sent exactly as before', () async {
      late Map<String, String> sent;
      final client = CloudflareClearanceClient(
        MockClient((req) async {
          sent = req.headers;
          return http.Response('{}', 200);
        }),
        CloudflareClearanceStore(),
      );
      await client.get(api, headers: {'user-agent': 'Dart'});
      expect(sent['user-agent'], 'Dart');
      expect(sent.containsKey('cookie'), isFalse);
    });

    test('a passed check sends its cookies and the web view\'s User-Agent — '
        'to that origin only', () async {
      final store = CloudflareClearanceStore()
        ..adopt(Uri.parse(server), clearance());
      final sent = <Uri, Map<String, String>>{};
      final client = CloudflareClearanceClient(
        MockClient((req) async {
          sent[req.url] = req.headers;
          return http.Response('{}', 200);
        }),
        store,
      );
      await client.get(api, headers: {'cookie': 'XSRF=1'});
      final other = Uri.parse('https://other.example.com/api/v1/ping');
      await client.get(other);

      expect(
        sent[api]!['user-agent'],
        'Mozilla/5.0 (iPhone) AppleWebKit Safari',
      );
      expect(sent[api]!['cookie'], 'XSRF=1; cf_clearance=abc; __cf_bm=bm1');
      expect(sent[other]!.containsKey('cookie'), isFalse);
    });

    test('a User-Agent-only clearance adds no empty Cookie header', () async {
      late Map<String, String> sent;
      final store = CloudflareClearanceStore()
        ..adopt(Uri.parse(server), clearance(cookies: const {}));
      final client = CloudflareClearanceClient(
        MockClient((req) async {
          sent = req.headers;
          return http.Response('{}', 200);
        }),
        store,
      );
      await client.get(api);
      expect(sent.containsKey('cookie'), isFalse);
      expect(sent['user-agent'], startsWith('Mozilla/'));
    });

    test('while an origin waits, requests fail at once but for one real '
        'probe every probeEvery — no burst per drain', () async {
      var now = DateTime(2026, 11, 23, 12);
      final store = CloudflareClearanceStore(now: () => now);
      var calls = 0;
      final client = CloudflareClearanceClient(
        MockClient((_) async {
          calls++;
          return challenge();
        }),
        store,
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          client.get(api),
          throwsA(isA<CloudflareChallengeException>()),
        );
      }
      expect(calls, 1);
      now = now.add(CloudflareClearanceStore.probeEvery);
      await expectLater(
        client.get(api),
        throwsA(isA<CloudflareChallengeException>()),
      );
      expect(calls, 2);
    });

    test('an answer without a challenge ends the wait — the device reached a '
        'network the zone allows', () async {
      var now = DateTime(2026, 11, 23, 12);
      final store = CloudflareClearanceStore(now: () => now);
      var challenged = true;
      final client = CloudflareClearanceClient(
        MockClient(
          (_) async => challenged ? challenge() : http.Response('{}', 200),
        ),
        store,
      );
      await expectLater(client.get(api), throwsA(anything));
      challenged = false;
      now = now.add(CloudflareClearanceStore.probeEvery);
      await client.get(api);
      expect(store.outstandingFor(api), isNull);
    });

    test('a clearance refused right after its pass is "refused", not a new '
        'check — the loop a TLS-bound zone would start', () async {
      var now = DateTime(2026, 11, 23, 12);
      final store = CloudflareClearanceStore(now: () => now)
        ..adopt(Uri.parse(server), clearance(at: now));
      final client = CloudflareClearanceClient(
        MockClient((_) async => challenge()),
        store,
      );
      now = now.add(const Duration(seconds: 5));
      await expectLater(client.get(api), throwsA(anything));
      expect(store.clearanceFor(api), isNull, reason: 'never sent again');
      expect(store.outstandingFor(api)!.wait, CloudflareWait.refused);
    });

    test('one that carried even one accepted request expired — a new '
        'network soon after the pass is not "refused"', () async {
      var now = DateTime(2026, 11, 23, 12);
      final store = CloudflareClearanceStore(now: () => now)
        ..adopt(Uri.parse(server), clearance(at: now));
      var challenged = false;
      final client = CloudflareClearanceClient(
        MockClient(
          (_) async => challenged ? challenge() : http.Response('{}', 200),
        ),
        store,
      );
      await client.get(api);
      challenged = true;
      now = now.add(const Duration(minutes: 1));
      await expectLater(client.get(api), throwsA(anything));
      expect(store.outstandingFor(api)!.wait, CloudflareWait.expired);
    });

    test('"refused" said once turns back into an ordinary challenge, so the '
        'next tap can open the check', () {
      final now = DateTime(2026, 11, 23, 12);
      final held = clearance(at: now);
      final store = CloudflareClearanceStore(now: () => now)
        ..adopt(api, held)
        ..noteChallenge(api, sent: held);
      expect(store.outstandingFor(api)!.wait, CloudflareWait.refused);
      store.acknowledgeRefused(api);
      expect(store.outstandingFor(api)!.wait, CloudflareWait.challenged);
    });

    test('one that worked a while simply expired', () async {
      var now = DateTime(2026, 11, 23, 12);
      final store = CloudflareClearanceStore(now: () => now)
        ..adopt(Uri.parse(server), clearance(at: now));
      final client = CloudflareClearanceClient(
        MockClient((_) async => challenge()),
        store,
      );
      now = now.add(const Duration(minutes: 31));
      await expectLater(client.get(api), throwsA(anything));
      expect(store.outstandingFor(api)!.wait, CloudflareWait.expired);
    });

    test(
      'Cloudflare\'s rotated cookies are kept; the server\'s are not',
      () async {
        final store = CloudflareClearanceStore()
          ..adopt(Uri.parse(server), clearance());
        final client = CloudflareClearanceClient(
          MockClient(
            (_) async => http.Response(
              '{}',
              200,
              headers: {
                'set-cookie':
                    '__cf_bm=bm2; path=/; expires=Sun, 23-Nov-26 13:00:00 GMT; '
                    'HttpOnly, laravel_session=s3cret; path=/',
              },
            ),
          ),
          store,
        );
        await client.get(api);
        expect(store.clearanceFor(api)!.cookies, {
          'cf_clearance': 'abc',
          '__cf_bm': 'bm2',
        });
      },
    );
  });

  group('CloudflareClearanceStore', () {
    test('a burst of challenged requests asks once', () {
      var notified = 0;
      final store = CloudflareClearanceStore()..addListener(() => notified++);
      for (var i = 0; i < 5; i++) {
        store.noteChallenge(api);
      }
      expect(notified, 1);
      store.adopt(api, clearance());
      expect(store.outstandingFor(api), isNull);
      expect(notified, 2);
    });

    test('a request that left before a new check passed cannot throw the '
        'new clearance away, or reopen the wait', () {
      final old = clearance(cookies: const {'cf_clearance': 'old'});
      final fresh = clearance(cookies: const {'cf_clearance': 'new'});
      final store = CloudflareClearanceStore()..adopt(api, fresh);

      store.noteChallenge(api, sent: old);
      store.noteChallenge(api); // sent with none, before the pass
      expect(store.clearanceFor(api), same(fresh));
      expect(store.outstandingFor(api), isNull);

      store.noteResponseCookies(api, old, const ['__cf_bm=stale']);
      expect(store.clearanceFor(api)!.cookies, {'cf_clearance': 'new'});
    });

    test('only https self-hosted servers are offered the check', () {
      final store = CloudflareClearanceStore();
      expect(store.canVerify(api), isTrue);
      expect(
        store.canVerify(Uri.parse('http://invoice.example.com/api/v1')),
        isFalse,
        reason: 'a network attacker can inject the header over http',
      );
      expect(
        store.canVerify(Uri.parse('https://invoicing.co/api/v1')),
        isFalse,
      );
      expect(
        store.canVerify(Uri.parse('https://demo.invoiceninja.com./api/v1')),
        isFalse,
      );
    });

    test(
      'an origin is scheme, host and port, with default ports filled in',
      () {
        expect(
          cloudflareOrigin(Uri.parse('https://Invoice.Example.com/x')),
          'https://invoice.example.com:443',
        );
        expect(
          cloudflareOrigin(Uri.parse('https://invoice.example.com:443/y')),
          'https://invoice.example.com:443',
        );
        expect(
          cloudflareOrigin(Uri.parse('http://10.0.0.2:8080/')),
          'http://10.0.0.2:8080',
        );
      },
    );

    test('the check page is the server\'s ping, under its install path', () {
      expect(
        cloudflareCheckUrl(
          Uri.parse('$server/api/v1/invoices/abc/download'),
        ).toString(),
        '$server/api/v1/ping',
      );
      expect(
        cloudflareCheckUrl(
          Uri.parse('https://example.com/ninja/api/v1/login'),
        ).toString(),
        'https://example.com/ninja/api/v1/ping',
      );
    });

    test('a folded Set-Cookie splits at cookies, not inside Expires', () {
      expect(
        splitSetCookieHeader(
          'a=1; expires=Sun, 23-Nov-26 13:00:00 GMT, b=2; path=/',
        ),
        ['a=1; expires=Sun, 23-Nov-26 13:00:00 GMT', 'b=2; path=/'],
      );
      expect(splitSetCookieHeader(null), isEmpty);
    });

    test('only Cloudflare\'s cookies are replayed', () {
      expect(isCloudflareCookie('cf_clearance'), isTrue);
      expect(isCloudflareCookie('__cf_bm'), isTrue);
      expect(isCloudflareCookie('__cflb'), isTrue);
      expect(isCloudflareCookie('_cfuvid'), isTrue);
      expect(isCloudflareCookie('laravel_session'), isFalse);
      expect(isCloudflareCookie('XSRF-TOKEN'), isFalse);
    });

    test('only a browser engine\'s User-Agent is adopted', () {
      expect(isUsableUserAgent('Mozilla/5.0 (iPhone) AppleWebKit'), isTrue);
      expect(isUsableUserAgent('Dart/3.10 (dart:io)'), isFalse);
      expect(isUsableUserAgent('Mozilla/5.0\r\nX-Evil: 1'), isFalse);
      expect(isUsableUserAgent('Mozilla/${'x' * 600}'), isFalse);
    });
  });

  group('ApiClient over the clearance client', () {
    ApiClient client(http.Client transport, {VoidCallback? onUnauthorized}) =>
        ApiClient(
          credentials: ValueNotifier<ApiCredentials?>(
            const ApiCredentials(baseUrl: server, token: 't'),
          ),
          passwordCache: PasswordCache(),
          onUnauthorized: () async => onUnauthorized?.call(),
          httpClient: CloudflareClearanceClient(
            transport,
            CloudflareClearanceStore(),
          ),
        );

    test('a challenged 403 never reaches the 401 / dead-token path, and its '
        'HTML is never read as JSON', () async {
      var signedOut = false;
      final c = client(
        MockClient((_) async => challenge()),
        onUnauthorized: () => signedOut = true,
      );
      await expectLater(
        c.getOne('/api/v1/ping'),
        throwsA(isA<CloudflareChallengeException>()),
      );
      expect(signedOut, isFalse);
    });

    test('a challenged write stays "not sent" though its body went out — '
        'Cloudflare never forwarded it', () async {
      final c = client(
        MockClient((req) async {
          expect(req.body, isNotEmpty);
          return challenge();
        }),
      );
      await expectLater(
        c.mutate(
          method: 'PUT',
          path: '/api/v1/clients/c1',
          idempotencyKey: 'k',
          body: const {'name': 'Acme'},
        ),
        throwsA(isA<CloudflareChallengeException>()),
      );
    });
  });
}
