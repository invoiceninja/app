import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart'
    show HtmlWidget;
// ignore: depend_on_referenced_packages
import 'package:html/dom.dart' as dom;
import 'package:material_ui/material_ui.dart';

/// Draws an inline `<svg>` for an [HtmlWidget], which on its own draws none:
/// it walks into the element, finds no text, and leaves a blank. Pass it as
/// `customWidgetBuilder`.
///
/// An email body can carry one: `$sepa_qr_code_raw` is the invoice's SEPA
/// payment QR as SVG markup (`HtmlEngine` decodes the escaped
/// `$sepa_qr_code`), and a web view or a mail client draws it. The email
/// preview's `HtmlWidget` fallback (the web, Linux) showed an empty box in
/// its place.
///
/// Markup `flutter_svg` cannot read draws nothing rather than an error.
/// Anything else is left to [HtmlWidget].
Widget? htmlInlineSvgBuilder(dom.Element element) {
  if (element.localName != 'svg') return null;
  return SvgPicture.string(
    element.outerHtml,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
