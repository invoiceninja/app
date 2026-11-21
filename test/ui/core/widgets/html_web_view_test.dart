import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
// The macOS implementation, to build the web view as macOS does. Both come
// with webview_flutter.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:admin/ui/core/widgets/html_web_view.dart';

/// Records what a preview hands its web view, without a native one.
class _FakeWebViewPlatform extends WebViewPlatform {
  final loads = <String>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakeController(params, loads);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params, this.loads) : super.implementation();

  final List<String> loads;

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async =>
      loads.add(html);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}
}

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// The server's email wrapper: a 570 px table.
const _email =
    '<!DOCTYPE html><html>'
    '<meta name="viewport" content="width=device-width, initial-scale=1.0"/>'
    '<body><table width="100%"><tr><td>'
    '<table align="center" width="570"><tr><td>Bonjour</td></tr></table>'
    '</td></tr></table></body></html>';

void main() {
  testWidgets('macOS shows the web view: no background colour is set on it', (
    tester,
  ) async {
    // macOS's WKWebView cannot be made non-opaque: setting a background
    // colour there throws in the build, and the preview was an error box.
    final previous = WebViewPlatform.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    WebViewPlatform.instance = WebKitWebViewPlatform();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: HtmlWebView(
            html: '<p>Hello</p>',
            fallback: (_) => const Text('fallback'),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the web view must build on macOS',
      );
      expect(find.text('fallback'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      if (previous != null) WebViewPlatform.instance = previous;
    }
  });

  testWidgets('a platform without a web view shows the fallback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: HtmlWebView(
            html: '<p>Hello</p>',
            fallback: (_) => const Text('fallback'),
          ),
        ),
      );
      expect(find.text('fallback'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('fit to the pane, pinch to zoom (cut off on an iPhone, 5.1.32)', () {
    late WebViewPlatform? previous;
    late _FakeWebViewPlatform fake;

    setUp(() {
      previous = WebViewPlatform.instance;
      fake = _FakeWebViewPlatform();
      WebViewPlatform.instance = fake;
    });

    tearDown(() {
      if (previous != null) WebViewPlatform.instance = previous!;
    });

    // The phone the bug came from.
    final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

    Widget host(double width, {String html = _email}) => MaterialApp(
      home: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: width,
          height: 600,
          child: HtmlWebView(
            html: html,
            fallback: (_) => const Text('fallback'),
          ),
        ),
      ),
    );

    testWidgets(
      'loads once, after layout, scaled to the pane',
      (tester) async {
        await tester.pumpWidget(host(358));
        expect(fake.loads, hasLength(1), reason: 'no unfitted first load');
        expect(fake.loads.single, contains(':root { zoom: 0.6 !important; }'));
        expect(fake.loads.single, isNot(contains('initial-scale=1.0')));
      },
      variant: TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'on macOS, where nothing pinches it back, no smaller than 0.8',
      (tester) async {
        // macOS's WKWebView has no magnification: a fully fitted narrow pane
        // would be stuck at 60 %. The rest of the email scrolls sideways.
        await tester.pumpWidget(host(358));
        expect(fake.loads.single, contains(':root { zoom: 0.8 !important; }'));
        // A pane it nearly fits still fits fully.
        await tester.pumpWidget(host(560));
        await tester.pump();
        expect(fake.loads.last, contains(':root { zoom: 0.95 !important; }'));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('a wider pane reloads it unscaled; the same width does not', (
      tester,
    ) async {
      await tester.pumpWidget(host(358));
      await tester.pumpWidget(host(358));
      expect(fake.loads, hasLength(1));
      await tester.pumpWidget(host(800));
      await tester.pump();
      expect(fake.loads, hasLength(2));
      expect(fake.loads.last, isNot(contains('zoom')));
    }, variant: iOS);

    testWidgets('a new document is fitted to the width it lands in', (
      tester,
    ) async {
      await tester.pumpWidget(host(358));
      await tester.pumpWidget(host(358, html: '<p>Plain</p>'));
      expect(fake.loads, hasLength(2));
      expect(fake.loads.last, isNot(contains('zoom')));
    }, variant: iOS);

    testWidgets('the web view claims every gesture on it, a pinch included', (
      tester,
    ) async {
      // A TabBarView's horizontal drag won every pinch and sideways pan
      // over the preview; an eager recognizer hands them to the web view.
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: TabBarView(
              children: [
                HtmlWebView(html: _email, fallback: (_) => const Text('x')),
                const SizedBox(),
              ],
            ),
          ),
        ),
      );
      final view = tester.widget<WebViewWidget>(find.byType(WebViewWidget));
      expect(
        view.gestureRecognizers.map((f) => f.constructor()),
        contains(isA<EagerGestureRecognizer>()),
      );
    }, variant: iOS);
  });
}
