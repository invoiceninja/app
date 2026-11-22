import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/ui/core/widgets/html_web_view.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/services/templates_api.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/preview_controller.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/widgets/template_preview_panel.dart';

import '../../../../../../_localization_helper.dart';

class _FakeTemplatesApi implements TemplatesApi {
  @override
  Future<TemplatePreview> render({
    required String template,
    required String subject,
    required String body,
    String entity = '',
    String entityId = '',
  }) async {
    return TemplatePreview(
      subject: subject,
      body: body,
      wrapper: '<html><body>$body</body></html>',
      rawSubject: subject,
      rawBody: body,
    );
  }
}

/// Answers after a moment, so the loading state shows.
class _SlowTemplatesApi extends _FakeTemplatesApi {
  @override
  Future<TemplatePreview> render({
    required String template,
    required String subject,
    required String body,
    String entity = '',
    String entityId = '',
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return super.render(template: template, subject: subject, body: body);
  }
}

/// Records what the preview loads, without a native web view.
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

/// A fixed 570 px email, as the server's wrapper is.
class _WideTemplatesApi extends _FakeTemplatesApi {
  @override
  Future<TemplatePreview> render({
    required String template,
    required String subject,
    required String body,
    String entity = '',
    String entityId = '',
  }) async => TemplatePreview(
    subject: subject,
    body: body,
    wrapper:
        '<html><body><table width="570"><tr><td>$body</td></tr>'
        '</table></body></html>',
    rawSubject: subject,
    rawBody: body,
  );
}

void main() {
  Widget host(PreviewController controller) {
    return MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 500,
          height: 600,
          child: TemplatePreviewPanel(controller: controller),
        ),
      ),
    );
  }

  testWidgets(
    'success branch without a web view renders the body via HtmlWidget, '
    'never a WebView',
    (tester) async {
      // Linux stands in for every target without a web view. The web path
      // (kIsWeb true) routes here too, but kIsWeb is a compile-time const we
      // can't flip in a VM test — it's exercised by the Chrome integration
      // suite. The guarantee under test: the success branch must NOT
      // instantiate a WebView where there is none. (The default test
      // platform is android, which WOULD take the WebView path — hence the
      // override is required, reset in a finally so the foundation-var
      // invariant check at the end of the body passes.)
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final controller = PreviewController(api: _FakeTemplatesApi());
        addTearDown(controller.dispose);
        controller.schedule(
          template: 'invoice',
          subject: 'Welcome',
          body: '<p>Hello world</p>',
          immediate: true,
        );

        await tester.pumpWidget(host(controller));
        await tester.pumpAndSettle();

        expect(find.byType(HtmlWidget), findsOneWidget);
        expect(find.byType(WebViewWidget), findsNothing);
        // Subject bar reflects the server-substituted subject.
        expect(find.text('Welcome'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'the preview stays up under a progress bar while the next one loads',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final controller = PreviewController(api: _SlowTemplatesApi());
        addTearDown(controller.dispose);
        controller.schedule(
          template: 'invoice',
          subject: 'One',
          body: '<p>First</p>',
          immediate: true,
        );
        await tester.pumpWidget(host(controller));
        await tester.pumpAndSettle();
        final before = tester.state(find.byType(HtmlWebView));

        controller.schedule(
          template: 'invoice',
          subject: 'Two',
          body: '<p>Second</p>',
        );
        // Past the debounce: loading.
        await tester.pump(const Duration(milliseconds: 450));
        // Loading: the same preview (its web view not torn down), with a bar.
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(tester.state(find.byType(HtmlWebView)), same(before));

        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Two'), findsOneWidget);
        expect(tester.state(find.byType(HtmlWebView)), same(before));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test(
    'the email preview has a web view on iOS, Android, macOS and Windows',
    () {
      try {
        for (final p in TargetPlatform.values) {
          debugDefaultTargetPlatformOverride = p;
          expect(
            HtmlWebView.supported,
            {
              TargetPlatform.iOS,
              TargetPlatform.android,
              TargetPlatform.macOS,
              TargetPlatform.windows,
            }.contains(p),
            reason: '$p',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('a zoom control over the email: the only zoom a desktop has', (
    tester,
  ) async {
    // "You can't zoom in or out to see the email preview" (beta): macOS's
    // web view has no magnification, and WebView2 gets no Ctrl+wheel.
    final previous = WebViewPlatform.instance;
    final fake = _FakeWebViewPlatform();
    WebViewPlatform.instance = fake;
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    final controller = PreviewController(api: _WideTemplatesApi());
    addTearDown(controller.dispose);
    controller.schedule(
      template: 'invoice',
      subject: 'Welcome',
      body: '<p>Hello</p>',
      immediate: true,
    );
    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();

    // A 500 px pane fits the 570 px email at the desktop floor.
    String level() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('preview_zoom_level')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(level(), '80%');
    expect(find.byKey(const ValueKey('preview_zoom_fit')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('preview_zoom_out')));
    await tester.pumpAndSettle();
    expect(level(), '75%');
    expect(fake.loads.last, contains(':root { zoom: 0.75 !important; }'));
    expect(find.byKey(const ValueKey('preview_zoom_fit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preview_zoom_in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preview_zoom_in')));
    await tester.pumpAndSettle();
    expect(level(), '90%');

    await tester.tap(find.byKey(const ValueKey('preview_zoom_fit')));
    await tester.pumpAndSettle();
    expect(level(), '80%');
    expect(fake.loads.last, contains(':root { zoom: 0.8 !important; }'));
    expect(find.byKey(const ValueKey('preview_zoom_fit')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('no zoom control where the email is not a web view', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final controller = PreviewController(api: _FakeTemplatesApi());
      addTearDown(controller.dispose);
      controller.schedule(
        template: 'invoice',
        subject: 'Welcome',
        body: '<p>Hello</p>',
        immediate: true,
      );
      await tester.pumpWidget(host(controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preview_zoom_in')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
