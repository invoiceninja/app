import 'package:flutter_test/flutter_test.dart';

import 'package:admin/utils/url_display.dart';

void main() {
  test('a URL reads as its address', () {
    expect(displayUrl('https://www.acme.com/'), 'acme.com');
    expect(displayUrl('http://acme.com/invoices'), 'acme.com/invoices');
    expect(displayUrl('HTTPS://Acme.com'), 'Acme.com');
    expect(displayUrl('  acme.com  '), 'acme.com');
    expect(displayUrl(''), '');
  });
}
