/// HTML the app shows in a web view as a picture of a document (an email
/// preview), never as a page:
///
/// - **No script runs**: a Content-Security-Policy allows none, on every
///   platform alike (a custom template is user-written HTML, and the
///   Windows web view the app uses exposes no switch to turn JavaScript
///   off). It also refuses form submissions.
/// - **No link or form leaves**: `<base target="_blank">` sends every link
///   to a new window, which the web views refuse, so a tap never reaches the
///   server (a real portal link would mark the invoice viewed).
/// - **It reads as the email will**: light, on white, whatever the app's
///   theme (`color-scheme: light only`), unless the email sets its own
///   colours.
///
/// These go first in the document, right after its doctype (before any
/// comment or prolog-free markup), where the HTML parser puts them into the
/// head it makes, whatever follows: a document's own `<head>` then merges
/// into that one, and the server's email wrapper, which has no `<head>` (it
/// strips it), works the same. Inserting inside a `<head>` was wrong twice
/// over: markup before that head (`<html><script>…<head>`) ran first, and a
/// full HTML email pasted into a template's body brings a `<head>` *inside*
/// the wrapper's body, where a policy is ignored. A doctype inside a comment
/// is not the doctype. A `<meta http-equiv="refresh">` is dropped too: no
/// policy stops it, and it would send the preview off to its address.
///
/// - **It fits the pane, and a finger can zoom it**: the document's own
///   viewport tags are dropped for one of ours (`width=device-width,
///   initial-scale=1`, user scaling left on), and a [zoom] below 1 (from
///   [previewFitZoom]) scales the whole page down with CSS `zoom` on the
///   root, so a 570 px email table lays out whole on a 390 px phone. CSS
///   zoom, not a wider viewport, because only iOS honours a viewport tag
///   (`webview_flutter_android` turns the wide viewport off, and macOS and
///   WebView2 ignore it) and zoom works on all four. A pinch then zooms in
///   from there (docs/windows-web-view.md).
String previewHtml(String html, {double zoom = 1}) {
  final fit = zoom < 1 ? ':root { zoom: ${_zoomText(zoom)} !important; }' : '';
  final head =
      '<meta http-equiv="Content-Security-Policy" '
      "content=\"script-src 'none'; object-src 'none'; base-uri 'none'; "
      "form-action 'none'\">"
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<base target="_blank">'
      '<style>:root { color-scheme: light only !important; }$fit</style>';
  final doc = html
      .replaceAll(
        RegExp(
          r'''<meta\b[^>]*http-equiv\s*=\s*["']?refresh["']?[^>]*>''',
          caseSensitive: false,
        ),
        '',
      )
      // Ours is the only one: WebKit takes the last viewport tag, and the
      // server's (`initial-scale=1.0`) or a custom template's would win.
      .replaceAll(
        RegExp(
          r'''<meta\b[^>]*name\s*=\s*["']?viewport["']?[^>]*>''',
          caseSensitive: false,
        ),
        '',
      );
  final comments = [
    for (final m in RegExp(r'<!--[\s\S]*?(-->|$)').allMatches(doc))
      (m.start, m.end),
  ];
  bool commented(int at) => comments.any((c) => at >= c.$1 && at < c.$2);
  RegExpMatch? first(RegExp tag) {
    for (final m in tag.allMatches(doc)) {
      if (!commented(m.start)) return m;
    }
    return null;
  }

  // After the doctype, or quirks mode would follow. Only the document's
  // own doctype counts: one with nothing but comments, white space or an
  // XML prolog before it, not one a pasted email brings into the body.
  final doctype = first(RegExp(r'<!doctype[^>]*>', caseSensitive: false));
  var at = 0;
  if (doctype != null) {
    final before = doc
        .substring(0, doctype.start)
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'<\?xml[^>]*\?>', caseSensitive: false), '');
    if (before.trim().isEmpty) at = doctype.end;
  }
  return doc.replaceRange(at, at, head);
}

String _zoomText(double zoom) {
  final text = zoom.toStringAsFixed(2);
  return text.endsWith('0') ? zoom.toStringAsFixed(1) : text;
}

