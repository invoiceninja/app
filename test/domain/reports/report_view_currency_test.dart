import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/report_preview.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/reports/report_column_types.dart';
import 'package:admin/domain/reports/report_engine.dart';
import 'package:admin/domain/reports/report_measures.dart';
import 'package:admin/domain/reports/report_row_currency.dart';

/// The currency a report is read in does not depend on the order the server
/// lists its rows (`docs/reports.md` § A report is read in the company's
/// currency, whatever order its rows arrive in): the reader's choice, else
/// the company's, else the one with the most rows, ties to the lowest id.
///
/// The fixture is the demo invoice report of 2026-11-17 — 13 USD rows, 3 EUR
/// and 1 GBP — whose screenshots came up in USD in one run and EUR in the
/// next. The demo company's currency had been changed from USD to EUR between
/// them; for one company currency the answer is one currency.
void main() {
  const idByCode = {'USD': '1', 'GBP': '2', 'EUR': '3'};
  const columns = [
    ReportColumn(
      identifier: 'client.name',
      displayLabel: 'Client',
      type: ReportColumnType.string,
    ),
    ReportColumn(
      identifier: 'client.currency_id',
      displayLabel: 'Client Currency',
      type: ReportColumnType.string,
    ),
    ReportColumn(
      identifier: 'invoice.date',
      displayLabel: 'Date',
      type: ReportColumnType.date,
    ),
    ReportColumn(
      identifier: 'invoice.amount',
      displayLabel: 'Amount',
      type: ReportColumnType.money,
    ),
  ];

  ReportRow row(int i, String code, int amount) => ReportRow(
    cells: [
      ReportStringCell(value: 'Client $i', displayValue: 'Client $i'),
      ReportStringCell(value: code, displayValue: code),
      ReportDateCell(value: Date(2026, 9 + i % 4, 1 + i)),
      ReportNumberCell(value: Decimal.fromInt(amount), isMoney: true),
    ],
  );

  final demoRows = [
    for (final (i, (code, amount)) in const [
      ('USD', 484), ('USD', 3100), ('USD', 2950), ('USD', 4855), //
      ('EUR', 761), ('USD', 3981), ('GBP', 3593), ('USD', 2114),
      ('USD', 1266), ('USD', 3978), ('USD', 4676), ('EUR', 3866),
      ('USD', 6250), ('EUR', 2286), ('USD', 3020), ('USD', 915),
      ('USD', 3406),
    ].indexed)
      row(i, code, amount),
  ];

  /// [rows] in eight different orders, the server's own first.
  Iterable<List<ReportRow>> orders(List<ReportRow> rows) sync* {
    yield rows;
    yield rows.reversed.toList();
    final random = Random(42);
    for (var i = 0; i < 6; i++) {
      yield [...rows]..shuffle(random);
    }
  }

  /// The view currency and the picker's order for [rows] as they arrive.
  (String, List<String>) read(
    List<ReportRow> rows, {
    String? company,
    String? chosen,
    String? group,
  }) {
    final preview = withRowCurrencies(
      ReportPreview(columns: columns, rows: rows),
      currencyIdByCode: idByCode,
      fallbackCurrencyId: company,
    );
    final view = const ReportEngine().compute(
      preview: preview,
      ui: ReportUiState(
        currencyId: chosen,
        group: group,
        subgroup: group == null ? null : ReportSubgroup.month,
      ),
      exchangeRates: const {},
      companyCurrencyId: company,
    );
    return (view.currencyId, reportCurrencies(view));
  }

  void expectSameInEveryOrder(
    List<ReportRow> rows,
    String expected, {
    String? company,
    String? chosen,
  }) {
    for (final group in [null, 'invoice.date']) {
      final seen = {
        for (final order in orders(rows))
          if (read(order, company: company, chosen: chosen, group: group) case (
            final currency,
            final picker,
          ))
            '$currency in ${picker.join(',')}',
      };
      expect(seen, hasLength(1), reason: 'group $group: $seen');
      expect(seen.single, startsWith('$expected in '), reason: 'group $group');
    }
  }

  test('the company currency wins whatever the row order', () {
    expectSameInEveryOrder(demoRows, '3', company: '3');
    expectSameInEveryOrder(demoRows, '1', company: '1');
    expectSameInEveryOrder(demoRows, '2', company: '2');
  });

  test('the reader\'s choice outranks the company currency', () {
    expectSameInEveryOrder(demoRows, '2', company: '3', chosen: '2');
  });

  test('with no company currency, the most rows, in any order', () {
    expectSameInEveryOrder(demoRows, '1');
    // A company currency the result does not hold is no answer either.
    expectSameInEveryOrder(demoRows, '1', company: '4');
  });

  test('a tie goes to the lowest currency id, in any order', () {
    final tied = [
      row(0, 'EUR', 10),
      row(1, 'USD', 20),
      row(2, 'EUR', 30),
      row(3, 'USD', 40),
    ];
    expectSameInEveryOrder(tied, '1');
  });

  test('the currency picker lists the same order every time', () {
    final lists = {
      for (final order in orders(demoRows))
        read(order, company: '3').$2.join(','),
    };
    expect(lists, {'1,3,2'});
  });
}
