import 'package:admin/utils/html_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = "script-src 'none'";

  test('the preview tags go first, ahead of the document\'s own head', () {
    final out = previewHtml(
      '<html><script>y()</script><head lang="en"><script>x()</script></head>'
      '<body></body></html>',
    );
    // Ahead of a script before the head too, which ran first.
    expect(out, startsWith('<meta'));
    expect(out.indexOf(policy), lessThan(out.indexOf('<script>')));
    expect(out, contains('<base target="_blank">'));
    expect(out, contains("form-action 'none'"));
    expect(out, contains('color-scheme: light only'));
  });

  test('a document without a head gets the tags first', () {
    final out = previewHtml('<HTML><body>hi</body></HTML>');
    expect(out, startsWith('<meta'));
    expect(out, contains(policy));
  });

  test('after a doctype, never before it (quirks mode)', () {
    final out = previewHtml('<!DOCTYPE html><html><body>hi</body></html>');
    expect(out, startsWith('<!DOCTYPE html><meta'));
  });

  test('the server wrapper (no head) with a pasted email in its body', () {
    // TemplateEngine strips the wrapper's <head>; a full HTML email pasted
    // into the body brings one inside <body>, where a policy is ignored.
    const wrapper =
        '<!DOCTYPE html><html><meta charset="utf-8"><style>p{}</style>'
        '<body><div id="content"><html><head><title>x</title></head>'
        '<body><script>alert(1)</script></body></html></div></body></html>';
    final out = previewHtml(wrapper);
    expect(out, startsWith('<!DOCTYPE html><meta'));
    expect(out.indexOf(policy), lessThan(out.indexOf('<body')));
  });

  test('a fragment gets the tags in front', () {
    final out = previewHtml('<p>Hello</p>');
    expect(out, startsWith('<meta'));
    expect(out, endsWith('<p>Hello</p>'));
  });

  test('a <header> element is not mistaken for <head>', () {
    final out = previewHtml('<header>Top</header><p>x</p>');
    expect(out, startsWith('<meta'));
  });

  test('a doctype after a comment or a prolog still leads', () {
    expect(
      previewHtml('<!-- x --><!DOCTYPE html><html></html>'),
      startsWith('<!-- x --><!DOCTYPE html><meta'),
    );
    expect(
      previewHtml('<?xml version="1.0"?>\n<!DOCTYPE html><html></html>'),
      contains('<!DOCTYPE html><meta'),
    );
  });

  test('a doctype a pasted email brings into the body is not the doctype', () {
    final out = previewHtml(
      '<html><body><!DOCTYPE html><html><body>x</body></html></body></html>',
    );
    expect(out, startsWith('<meta'));
  });

  test('a doctype inside a comment is not the doctype', () {
    final out = previewHtml('<!-- <!DOCTYPE html> --><html></html>');
    expect(out, startsWith('<meta'));
  });

  test('a meta refresh is dropped', () {
    final out = previewHtml(
      '<html><head><META HTTP-EQUIV="Refresh" content="0; url=https://x.y">'
      '</head></html>',
    );
    expect(out.toLowerCase(), isNot(contains('refresh')));
    expect(out, contains(policy));
  });

  group('fit to the pane, pinch to zoom (cut off on an iPhone, 5.1.32)', () {
    test("the document's viewport tags give way to ours", () {
      // The server's wrapper says initial-scale=1.0, and WebKit takes the
      // last viewport tag, so it has to go for ours to count.
      final out = previewHtml(
        '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0"/>'
        "<META NAME='Viewport' CONTENT='width=600, user-scalable=no'>"
        '</head><body></body></html>',
      );
      expect(
        RegExp('name="?viewport', caseSensitive: false).allMatches(out),
        hasLength(1),
      );
      expect(
        out,
        contains(
          '<meta name="viewport" content="width=device-width, '
          'initial-scale=1">',
        ),
      );
      // Nothing stops the user zooming.
      expect(out, isNot(contains('user-scalable')));
      expect(out, isNot(contains('maximum-scale')));
      // The policy still leads.
      expect(out, startsWith('<!DOCTYPE html><meta http-equiv'));
    });

    test('a zoom below 1 scales the root; 1 adds none', () {
      expect(
        previewHtml('<p>x</p>', zoom: 0.65),
        contains(':root { zoom: 0.65 !important; }'),
      );
      expect(
        previewHtml('<p>x</p>', zoom: 0.7),
        contains(':root { zoom: 0.7 !important; }'),
      );
      expect(previewHtml('<p>x</p>'), isNot(contains('zoom')));
      // The zoom control zooms in too, and a hundredth survives.
      expect(
        previewHtml('<p>x</p>', zoom: 1.25),
        contains(':root { zoom: 1.25 !important; }'),
      );
      expect(
        previewHtml('<p>x</p>', zoom: 2),
        contains(':root { zoom: 2 !important; }'),
      );
      expect(
        previewHtml('<p>x</p>', zoom: 0.61),
        contains(':root { zoom: 0.61 !important; }'),
      );
    });

    test("the server's email wrapper is 570 wide, and fits a phone", () {
      // The shape of resources/views/email/template/client.blade.php.
      const wrapper = '''
<!DOCTYPE html><html><meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<style>#content .button { padding: 15px 50px; } @media (min-width: 900px) { p { margin: 0 } }</style>
<body style="margin: 0; padding: 0;">
<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" >
<tr><td><table align="center" border="0" cellpadding="0" cellspacing="0" width="570"
 style="border: 1px solid #c2c2c2; border-collapse: collapse;">
<tr><td><img src="x.png" style="display: block; width: auto; max-width: 300px;"></td></tr>
</table></td></tr></table></body></html>''';
      final width = previewContentWidth(wrapper);
      expect(width, 570);
      // An iPhone's pane: scaled to fit, on a 0.05 step, never wider.
      final zoom = previewFitZoom(width, 358);
      expect(zoom, 0.6);
      expect((570 + 16) * zoom, lessThanOrEqualTo(358));
      // A pane it fits: left alone.
      expect(previewFitZoom(width, 800), 1);
    });

    test('a fluid email declares no width and is never scaled', () {
      // The server's "plain" style, and a fluid custom template.
      expect(
        previewContentWidth('<div id="content-wrapper"><p>Hi</p></div>'),
        isNull,
      );
      expect(previewFitZoom(null, 320), 1);
      // A table whose style makes it fluid does not count its attribute.
      expect(
        previewContentWidth(
          '<table width="600" style="width:100%; max-width:600px"></table>',
        ),
        isNull,
      );
      // max-width never counts, and neither does an image.
      expect(
        previewContentWidth(
          '<div style="max-width: 640px"><img width="1200" src="a.png"></div>',
        ),
        isNull,
      );
    });

    test('inline px widths, min-width and style blocks count', () {
      expect(previewContentWidth('<div style="width: 640px"></div>'), 640);
      expect(
        previewContentWidth('<td style="min-width:520px; width:100%"></td>'),
        520,
      );
      expect(
        previewContentWidth(
          '<style>.wrap { width: 600px } @media (min-width: 900px) {}</style>',
        ),
        600,
      );
      // The style's px width wins over the attribute.
      expect(
        previewContentWidth('<table width="800" style="width: 500px"></table>'),
        500,
      );
      expect(previewContentWidth('<TABLE WIDTH=700></TABLE>'), 700);
    });

    test('the zoom has a floor, and an unbounded pane is left alone', () {
      // On touch never below 0.5: one stray 1200 px spacer shrank a whole
      // email to 4 px text at the old 0.25.
      expect(previewFitZoom(4000, 320), kPreviewTouchZoomFloor);
      expect(kPreviewTouchZoomFloor, 0.5);
      expect(previewFitZoom(570, double.infinity), 1);
      expect(previewFitZoom(570, 0), 1);
      // Where nothing zooms it back in (macOS, Windows), no smaller than 0.8.
      expect(
        previewFitZoom(570, 358, floor: kPreviewDesktopZoomFloor),
        kPreviewDesktopZoomFloor,
      );
      expect(previewFitZoom(570, 560, floor: kPreviewDesktopZoomFloor), 0.95);
    });

    // HtmlEngine::buildViewButton, in every default body: an Outlook-only
    // 600 px table inside a conditional comment.
    const viewButton = '''
<div class="center">
<!--[if (gte mso 9)|(IE)]>
<table align="center" cellspacing="0" cellpadding="0" style="width: 600px;">
    <tr>
    <td align="center" valign="top">
        <![endif]-->
        <table align="center" border="0" cellpadding="0" cellspacing="0" role="presentation" >
        <tbody><tr>
        <td align="center" class="new_button" style="border-radius: 2px; background-color: #f60">
            <a href="https://x.y" target="_blank" style="display: inline-block; padding-left: 25px;">
            <span label="cta button">Voir la facture</span>
            </a>
        </td>
        </tr>
        </tbody>
        </table>
<!--[if (gte mso 9)|(IE)]>
    </td>
    </tr>
</table>
<![endif]-->
</div>''';

    test('a comment does not count: the wrapper with its button is 570', () {
      const wrapper =
          '<!DOCTYPE html><html><body style="margin: 0;">'
          '<table width="100%"><tr><td>'
          '<table align="center" width="570"><tr><td><div id="content">'
          '$viewButton'
          '</div></td></tr></table></td></tr></table></body></html>';
      expect(previewContentWidth(wrapper), 570);
      // An unclosed comment runs to the end.
      expect(
        previewContentWidth('<div></div><!-- <table width="900">'),
        isNull,
      );
    });

    test('a fluid custom wrapper with the button is not scaled', () {
      const custom =
          '<html><body><div style="padding: 12px">'
          '$viewButton'
          '</div></body></html>';
      expect(previewContentWidth(custom), isNull);
    });

    test('an @media block does not count (a responsive template)', () {
      // Unlayer's shape: the desktop width under a query a phone does not
      // match, the mobile rules already fit.
      const unlayer = '''
<style type="text/css">
  @media only screen and (min-width: 620px) {
    .u-row { width: 600px !important; }
    .u-row .u-col-100 { width: 600px !important; }
  }
  @media (max-width: 620px) {
    .u-row-container { max-width: 100% !important; }
    .u-row { width: 100% !important; }
  }
  /* .old { width: 900px } */
  table, td { color: #000000; }
</style>
<div class="u-row" style="margin: 0 auto; min-width: 320px; max-width: 600px;">x</div>''';
      // Its max-width query makes it responsive: shown at its own size.
      expect(previewContentWidth(unlayer), isNull);
      expect(previewFitZoom(previewContentWidth(unlayer), 358), 1);
      // A nested block inside @media (an @supports) does not end it early,
      // and a rule after it still counts.
      expect(
        previewContentWidth(
          '<style>@media screen { @supports (display: grid) { a { b: c } } '
          '.x { width: 700px } } .wrap { width: 540px }</style>',
        ),
        540,
      );
    });
  });

  test('a desktop-first template that narrows itself on a phone is not '
      'scaled', () {
    // The classic responsive email: 600 px, 100 % under a max-width query.
    // A phone matches it, so the email already fits, as Mail shows it.
    const responsive = '''
<style>
  .container { width: 600px; }
  @media only screen and (max-width: 480px) {
    .container { width: 100% !important; }
  }
</style>
<table class="container" width="600"><tr><td>x</td></tr></table>''';
    expect(previewContentWidth(responsive), isNull);
    expect(
      previewContentWidth(
        '<style>@media screen and (max-device-width: 480px) { a {} }</style>'
        '<table width="600"></table>',
      ),
      isNull,
    );
    // A min-width query alone (desktop-up) is no such promise.
    expect(
      previewContentWidth(
        '<style>@media (min-width: 620px) { .x { width: 600px } }</style>'
        '<table width="570"></table>',
      ),
      570,
    );
  });

  test('a phone fits to the hundredth', () {
    expect(previewFitZoom(570, 358, steps: 100), 0.61);
    expect(previewFitZoom(570, 358), 0.6);
  });

  test('the zoom control steps like a browser, and stops at the ends', () {
    expect(previewZoomStep(1, zoomIn: true), 1.1);
    expect(previewZoomStep(1, zoomIn: false), 0.9);
    // From a fit between steps, to the next step either way.
    expect(previewZoomStep(0.61, zoomIn: true), 0.67);
    expect(previewZoomStep(0.61, zoomIn: false), 0.5);
    expect(previewZoomStep(2, zoomIn: true), 2);
    expect(previewZoomStep(0.25, zoomIn: false), 0.25);
  });
}
