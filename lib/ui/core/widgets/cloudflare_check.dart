import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/services/cloudflare/cloudflare_clearance.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/windows_web_view.dart';

final _log = Logger('CloudflareCheck');

/// Whether this device can show Cloudflare's check: a web view that can hand
/// back its cookies — `webview_flutter` on iOS, Android and macOS, WebView2 on
/// Windows (which can still turn out to be missing its runtime). Not the web,
/// where the browser holds the clearance itself, nor Linux, which has no web
/// view the app ships (docs/windows-web-view.md).
bool get cloudflareCheckAvailable {
  if (kIsWeb) return false;
  if (isWindowsWebView) return true;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// The line that explains a challenge this device can't show the check for:
/// on the web the browser can pass it itself (a reload); on Linux nothing in
/// the app can.
String cloudflareUnavailableKey() =>
    kIsWeb ? 'cloudflare_banner_web' : 'cloudflare_banner_unsupported';

/// The line that explains [challenge] — the shell strip and the login toast
/// say the same thing. [canVerify]: `CloudflareClearanceStore.canVerify`.
String cloudflareWaitMessage(
  BuildContext context,
  CloudflareChallenge challenge, {
  bool canVerify = true,
}) {
  final params = {'host': challenge.host, 'ray': challenge.rayId ?? ''};
  // Hosted, the demo, or plain http: nothing in the app may open the check
  // there, so the line promises none.
  if (!canVerify) return context.tr('cloudflare_challenge_hosted', params);
  if (challenge.wait == CloudflareWait.refused) {
    return context.tr('cloudflare_banner_refused', params);
  }
  if (!cloudflareCheckAvailable) {
    return context.tr(cloudflareUnavailableKey(), params);
  }
  return context.tr(
    challenge.wait == CloudflareWait.expired
        ? 'cloudflare_banner_expired'
        : 'cloudflare_banner',
    params,
  );
}

/// Opens Cloudflare's "Verify you are human" for the server at [url] in a
/// real web view, full screen, and resolves true once it passed and the
/// clearance is in [CloudflareClearanceStore] (invoiceninja/invoiceninja#13484,
/// docs/cloudflare-challenge.md). False when the user closed it, or this
/// device can't show one. Only ever opened by the user (a tap, a sign-in) —
/// never on its own, so it can't pop up over a dialog or an edit, or loop.
///
/// The page is the server's `/api/v1/ping` ([cloudflareCheckUrl]), not the
/// challenged request: that may be a POST route or a download.
///
/// When the web view's own cookie store still holds a clearance Cloudflare
/// accepts (an earlier check on this network), the page loads straight
/// through and the screen closes itself: one check per clearance, not one per
/// launch.
Future<bool> showCloudflareCheck(BuildContext context, {required Uri url}) {
  final store = context.read<CloudflareClearanceStore?>();
  if (store == null || !cloudflareCheckAvailable || !store.canVerify(url)) {
    return Future.value(false);
  }
  return Navigator.of(context, rootNavigator: true)
      .push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              CloudflareCheckScreen(url: cloudflareCheckUrl(url), store: store),
        ),
      )
      .then((passed) => passed ?? false);
}

/// What one look at the page found — see [CloudflareCheckProbe].
@immutable
class CloudflarePageState {
  const CloudflarePageState({
    required this.origin,
    required this.challenge,
    required this.loaded,
  });

  /// `location.origin` of the main frame.
  final String origin;

  /// Cloudflare's challenge page is on screen.
  final bool challenge;

  /// `document.readyState == 'complete'`.
  final bool loaded;

  /// The script that reports it, as JSON. The challenge page names itself
  /// with `window._cf_chl_opt` (and, older, a `#challenge-form`); its title
  /// is translated, so it is only a last resort.
  static const script =
      '(function () { return JSON.stringify({'
      'o: location.origin,'
      "c: typeof window._cf_chl_opt !== 'undefined' ||"
      " !!document.getElementById('challenge-form') ||"
      ' /^just a moment/i.test(document.title),'
      "r: document.readyState === 'complete'"
      '}); })()';

