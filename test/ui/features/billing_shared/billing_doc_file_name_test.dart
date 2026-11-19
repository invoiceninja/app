import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/features/billing_shared/billing_doc_file_name.dart';

/// The fallback must look like the server's own default name
/// (`BaseModel::numberFormatter()`), so a file the app names itself matches
/// the one the same document has in its email and the client portal.
void main() {
  test('the type, an underscore, the number', () {
    expect(billingDocFileBase('Invoice', '0042'), 'Invoice_0042');
  });

  test('whitespace becomes an underscore, as the server does it', () {
    expect(billingDocFileBase('Purchase Order', '0042'), 'Purchase_Order_0042');
    expect(
      billingDocFileBase('Recurring Invoice', 'R 7'),
      'Recurring_Invoice_R_7',
    );
  });
}
