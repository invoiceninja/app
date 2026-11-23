import 'package:flutter/foundation.dart';

import 'package:admin/app/env.dart';
import 'package:admin/data/services/tls/certificate_problems.dart';
import 'package:admin/data/services/tls/certificate_trust_store.dart';

/// Whether a response is Cloudflare's challenge page rather than the server's
/// answer: `cf-mitigated: challenge`, Cloudflare's documented signal for every
/// challenge page (managed, interactive and JS) whatever the status (403, 429,
/// 503) and the page's language — and a `cf-ray`, which Cloudflare puts on
/// every response it serves. Requiring both keeps a proxy that is not
/// Cloudflare from turning a write it forwarded into a "not sent" one the
/// outbox would send again.
bool isCloudflareChallenge(Map<String, String> headers) =>
    (headers['cf-mitigated'] ?? '').toLowerCase().contains('challenge') &&
    (headers['cf-ray'] ?? '').isNotEmpty;

/// The scheme, host and port a clearance belongs to — Cloudflare scopes
/// `cf_clearance` to the zone, and the app talks to one server per origin.
String cloudflareOrigin(Uri url) {
  final scheme = url.scheme.toLowerCase();
  final port = url.hasPort
      ? url.port
      : scheme == 'http'
      ? 80
      : 443;
  return '$scheme://${normalizeCertificateHost(url.host)}:$port';
}

/// Whether [host] is hosted Invoice Ninja or the demo, which never get a web
/// view: both stay on the plain Dart client (#13484 asks exactly that), and a
/// challenge there is Cloudflare's to lift, not the user's.
bool isHostedOrDemoHost(String host) {
  final h = normalizeCertificateHost(host);
  if (isHostedCertificateHost(h)) return true;
  final demo = normalizeCertificateHost(
    Uri.tryParse(Env.demoApiUrl)?.host ?? '',
  );
  return (demo.isNotEmpty && h == demo) || h == 'demo.invoiceninja.com';
}

/// Whether a cookie belongs to Cloudflare — the only ones copied out of the
/// web view and sent with API calls. `cf_clearance` is the passed check;
/// `__cf_bm`, `__cflb` and `_cfuvid` are bot-management, load-balancer and
/// rate-limit cookies the zone may tie to it. The server's own cookies (a web
/// session from someone who also signed in to the site there) stay behind.
bool isCloudflareCookie(String name) =>
    name == 'cf_clearance' || name == '_cfuvid' || name.startsWith('__cf');

/// Whether [userAgent] is one to send: what a browser engine reports
/// (`Mozilla/…`), printable ASCII, of a sane length. The value comes from the
/// page (its script can override `navigator.userAgent`), and one `dart:io`
/// refuses as a header would fail every request to the origin.
bool isUsableUserAgent(String userAgent) =>
    userAgent.startsWith('Mozilla/') &&
    userAgent.length <= 512 &&
    userAgent.codeUnits.every((c) => c >= 0x20 && c < 0x7f);

/// Where the check page opens for a challenge at [url]: the server's
/// `/api/v1/ping` (a light JSON answer) under whatever path the server is
/// installed at — never the challenged request itself, which may be a POST
/// route (a 405 page; with `APP_DEBUG`, a stack trace), a download the web
/// view never finishes, or an upload.
Uri cloudflareCheckUrl(Uri url) {
  final at = url.path.indexOf('/api/v1');
  final base = at < 0 ? '' : url.path.substring(0, at);
  return Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: '$base/api/v1/ping',
  );
}

/// A passed check: what the web view had when Cloudflare let it through,
/// replayed on every API call to that origin. The cookie is bound to the
/// visitor that solved it — at least the IP and the User-Agent — so both go
/// together.
@immutable
class CloudflareClearance {
  const CloudflareClearance({
    required this.userAgent,
    required this.cookies,
    required this.obtainedAt,
  });

  final String userAgent;

  /// Cloudflare's cookies by name — `cf_clearance`, unless the zone let the
  /// web view through without a challenge (then possibly none).
  final Map<String, String> cookies;
  final DateTime obtainedAt;

  /// The `Cookie` header value; empty when there are none.
  String get cookieHeader =>
      [for (final e in cookies.entries) '${e.key}=${e.value}'].join('; ');

  CloudflareClearance withCookies(Map<String, String> updated) =>
      CloudflareClearance(
        userAgent: userAgent,
        cookies: {...cookies, ...updated},
        obtainedAt: obtainedAt,
      );
}