  /// [raw] as a web view returns [script]'s result: the JSON string, or that
  /// string quoted again (Android), or already decoded (WebView2).
  static CloudflarePageState? parse(Object? raw) {
    Object? value = raw;
    for (var i = 0; i < 2 && value is String; i++) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    if (value is! Map) return null;
    return CloudflarePageState(
      origin: '${value['o'] ?? ''}',
      challenge: value['c'] == true,
      loaded: value['r'] == true,
    );
  }
}

/// A string a web view returned from `navigator.userAgent`, unquoted
/// (Android returns it JSON-encoded).
String? unquoteJavaScriptString(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    try {
      final decoded = jsonDecode(s);
      return decoded is String ? decoded : null;
    } on FormatException {
      return null;
    }
  }
  return s;
}

/// Decides when the check has passed, from repeated looks at the page and
/// its cookies. Pure, so it is tested without a web view.
///
/// Passed: the main frame is on the server's origin, fully loaded and not the
/// challenge, and the cookie store holds `cf_clearance`. A zone that let the
/// web view through without a challenge at all (a rule that challenged the
/// Dart client's User-Agent, say) sets no `cf_clearance`: after
/// [graceProbes] clean looks without one, the User-Agent alone is adopted —
/// and if that is not enough, the next request is challenged with it, the
/// store drops it, and the user is asked again rather than looped.
class CloudflareCheckProbe {
  CloudflareCheckProbe({required this.origin, this.graceProbes = 3});

  /// `Uri.origin` of the server — what `location.origin` reports.
  final String origin;
  final int graceProbes;
  int _cleanWithoutCookie = 0;

  /// Whether to adopt now, given the page and the Cloudflare cookies the web
  /// view holds for the origin.
  bool passed(CloudflarePageState? page, Map<String, String> cookies) {
    if (page == null || page.origin != origin || !page.loaded) return false;
    if (page.challenge) {
      _cleanWithoutCookie = 0;
      return false;
    }
    if (cookies.containsKey('cf_clearance')) return true;
    return ++_cleanWithoutCookie >= graceProbes;
  }
}

class CloudflareCheckScreen extends StatefulWidget {
  const CloudflareCheckScreen({
    super.key,
    required this.url,
    required this.store,
  });

  final Uri url;
  final CloudflareClearanceStore store;

  @override
  State<CloudflareCheckScreen> createState() => _CloudflareCheckScreenState();
}

class _CloudflareCheckScreenState extends State<CloudflareCheckScreen> {
  late final _CheckSurface _surface = _CheckSurface(
    origin: widget.url,
    onLoadFailed: _onLoadFailed,
    onUnavailable: _onUnavailable,
  );
  late final _probe = CloudflareCheckProbe(origin: widget.url.origin);
  Timer? _timer;
  bool _probing = false;
  bool _done = false;
  bool _failed = false;

  /// No web view could start at all (Windows without WebView2's runtime):
  /// Retry can't help, so the screen says so.
  bool _unavailable = false;

