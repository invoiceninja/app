import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/domain/outstanding_by_currency.dart';

Map<String, dynamic> _bucket(String code, String amount) => {
  'outstanding': {'amount': amount, 'code': code, 'outstanding_count': 1},
};

void main() {
  test('unknown stays unknown — never zero', () {
    expect(outstandingByCurrency(null, baseCurrencyId: '1'), isNull);
  });

  test('nothing outstanding is empty, so the line hides', () {
    final totals = DashboardTotals.fromJson({
      'currencies': {'1': 'USD'},
      '1': _bucket('USD', '0'),
      '999': _bucket('USD', '0'),
    });
    expect(outstandingByCurrency(totals, baseCurrencyId: '1'), isEmpty);
  });

  test('one entry per currency with a balance, the company currency first, '
      'and never the converted 999 aggregate', () {
    final totals = DashboardTotals.fromJson({
      'currencies': {'2': 'GBP', '1': 'USD', '3': 'EUR'},
      'start_date': '1970-01-01',
      '2': _bucket('GBP', '6091.00'),
      '3': _bucket('EUR', '0'),
      '1': _bucket('USD', '22924.00'),
      '999': _bucket('USD', '31000.00'),
    });
    final out = outstandingByCurrency(totals, baseCurrencyId: '1')!;
    expect([for (final e in out) e.currencyId], ['1', '2']);
    expect(out.first.amount, Decimal.parse('22924.00'));
  });
}