/// Why requests to an origin are waiting.
enum CloudflareWait {
  /// Cloudflare challenged a request: the user passes the check.
  challenged,

  /// A clearance had been working and stopped (usually a new network: the
  /// cookie is bound to the IP): the user passes the check again.
  expired,

  /// A check that passed in the web view was refused for the app's own
  /// requests right after — the zone binds more than the cookie and the
  /// User-Agent (the TLS fingerprint, say). Passing again would only repeat
  /// that, so nothing offers it on its own; the server's administrator has
  /// to change the zone (docs/cloudflare-challenge.md).
  refused,
}

/// A challenge waiting for the user.
@immutable
class CloudflareChallenge {
  const CloudflareChallenge({
    required this.url,
    required this.seenAt,
    required this.wait,
    this.rayId,
  });

  /// The challenged request's address, without its query.
  final Uri url;
  final DateTime seenAt;
  final CloudflareWait wait;

  /// The challenge's `cf-ray`, for the administrator.
  final String? rayId;

  String get host => url.host;

  /// Where the check page opens ([cloudflareCheckUrl]).
  Uri get checkUrl => cloudflareCheckUrl(url);
}

/// The passed Cloudflare checks this run holds, and the challenges waiting
/// for one (invoiceninja/invoiceninja#13484, docs/cloudflare-challenge.md).
///
/// Written by `CloudflareClearanceClient` (every request and response) and by
/// the check screen (a passed check); read by the shell banner and the login
/// screen, which open the check only when the user asks.
///
/// **Memory only.** The clearance is a credential of sorts, and does not need
/// keeping: the web view's own cookie store keeps `cf_clearance` across
/// launches, so a later check opens on a page Cloudflare lets straight
/// through and closes itself.
class CloudflareClearanceStore extends ChangeNotifier {
  CloudflareClearanceStore({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, CloudflareClearance> _clearances = {};
  final Map<String, CloudflareChallenge> _outstanding = {};
  final Map<String, DateTime> _lastProbe = {};

  /// Origins whose current clearance has carried at least one request
  /// Cloudflare let through — what tells [CloudflareWait.expired] from
  /// [CloudflareWait.refused].
  final Set<String> _proven = {};

  /// A clearance that never carried a request Cloudflare let through, and is
  /// challenged sooner than this after it passed, was not accepted for the
  /// app's requests at all — [CloudflareWait.refused]. One that worked even
  /// once simply expired (Challenge Passage defaults to 30 minutes) or met a
  /// new network (the cookie is bound to the IP) — [CloudflareWait.expired].
  static const Duration refusedWithin = Duration(minutes: 3);

  /// While an origin waits, one real request every this long finds out
  /// whether it still has to (the device moved onto a network the zone
  /// allows, the administrator changed the rule); the rest fail at once
  /// without reaching Cloudflare, so a queue of offline edits is not a
  /// burst of challenged requests per drain.
  static const Duration probeEvery = Duration(seconds: 20);

  /// The clearance to send to [url]'s origin, if this run has one.
  CloudflareClearance? clearanceFor(Uri url) =>
      _clearances[cloudflareOrigin(url)];

  /// The challenge waiting at [url]'s origin, if any.
  CloudflareChallenge? outstandingFor(Uri url) =>
      _outstanding[cloudflareOrigin(url)];

  /// Whether the user can be offered the check for [url]: an https server
  /// that is not hosted Invoice Ninja or the demo. Never plain http: a
  /// network attacker can inject the header there, and the check would put
  /// their page full screen inside the app and send Cloudflare's `Secure`
  /// cookies in the clear. (Whether this device can show a web view at all
  /// is the UI's question.)
  bool canVerify(Uri url) =>
      url.scheme.toLowerCase() == 'https' && !isHostedOrDemoHost(url.host);

  /// Whether a request to [url] may go out now, or should fail at once as
  /// still challenged ([probeEvery]). Records the attempt when it may.
  bool mayProbe(Uri url) {
    final origin = cloudflareOrigin(url);
    if (!_outstanding.containsKey(origin)) return true;
    final last = _lastProbe[origin];
    final now = _now();
    if (last != null && now.difference(last) < probeEvery) return false;
    _lastProbe[origin] = now;
    return true;
  }

  /// Cloudflare challenged a request to [url]. [sent] is the clearance that
  /// request carried (null: none). Notifies only when something changed, so
  /// a burst of challenged requests asks once.
  ///
  /// * A request that left before the clearance held now was adopted (sent
  ///   none, or an older one) is stale: it says nothing about the new one.
  /// * The clearance it carried is dropped — never sent again, so the next
  ///   request is not challenged in a loop — and the wait says whether it
  ///   had worked for a while ([CloudflareWait.expired]) or was refused from
  ///   the start ([CloudflareWait.refused], [refusedWithin]).
  void noteChallenge(Uri url, {CloudflareClearance? sent, String? rayId}) {
    final origin = cloudflareOrigin(url);
    final held = _clearances[origin];
    if (held != null && !identical(held, sent)) return;
    var wait = CloudflareWait.challenged;
    if (held != null) {
      _clearances.remove(origin);
      final proven = _proven.remove(origin);
      wait = !proven && _now().difference(held.obtainedAt) < refusedWithin
          ? CloudflareWait.refused
          : CloudflareWait.expired;
    }
    final waiting = _outstanding[origin];
    if (waiting != null && held == null) return;
    _lastProbe[origin] = _now();
    _outstanding[origin] = CloudflareChallenge(
      url: Uri(
        scheme: url.scheme,
        host: url.host,
        port: url.hasPort ? url.port : null,
        path: url.path,
      ),
      seenAt: _now(),
      wait: wait,
      rayId: rayId,
    );
    notifyListeners();
  }

  /// [url]'s origin answered without a challenge: it no longer waits (the
  /// device reached a network the zone allows, or the zone changed). Cheap
  /// when nothing waits — it runs on every response.
  void noteReached(Uri url, {CloudflareClearance? sent}) {
    final origin = cloudflareOrigin(url);
    if (sent != null && identical(_clearances[origin], sent)) {
      _proven.add(origin);
    }
    if (_outstanding.isEmpty) return;
    if (_outstanding.remove(origin) == null) return;
    _lastProbe.remove(origin);
    notifyListeners();
  }

  /// The check at [url]'s origin passed: send [clearance] from now on.
  void adopt(Uri url, CloudflareClearance clearance) {
    final origin = cloudflareOrigin(url);
    _clearances[origin] = clearance;
    _proven.remove(origin);
    _outstanding.remove(origin);
    _lastProbe.remove(origin);
    notifyListeners();
  }

  /// The user has been told the zone refused the app ([CloudflareWait.
  /// refused]): the wait goes back to an ordinary challenge, so the next
  /// thing they tap opens the check again — a choice, never a loop — and an
  /// administrator's fix is not a dead end until the app restarts.
  void acknowledgeRefused(Uri url) {
    final origin = cloudflareOrigin(url);
    final waiting = _outstanding[origin];
    if (waiting == null || waiting.wait != CloudflareWait.refused) return;
    _outstanding[origin] = CloudflareChallenge(
      url: waiting.url,
      seenAt: waiting.seenAt,
      wait: CloudflareWait.challenged,
      rayId: waiting.rayId,
    );
    notifyListeners();
  }

  /// Cloudflare rotates some of its cookies (`__cf_bm` every half hour) in
  /// ordinary responses; keep the replayed set current. [sent] is the
  /// clearance the request carried: a response to an older one is not
  /// merged into a newer. Quiet: nothing on screen depends on it.
  void noteResponseCookies(
    Uri url,
    CloudflareClearance sent,
    Iterable<String> setCookies,
  ) {
    final origin = cloudflareOrigin(url);
    final held = _clearances[origin];
    if (held == null || !identical(held, sent)) return;
    final updated = <String, String>{};
    for (final line in setCookies) {
      final pair = line.split(';').first;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      if (!isCloudflareCookie(name)) continue;
      updated[name] = pair.substring(eq + 1).trim();
    }
    if (updated.isEmpty) return;
    _clearances[origin] = held.withCookies(updated);
  }
}

/// `Set-Cookie` values out of `package:http`'s folded header, which joins
/// several with commas — the same character a cookie's `Expires` date holds.
/// A comma starts a new cookie only where a `name=` follows it.
List<String> splitSetCookieHeader(String? folded) {
  if (folded == null || folded.isEmpty) return const [];
  return folded
      .split(RegExp(r',(?=\s*[!#$%&*+\-.^_`|~0-9A-Za-z]+=)'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