  /// Until the server's origin has answered once: a bar, not a blank page.
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_surface.open(widget.url));
    _timer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_look()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _surface.dispose();
    super.dispose();
  }

  void _onLoadFailed() {
    if (mounted && !_done) setState(() => _failed = true);
  }

  void _onUnavailable() {
    if (mounted && !_done) setState(() => _unavailable = true);
  }

  Future<void> _look() async {
    if (_probing || _done) return;
    _probing = true;
    try {
      final page = await _surface.pageState();
      if (_loading && page != null && page.origin == widget.url.origin) {
        if (mounted) setState(() => _loading = false);
      }
      final cookies = page == null || page.challenge
          ? const <String, String>{}
          : await _surface.cloudflareCookies(widget.url);
      if (!_probe.passed(page, cookies)) return;
      final userAgent = await _surface.userAgent();
      if (userAgent == null || !isUsableUserAgent(userAgent)) return;
      if (_done || !mounted) return;
      _done = true;
      widget.store.adopt(
        widget.url,
        CloudflareClearance(
          userAgent: userAgent,
          cookies: cookies,
          obtainedAt: DateTime.now(),
        ),
      );
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      // A page mid-navigation refuses scripts; the next look asks again.
      _log.fine('Looking at the check page: $e');
    } finally {
      _probing = false;
    }
  }

  void _retry() {
    setState(() => _failed = false);
    unawaited(_surface.load(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        leading: CloseButton(onPressed: () => Navigator.of(context).pop(false)),
        title: Text(context.tr('cloudflare_check_title')),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                InSpacing.lg(context),
                InSpacing.sm,
                InSpacing.lg(context),
                InSpacing.md(context),
              ),
              child: Text(
                context.tr('cloudflare_check_help', {'host': widget.url.host}),
                style: TextStyle(color: tokens.ink2),
              ),
            ),
            if (_loading && !_failed && !_unavailable)
              const LinearProgressIndicator(minHeight: 2)
            else
              Divider(height: 1, color: tokens.border),
            Expanded(
              child: _unavailable
                  ? _Unavailable(host: widget.url.host)
                  : _failed
                  ? _LoadFailed(onRetry: _retry)
                  : _surface.build(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(InSpacing.lg(context)),
      child: Text(
        context.tr(cloudflareUnavailableKey(), {'host': host}),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(InSpacing.lg(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('cloudflare_check_failed'),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: InSpacing.md(context)),
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: onRetry,
            child: Text(context.tr('retry')),
          ),
        ],
      ),
    ),
  );
}

/// The web view the check runs in, one implementation per package (the rule
/// docs/windows-web-view.md keeps for every surface): only the server's own
/// origin loads in the main frame — Cloudflare's widget is a frame inside it
/// — and nothing is cleared afterwards, because the cookie it earns is the
/// point.
abstract class _CheckSurface {
  factory _CheckSurface({
    required Uri origin,
    required VoidCallback onLoadFailed,
    required VoidCallback onUnavailable,
  }) => isWindowsWebView
      ? _WindowsCheckSurface(origin, onLoadFailed, onUnavailable)
      : _FlutterCheckSurface(origin, onLoadFailed);

  Future<void> open(Uri url);
  Future<void> load(Uri url);
  Future<CloudflarePageState?> pageState();
  Future<Map<String, String>> cloudflareCookies(Uri url);
  Future<String?> userAgent();
  Widget build(BuildContext context);
  void dispose();
}

Map<String, String> _onlyCloudflare(Iterable<(String, String)> cookies) => {
  for (final (name, value) in cookies)
    if (isCloudflareCookie(name)) name: value,
};

/// Whether [address] is on [origin]. `Uri.origin` throws for a scheme with
/// no origin (`blob:`, `data:`, `file:`, `about:`), which is never the
/// server's.
bool _onOrigin(String address, Uri origin) {
  try {
    return Uri.parse(address).origin == origin.origin;
  } on Object {
    return false;
  }
}

/// WebKit's own reports of a load it stopped, which are not a failed page:
/// `NSURLErrorCancelled` (a load another replaced — Cloudflare's redirect
/// after the check) and `WebKitErrorFrameLoadInterruptedByPolicyChange` (a
/// navigation the guard below refused).
const _kAppleInterruptedLoads = {-999, 102};

