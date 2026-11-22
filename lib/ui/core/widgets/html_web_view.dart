import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'package:admin/ui/core/widgets/windows_web_view.dart';
import 'package:admin/utils/html_preview.dart';

/// The largest document WebView2 loads from a string (`NavigateToString`
/// takes 2 MB); a larger one (an email with big inline images) shows the
/// fallback rather than a blank page.
const _kWindowsMaxDocumentBytes = 1900 * 1024;

/// A finished HTML document (an email as it will arrive) shown in a native
/// web view, so its `<style>` blocks, tables and images render as a mail
/// client renders them: iOS, Android, macOS (`webview_flutter`) and Windows
/// (WebView2, `windows_web_view.dart`). Everywhere else (the web, Linux),
/// and on a Windows whose WebView2 runtime is missing, [fallback] is shown
/// instead.
///
/// It is a picture, not a page ([previewHtml]): no script runs, a tapped
/// link or form leaves the document where it is, and it reads light. It is
/// fitted to the pane's width ([previewFitZoom]: an email is a fixed 570 px
/// table, wider than a phone; on desktop no smaller than 0.8), unless the
/// host passes a [zoom] of the user's choosing, and on touch it takes every gesture that
/// lands on it ([kHtmlWebViewGestures]), so a pinch zooms it and a
/// sideways drag pans it, even inside a `TabBarView`.
/// docs/windows-web-view.md.
class HtmlWebView extends StatefulWidget {
  const HtmlWebView({
    super.key,
    required this.html,
    required this.fallback,
    this.background = const Color(0x00000000),
    this.zoom,
    this.onFitZoom,
  });

  final String html;

  /// The zoom to show the document at, chosen by the user (the preview's
  /// zoom control); null fits it to the pane ([previewFitZoom]). The only
  /// zoom macOS and Windows have: macOS's web view has no magnification, and
  /// WebView2 here gets no Ctrl+wheel (the plugin forwards a wheel event
  /// without its modifier keys).
  final double? zoom;

  /// Told the fitted zoom whenever a layout changes it, so a zoom control
  /// can start from it and show it.
  final ValueChanged<double>? onFitZoom;

  /// What shows where there is no web view.
  final WidgetBuilder fallback;

  /// Behind the document (transparent: the email's own background shows).
  /// Not applied on macOS, whose web view cannot take one and is
  /// transparent already.
  final Color background;

  /// Whether this platform has a web view to show it in.
  static bool get supported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  @override
  State<HtmlWebView> createState() => _HtmlWebViewState();
}

/// The gestures a `webview_flutter` preview claims: all of them, at once.
///
/// With none (the default) a platform view only gets the gestures no
/// Flutter recognizer around it wants, and the Email screen's `TabBarView`
/// is a horizontal drag: it won every pinch and every sideways pan, so the
/// email could be neither zoomed nor moved (and on iOS the web view's own
/// gestures wait for Flutter's arena to give up on them). Swiping between
/// the tabs still works everywhere but over the preview itself; the tab
/// strip is the way across there. No host puts a preview inside a vertical
/// scroll view (its frame is always bounded), so nothing loses a drag.
final Set<Factory<OneSequenceGestureRecognizer>> kHtmlWebViewGestures = {
  Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
};

class _HtmlWebViewState extends State<HtmlWebView> {
  WebViewController? _flutter;

  /// WebView2's controller from the moment it exists, so a dispose during
  /// its start-up lets it go.
  WebviewController? _starting;
  WebviewController? _windows;
  StreamSubscription<String>? _windowsUrl;

  /// WebView2 could not start (no runtime): the fallback shows, for good.
  bool _failed = false;

  /// The document is too large for WebView2: the fallback shows until a
  /// smaller one comes.
  bool _tooLarge = false;

  /// The widest fixed width [HtmlWebView.html] declares ([previewContentWidth]),
  /// read once per document rather than on every layout.
  late double? _contentWidth = previewContentWidth(widget.html);

  /// The zoom that fits it into the pane, from the last layout; null until
  /// the first, which is when the document first loads (a load at 1 and
  /// another once the width is known would flash).
  double? _zoom;

  /// The document a web view was last handed, so a layout that does not
  /// change the zoom (or a rebuild) reloads nothing.
  String? _shown;

  String get _document => previewHtml(widget.html, zoom: _shownZoom);

  /// The user's zoom, else the fit; 1 until the first layout.
  double get _shownZoom => widget.zoom ?? _zoom ?? 1;

