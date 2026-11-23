import 'package:http/http.dart' as http;

import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/cloudflare/cloudflare_clearance.dart';

/// The app's transport for a server behind a Cloudflare zone that challenges
/// visitors (invoiceninja/invoiceninja#13484, docs/cloudflare-challenge.md).
/// Wraps the client both `ApiClient` and `AuthService` send through, so
/// login, `/refresh`, the outbox and file transfers all get it.
///
/// * **A challenge is recognised here** ([isCloudflareChallenge]), before
///   anything reads the HTML page as JSON or a 403 as a refusal: the request
///   fails as [CloudflareChallengeException], a `RequestNotSentException` —
///   Cloudflare never forwarded it, so the outbox re-parks it untouched — and
///   the store learns the origin is waiting.
/// * **While an origin waits, requests fail at once** without reaching
///   Cloudflare, but for one real probe every
///   [CloudflareClearanceStore.probeEvery]: a queue of edits is not a burst
///   of challenged requests, and a network the zone allows is still noticed.
/// * **A passed check is replayed**: the web view's Cloudflare cookies and its
///   exact User-Agent go on every request to that origin. Nothing is added
///   for an origin without one, so hosted Invoice Ninja and every
///   unchallenged server see the app as before.
/// * **A dead clearance is dropped, not retried** — only the one the request
///   actually carried, so a slow request that left before a new check passed
///   cannot throw the new clearance away.
class CloudflareClearanceClient extends http.BaseClient {
  CloudflareClearanceClient(this._inner, this._store);

  final http.Client _inner;
  final CloudflareClearanceStore _store;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    final waiting = _store.outstandingFor(url);
    if (waiting != null && !_store.mayProbe(url)) {
      throw CloudflareChallengeException(
        url: url,
        statusCode: 0,
        rayId: waiting.rayId,
      );
    }
    final clearance = _store.clearanceFor(url);
    if (clearance != null) {
      request.headers['user-agent'] = clearance.userAgent;
      final replay = clearance.cookieHeader;
      if (replay.isNotEmpty) {
        final existing = request.headers['cookie'];
        request.headers['cookie'] = existing == null || existing.isEmpty
            ? replay
            : '$existing; $replay';
      }
    }
    final response = await _inner.send(request);
    if (isCloudflareChallenge(response.headers)) {
      // The page is HTML nobody will read; let the connection go.
      await response.stream.drain<void>().catchError((_) {});
      final rayId = response.headers['cf-ray'];
      _store.noteChallenge(url, sent: clearance, rayId: rayId);
      throw CloudflareChallengeException(
        url: url,
        statusCode: response.statusCode,
        rayId: rayId,
      );
    }
    _store.noteReached(url, sent: clearance);
    if (clearance != null) {
      _store.noteResponseCookies(
        url,
        clearance,
        splitSetCookieHeader(response.headers['set-cookie']),
      );
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