class _FlutterCheckSurface implements _CheckSurface {
  _FlutterCheckSurface(Uri origin, VoidCallback onLoadFailed) {
    _web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Cloudflare's widget is a frame from its own host; the main
            // frame stays on the server (the challenge reloads it there).
            // Android asks only for GET navigations, so a form POSTed off
            // the origin is not caught (docs/cloudflare-challenge.md).
            if (!request.isMainFrame) return NavigationDecision.navigate;
            return _onOrigin(request.url, origin)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (!(error.isForMainFrame ?? false)) return;
            if (_isApple && _kAppleInterruptedLoads.contains(error.errorCode)) {
              return;
            }
            onLoadFailed();
          },
        ),
      );
    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      // Android's web view refuses third-party cookies by default, and
      // Cloudflare's widget (a frame on challenges.cloudflare.com) needs them.
      unawaited(
        AndroidWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        ).setAcceptThirdPartyCookies(platform, true),
      );
    }
  }

  final _web = WebViewController();

  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<void> open(Uri url) => _web.loadRequest(url);

  @override
  Future<void> load(Uri url) => _web.loadRequest(url);

  @override
  Future<CloudflarePageState?> pageState() async => CloudflarePageState.parse(
    await _web.runJavaScriptReturningResult(CloudflarePageState.script),
  );

  @override
  Future<Map<String, String>> cloudflareCookies(Uri url) async {
    final cookies = await WebViewCookieManager().getCookies(domain: url);
    final found = _onlyCloudflare([for (final c in cookies) (c.name, c.value)]);
    // Android's cookie string is split at every `=`, so a value holding one
    // comes back cut short. `cf_clearance` has none; the rest (`__cf_bm`)
    // arrive through the API's own `Set-Cookie` once the check passed.
    if (_web.platform is AndroidWebViewController) {
      found.removeWhere((name, _) => name != 'cf_clearance');
    }
    return found;
  }

  @override
  Future<String?> userAgent() async => unquoteJavaScriptString(
    await _web.runJavaScriptReturningResult('navigator.userAgent'),
  );

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);

  @override
  void dispose() {}
}

/// WebView2. It cannot refuse a navigation, so a main frame that leaves the
/// server is loaded back onto the check page.
class _WindowsCheckSurface implements _CheckSurface {
  _WindowsCheckSurface(this._origin, this._onLoadFailed, this._onUnavailable);

  final Uri _origin;
  final VoidCallback _onLoadFailed;
  final VoidCallback _onUnavailable;
  WebviewController? _started;
  final _controller = ValueNotifier<WebviewController?>(null);
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _disposed = false;

  @override
  Future<void> open(Uri url) async {
    final controller = await startWindowsWebView();
    if (controller == null) {
      // No WebView2 runtime: no Retry can fix that.
      if (!_disposed) _onUnavailable();
      return;
    }
    _started = controller;
    if (_disposed) return _release();
    try {
      _subscriptions
        ..add(
          controller.onLoadError.listen((status) {
            if (status != WebErrorStatus.operationCanceled) _onLoadFailed();
          }),
        )
        ..add(
          controller.url.listen((address) {
            if (address.isEmpty || address.startsWith('about:')) return;
            // Loaded back onto the check page rather than `goBack()`, which
            // has nowhere to go when the very first load left the origin.
            if (!_onOrigin(address, _origin)) {
              unawaited(controller.loadUrl(_origin.toString()));
            }
          }),
        );
      _controller.value = controller;
      await controller.loadUrl(url.toString());
    } on Object catch (e, st) {
      _log.warning('The Cloudflare check did not load in WebView2', e, st);
      if (!_disposed) _controller.value = null;
      _release();
      if (!_disposed) _onLoadFailed();
    }
  }

  @override
  Future<void> load(Uri url) async {
    final controller = _controller.value;
    if (controller == null) return open(url);
    await controller.loadUrl(url.toString());
  }

  @override
  Future<CloudflarePageState?> pageState() async {
    final controller = _controller.value;
    if (controller == null) return null;
    return CloudflarePageState.parse(
      await controller.executeScript(CloudflarePageState.script),
    );
  }

  @override
  Future<Map<String, String>> cloudflareCookies(Uri url) async {
    final controller = _controller.value;
    if (controller == null) return const {};
    final cookies = await controller.getCookies(url.toString());
    return _onlyCloudflare([for (final c in cookies) (c.name, c.value)]);
  }

  @override
  Future<String?> userAgent() async => unquoteJavaScriptString(
    await _controller.value?.executeScript('navigator.userAgent'),
  );

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<WebviewController?>(
        valueListenable: _controller,
        builder: (context, controller, _) =>
            controller == null ? const SizedBox.expand() : Webview(controller),
      );

  void _release() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    final controller = _started;
    _started = null;
    if (controller != null) unawaited(disposeWindowsWebView(controller));
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _release();
  }
}
