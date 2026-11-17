import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/bank_account.dart';

import '../../../_localization_helper.dart';

void main() {
  final l = bundledLocalization();
  String label(String wire) => l.lookup(labelKeyForAccountType(wire));

  test('Yodlee containers render as words, never camelCase', () {
    expect(label('creditCard'), 'Credit Card');
    expect(label('CREDITCARD'), 'Credit Card');
    expect(label('bank'), 'Bank');
    expect(label('investment'), 'Investment');
    expect(label('insurance'), 'Insurance');
    expect(label('loan'), 'Loan');
    expect(label('reward'), 'Rewards');
    expect(label('bill'), 'Bill');
    expect(label('realEstate'), 'Real Estate');
    expect(label('otherAssets'), 'Other assets');
    expect(label('otherLiabilities'), 'Other liabilities');
  });

  test('an unknown type is shown as sent', () {
    expect(label('brokerage'), 'brokerage');
  });
}
