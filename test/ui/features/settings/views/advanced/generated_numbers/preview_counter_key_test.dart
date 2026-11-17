import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/features/settings/views/advanced/generated_numbers/bodies/entity_body.dart';

void main() {
  String? Function(String) settings(Map<String, String> values) =>
      (key) => values[key];

  test('a shared quote counter previews from the invoice counter', () {
    expect(
      previewCounterKey(
        'quote_number_counter',
        settings({'shared_invoice_quote_counter': 'true'}),
      ),
      'invoice_number_counter',
    );
  });

  test('a shared credit counter previews from the invoice counter', () {
    expect(
      previewCounterKey(
        'credit_number_counter',
        settings({'shared_invoice_credit_counter': 'true'}),
      ),
      'invoice_number_counter',
    );
  });

  test('unshared, or unset, keeps the tab\'s own counter', () {
    expect(
      previewCounterKey(
        'quote_number_counter',
        settings({'shared_invoice_quote_counter': 'false'}),
      ),
      'quote_number_counter',
    );
    expect(
      previewCounterKey('credit_number_counter', settings({})),
      'credit_number_counter',
    );
  });

  test('only quotes and credits can share', () {
    // The quote flag says nothing about the payment counter.
    expect(
      previewCounterKey(
        'payment_number_counter',
        settings({
          'shared_invoice_quote_counter': 'true',
          'shared_invoice_credit_counter': 'true',
        }),
      ),
      'payment_number_counter',
    );
  });
}
