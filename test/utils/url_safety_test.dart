import 'package:admin/utils/url_safety.dart';
import 'package:flutter_test/flutter_test.dart';

/// The predicate gates server-controlled URLs before they're handed to
/// `Image.network`. Loose acceptance lets a hostile server downgrade to
/// http or point at internal addresses — both are tracking/disclosure
/// vectors even when no creds are involved.

void main() {
  group('isSafeHttpsUrl', () {
    test('accepts a plain https URL', () {
      expect(isSafeHttpsUrl('https://cdn.invoiceninja.com/logo.png'), isTrue);
    });
    test('accepts https with query string', () {
      expect(isSafeHttpsUrl('https://cdn.example/logo.png?v=42'), isTrue);
    });
    test('rejects null', () {
      expect(isSafeHttpsUrl(null), isFalse);
    });
    test('rejects empty', () {
      expect(isSafeHttpsUrl(''), isFalse);
    });
    test('rejects http:// (downgrade)', () {
      expect(isSafeHttpsUrl('http://cdn.example/logo.png'), isFalse);
    });
    test('rejects scheme-less', () {
      expect(isSafeHttpsUrl('cdn.example/logo.png'), isFalse);
    });
    test('rejects file://', () {
      expect(isSafeHttpsUrl('file:///etc/passwd'), isFalse);
    });
    test('rejects javascript:', () {
      expect(isSafeHttpsUrl('javascript:alert(1)'), isFalse);
    });
    test('rejects URL with embedded credentials', () {
      expect(isSafeHttpsUrl('https://u:p@cdn.example/logo.png'), isFalse);
    });
    test('rejects empty host', () {
      expect(isSafeHttpsUrl('https://'), isFalse);
    });
  });

  group('isSafeWebUrl', () {
    // Same threat model as isSafeHttpsUrl — guards user-tap launchUrl
    // calls against server-poisoned schemes — but allows http alongside
    // https for self-hosted "open portal" / "open website" links where
    // an internal-network http URL is a legitimate need.
    test('accepts https', () {
      expect(isSafeWebUrl('https://example.com/portal/abc'), isTrue);
    });
    test('accepts http (self-hosted on internal network)', () {
      expect(isSafeWebUrl('http://internal.lan:8080/portal'), isTrue);
    });
    test('rejects javascript:', () {
      expect(isSafeWebUrl('javascript:alert(1)'), isFalse);
    });
    test('rejects file://', () {
      expect(isSafeWebUrl('file:///etc/passwd'), isFalse);
    });
    test('rejects intent:// (Android intent hijacking)', () {
      expect(
        isSafeWebUrl('intent://malicious#Intent;package=com.attacker;end'),
        isFalse,
      );
    });
    test('rejects mailto: / tel: / sms:', () {
      expect(isSafeWebUrl('mailto:victim@example.com'), isFalse);
      expect(isSafeWebUrl('tel:+1234'), isFalse);
      expect(isSafeWebUrl('sms:+1234'), isFalse);
    });
    test('rejects data:', () {
      expect(isSafeWebUrl('data:text/html,<script>alert(1)</script>'), isFalse);
    });
    test('rejects URL with embedded credentials', () {
      expect(isSafeWebUrl('https://u:p@example.com/'), isFalse);
    });
    test('rejects empty / null', () {
      expect(isSafeWebUrl(''), isFalse);
      expect(isSafeWebUrl(null), isFalse);
    });
    test('rejects empty host', () {
      expect(isSafeWebUrl('https://'), isFalse);
      expect(isSafeWebUrl('http://'), isFalse);
    });
  });

  group('openableWebsiteUrl', () {
    test('assumes https when no scheme was typed', () {
      expect(openableWebsiteUrl('acme.com'), 'https://acme.com');
      expect(
        openableWebsiteUrl('  www.acme.com/about '),
        'https://www.acme.com/about',
      );
    });

    test('keeps a typed http or https scheme', () {
      expect(
        openableWebsiteUrl('http://intranet.local'),
        'http://intranet.local',
      );
      expect(openableWebsiteUrl('https://acme.com'), 'https://acme.com');
    });

    test('refuses blank, other schemes and no host', () {
      expect(openableWebsiteUrl(''), isNull);
      expect(openableWebsiteUrl('   '), isNull);
      expect(openableWebsiteUrl('javascript:alert(1)'), isNull);
      expect(openableWebsiteUrl('file:///etc/passwd'), isNull);
      expect(openableWebsiteUrl('ftp://acme.com'), isNull);
      expect(openableWebsiteUrl('https://'), isNull);
      expect(openableWebsiteUrl('https://user:pw@acme.com'), isNull);
    });
  });
}