  @override
  void initState() {
    super.initState();
    if (!HtmlWebView.supported) return;
    if (isWindowsWebView) {
      // Too large for WebView2: the fallback, from the first frame.
      if (!_fitsWindows(_document)) {
        _tooLarge = true;
      } else {
        unawaited(_startWindows());
      }
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Only the document itself loads (exactly `about:blank`, or a
          // `data:` URL, by platform); a tapped link goes nowhere. A `#`
          // link counts as a link: with `<base target="_blank">` it arrives
          // here as a new window (`about:blank#…` on Android), and loading
          // that would blank the preview.
          onNavigationRequest: (request) =>
              request.url == 'about:blank' ||
                  (request.url.startsWith('data:') &&
                      !request.url.contains('#'))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    // macOS's WKWebView cannot take a background colour (the plugin throws
    // making it non-opaque); it draws the page's own, white for a preview
    // ([previewHtml] sets the light colour scheme).
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      controller.setBackgroundColor(widget.background);
    }
    // The document loads after the first layout ([_layout]), fitted to it.
    _flutter = controller;
  }

  bool _fitsWindows(String document) =>
      utf8.encode(document).length <= _kWindowsMaxDocumentBytes;

  Future<void> _startWindows() async {
    final controller = await startWindowsWebView();
    if (controller == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _starting = controller;
    if (!mounted) return _release();
    // WebView2 cannot refuse a navigation from here, so one that leaves the
    // document (a tapped link) is put back. A document loaded from a string
    // reports `about:blank`, so this never loops on itself.
    _windowsUrl = controller.url.listen((url) {
      if (url.startsWith('http:') || url.startsWith('https:')) {
        unawaited(controller.loadStringContent(_document));
      }
    });
    final String document;
    try {
      await controller.setBackgroundColor(widget.background);
      if (!mounted) return _release();
      // The document as it is now: an edit while WebView2 was starting
      // must not leave the one from before showing.
      document = _document;
      if (!_fitsWindows(document)) {
        _release();
        setState(() => _tooLarge = true);
        return;
      }
      await controller.loadStringContent(document);
      _shown = document;
    } on Object {
      // A WebView2 that started but will not take the page (its browser
      // process failed): the fallback, not a blank box.
      _release();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return _release();
    setState(() => _windows = controller);
    // Changed during that last load (an edit, or the first layout's zoom):
    // the newest one, or the fallback.
    _show();
  }

  /// Lets WebView2 go (the widget left, or never needed it).
  void _release() {
    unawaited(_windowsUrl?.cancel());
    _windowsUrl = null;
    final controller = _starting;
    _starting = null;
    _windows = null;
    if (controller != null) unawaited(disposeWindowsWebView(controller));
  }

  @override
  void didUpdateWidget(covariant HtmlWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html == widget.html) {
      // The user zoomed (or went back to the fit): reload at the new zoom.
      if (oldWidget.zoom != widget.zoom && _zoom != null) _show();
      return;
    }
    _contentWidth = previewContentWidth(widget.html);
    final width = _paneWidth;
    if (width != null) {
      final zoom = _fit(width);
      if (zoom != _zoom) {
        _zoom = zoom;
        _reportFit(zoom);
      }
    }
    _show();
  }

  void _reportFit(double zoom) {
    final onFit = widget.onFitZoom;
    if (onFit == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _zoom == zoom) onFit(zoom);
    });
  }

  /// Fitted fully where a pinch can zoom back in (iOS, Android), to the
  /// hundredth (a phone's width changes only on rotation); on macOS and
  /// Windows no further than [kPreviewDesktopZoomFloor], so the text stays
  /// readable and the rest scrolls sideways, in steps of 0.05 (a window
  /// being resized reloads only every few dozen pixels).
  double _fit(double width) {
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    return previewFitZoom(
      _contentWidth,
      width,
      floor: touch ? kPreviewTouchZoomFloor : kPreviewDesktopZoomFloor,
      steps: touch ? 100 : 20,
    );
  }

  /// The pane's width at the last layout.
  double? _paneWidth;

  /// Hands the web view the document as it is now (the newest edit, fitted
  /// to the newest width), unless it already has it.
  void _show() {
    final document = _document;
    if (document == _shown) return;
    final flutter = _flutter;
    if (flutter != null) {
      _shown = document;
      unawaited(flutter.loadHtmlString(document));
      return;
    }
    if (!isWindowsWebView || _failed) return;
    final fits = _fitsWindows(document);
    final windows = _windows;
    if (windows != null) {
      if (fits) {
        _shown = document;
        unawaited(windows.loadStringContent(document));
      } else {
        _release();
        _shown = null;
        if (mounted) setState(() => _tooLarge = true);
      }
    } else if (_tooLarge && fits) {
      // A smaller document after one too large: WebView2 again.
      if (mounted) setState(() => _tooLarge = false);
      unawaited(_startWindows());
    }
    // A WebView2 still starting loads the newest document when it is up.
  }

  /// Called with the pane's width on every layout: a new width that changes
  /// the fit reloads the document after this frame (never during layout).
  /// An unbounded width fits at 1, and still loads.
  void _layout(double width) {
    _paneWidth = width;
    final zoom = _fit(width);
    if (zoom == _zoom) return;
    _zoom = zoom;
    _reportFit(zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show();
    });
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!HtmlWebView.supported || _failed || _tooLarge) {
      return widget.fallback(context);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _layout(constraints.maxWidth);
        final flutter = _flutter;
        if (flutter != null) {
          return WebViewWidget(
            controller: flutter,
            gestureRecognizers: kHtmlWebViewGestures,
          );
        }
        final windows = _windows;
        if (windows != null) return Webview(windows);
        // WebView2 is starting.
        return const SizedBox.expand();
      },
    );
  }
}
