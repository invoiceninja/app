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
/// and a `width` / `min-width` in px inside a `<style>` block (not in a
/// media query's condition). An element whose inline style makes it fluid
/// (`width: 100%`) does not count its width attribute (the fluid-hybrid
/// pattern, `<table width="600" style="width:100%; max-width:600px">`), and
/// `max-width` never counts. Images do not count: an email's images are
/// usually capped at their container (`max-width: 100%`).
double? previewContentWidth(String html) {
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
    for (final d in styleWidth.allMatches(block.group(1)!)) {
      if (d.group(3)?.toLowerCase() != 'px') continue;
      // `@media (min-width: 620px)` is a condition, not a width.
      final before = block.group(1)!.substring(0, d.start).trimRight();
      if (before.endsWith('(')) continue;
      take(double.parse(d.group(2)!));
    }
  }
  return widest;
}

/// The CSS zoom that fits a document [contentWidth] wide (from
/// [previewContentWidth]) into a pane [paneWidth] logical px wide, allowing
/// for the body's default 8 px margins: 1 when it already fits (or declares
/// no width), never below 0.25. Rounded down to a step of 0.05, so a window
/// being resized reloads the preview only every few dozen pixels, and the
/// page still fits.
double previewFitZoom(double? contentWidth, double paneWidth) {
  if (contentWidth == null || !paneWidth.isFinite || paneWidth <= 0) return 1;
  final needed = contentWidth + 16;
  if (needed <= paneWidth) return 1;
  final steps = (paneWidth / needed * 20).floor();
  return (steps / 20).clamp(0.25, 1.0);
}
