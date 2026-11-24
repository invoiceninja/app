import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/ui/core/widgets/html_inline_svg.dart';

import 'sepa_qr_svg_fixture.dart';

Widget _host(String html) => MaterialApp(
  home: Scaffold(
    body: HtmlWidget(html, customWidgetBuilder: htmlInlineSvgBuilder),
  ),
);

void main() {
  testWidgets('the SEPA QR draws as a 200 px picture, not a blank', (
    tester,
  ) async {
    await tester.pumpWidget(_host('<p>Code:<br>$kSepaQrSvg</p><p>After</p>'));
    // The picture decodes off the frame; let it land.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Decoded: the raw picture widget is up (it replaces the placeholder
    // only once the SVG has parsed), at the SVG's own size.
    final picture = find.descendant(
      of: find.byType(SvgPicture),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('_Raw'),
      ),
    );
    expect(picture, findsOneWidget);
    expect(tester.getSize(picture), const Size(200, 200));
    expect(find.text('After', findRichText: true), findsOneWidget);
  });

  testWidgets('markup it cannot read draws nothing, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(_host('<p>A</p><svg><path d="M"></svg><p>B</p>'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('A', findRichText: true), findsOneWidget);
    expect(find.text('B', findRichText: true), findsOneWidget);
  });

  testWidgets('other elements are left to HtmlWidget', (tester) async {
    await tester.pumpWidget(_host('<p>Plain <b>text</b></p>'));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.textContaining('Plain', findRichText: true), findsOneWidget);
  });
}
