import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/features/settings/widgets/tax_worked_example.dart';

void main() {
  Decimal d(String v) => Decimal.parse(v);

  test('exclusive adds the tax on top', () {
    final p = taxExampleParts(
      amount: d('100'),
      ratePercent: d('10'),
      inclusive: false,
    );
    expect(p.net, d('100'));
    expect(p.tax, d('10'));
  });

  // Taxer::calcInclusiveLineTax: amount − amount / (1 + rate).
  test('inclusive takes the tax out of the amount', () {
    final p = taxExampleParts(
      amount: d('100'),
      ratePercent: d('10'),
      inclusive: true,
    );
    expect(p.tax, d('9.09'));
    expect(p.net, d('90.91'));
    expect(p.net + p.tax, d('100'));
  });

  test('the parts always add back to the amount', () {
    final p = taxExampleParts(
      amount: d('100'),
      ratePercent: d('7.7'),
      inclusive: true,
    );
    expect(p.tax, d('7.15'));
    expect(p.net + p.tax, d('100'));
  });
}