/// The widest fixed layout width, in CSS px, that [html] declares, or null
/// when it declares none (a fluid email, like the server's "plain" style).
///
/// Without a script (none runs in a preview) the page cannot be measured, so
/// this reads what the markup says: a `width="570"` attribute or an inline
/// `width: 570px` / `min-width: 570px` on a table, cell, div or center tag,
/// and a `width` / `min-width` in px inside a `<style>` block. An element
/// whose inline style makes it fluid
/// (`width: 100%`) does not count its width attribute (the fluid-hybrid
/// pattern, `<table width="600" style="width:100%; max-width:600px">`), and
/// `max-width` never counts. Images do not count: an email's images are
/// usually capped at their container (`max-width: 100%`).
///
/// Nothing inside a comment counts: the server's own "View invoice" button
/// (`HtmlEngine::buildViewButton`, in every default body) carries an
/// Outlook-only `<!--[if mso]><table style="width: 600px">` that would read
/// the 570 px wrapper as 600 and scale a fluid template. Nothing inside an
/// `@media` block counts either: a responsive template (Unlayer, Beefree,
/// Foundation) sets its desktop width there, under a query a phone does not
/// match, and its mobile rules already fit.
double? previewContentWidth(String input) {
  final html = input.replaceAll(RegExp(r'<!--[\s\S]*?(?:-->|$)'), '');
  double? widest;
  void take(double? w) {
    if (w == null || w <= 0) return;
    if (widest == null || w > widest!) widest = w;
  }

  final styleWidth = RegExp(
    r'(?<![\w-])(min-)?width\s*:\s*(\d+(?:\.\d+)?)\s*(px|%)?',
    caseSensitive: false,
  );
  final tag = RegExp(
    r'<(?:table|td|th|div|center|body)\b([^>]*)>',
    caseSensitive: false,
  );
  final widthAttribute = RegExp(
    r"""(?<![\w-])width\s*=\s*["']?\s*(\d+(?:\.\d+)?)\s*(px)?\s*(?=["'\s>/]|$)""",
    caseSensitive: false,
  );
  final styleAttribute = RegExp(
    r"""(?<![\w-])style\s*=\s*("([^"]*)"|'([^']*)')""",
    caseSensitive: false,
  );
  for (final m in tag.allMatches(html)) {
    final attributes = m.group(1)!;
    final style = styleAttribute.firstMatch(attributes);
    final declarations = style == null
        ? ''
        : (style.group(2) ?? style.group(3) ?? '');
    // The attribute without the style, so `style="width:…"` is not read as
    // a width attribute.
    final bare = style == null
        ? attributes
        : attributes.replaceRange(style.start, style.end, '');
    var fluid = false;
    double? styled;
    for (final d in styleWidth.allMatches(declarations)) {
      final value = double.parse(d.group(2)!);
      final unit = d.group(3)?.toLowerCase();
      if (d.group(1) != null) {
        if (unit == 'px') take(value);
      } else if (unit == 'px') {
        styled = value;
      } else if (unit == '%') {
        fluid = true;
      }
    }
    if (styled != null) {
      take(styled);
    } else if (!fluid) {
      final a = widthAttribute.firstMatch(bare);
      if (a != null) take(double.parse(a.group(1)!));
    }
  }
  for (final block in RegExp(
    r'<style\b[^>]*>([\s\S]*?)</style>',
    caseSensitive: false,
  ).allMatches(html)) {
    final css = _withoutMediaBlocks(
      block.group(1)!.replaceAll(RegExp(r'/\*[\s\S]*?(?:\*/|$)'), ''),
    );
    for (final d in styleWidth.allMatches(css)) {
      if (d.group(3)?.toLowerCase() != 'px') continue;
      take(double.parse(d.group(2)!));
    }
  }
  return widest;
}

/// [css] without its `@media` rules, condition and block (braces matched,
/// so a nested rule does not end it early). An unclosed block runs to the
/// end, as a browser reads it.
String _withoutMediaBlocks(String css) {
  final media = RegExp(r'@media\b', caseSensitive: false);
  final out = StringBuffer();
  var at = 0;
  while (true) {
    final m = media.firstMatch(css.substring(at));
    if (m == null) break;
    final start = at + m.start;
    out.write(css.substring(at, start));
    final open = css.indexOf('{', start);
    if (open < 0) return out.toString();
    var depth = 0;
    var i = open;
    for (; i < css.length; i++) {
      final c = css[i];
      if (c == '{') depth++;
      if (c == '}' && --depth == 0) break;
    }
    if (i >= css.length) return out.toString();
    at = i + 1;
  }
  out.write(css.substring(at));
  return out.toString();
}

/// The CSS zoom that fits a document [contentWidth] wide (from
/// [previewContentWidth]) into a pane [paneWidth] logical px wide, allowing
/// for the body's default 8 px margins: 1 when it already fits (or declares
/// no width), never below [floor]. Rounded down to a step of 0.05, so a
/// window being resized reloads the preview only every few dozen pixels,
/// and the page still fits.
///
/// [floor] is [kPreviewTouchZoomFloor] where a pinch can zoom the preview
/// back in (iOS, Android), and [kPreviewDesktopZoomFloor] where it cannot
/// (macOS's web view has no magnification; Windows only Ctrl+wheel): there
/// the text stays readable and the rest of the email scrolls sideways.
double previewFitZoom(
  double? contentWidth,
  double paneWidth, {
  double floor = kPreviewTouchZoomFloor,
}) {
  if (contentWidth == null || !paneWidth.isFinite || paneWidth <= 0) return 1;
  final needed = contentWidth + 16;
  if (needed <= paneWidth) return 1;
  final steps = (paneWidth / needed * 20).floor();
  return (steps / 20).clamp(floor, 1.0);
}

/// The smallest fit where a pinch zooms the preview back in.
const kPreviewTouchZoomFloor = 0.25;

/// The smallest fit where nothing zooms it back in (macOS, Windows).
const kPreviewDesktopZoomFloor = 0.8;
