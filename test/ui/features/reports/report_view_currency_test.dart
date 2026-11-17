import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/report_preview.dart';
import 'package:admin/data/repositories/statics_repository.dart';
import 'package:admin/domain/reports/report_column_types.dart';
import 'package:admin/ui/features/reports/view_models/reports_view_model.dart';

import '_report_screen_harness.dart';

/// The invoice report is read in the company's currency however the server
/// orders its rows, and before the screen's `Formatter` has landed too
/// (`docs/reports.md` § A report is read in the company's currency, whatever
/// order its rows arrive in).
void main() {
  late AppDatabase db;
  late StaticsRepository statics;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    statics = StaticsRepository(db: db, service: NullStaticsService());
    await statics.applyStatic({
      'currencies': [
        for (final (id, code) in const [
          ('1', 'USD'),
          ('2', 'GBP'),
          ('3', 'EUR'),
        ])
          {
            'id': id,
            'name': code,
            'code': code,
            'symbol': '',
            'precision': 2,
            'thousand_separator': ',',
            'decimal_separator': '.',
            'swap_currency_symbol': false,
            'exchange_rate': 1,
          },
      ],
    });
  });
  tearDown(() => db.close());

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
      identifier: 'invoice.amount',
      displayLabel: 'Amount',
      type: ReportColumnType.money,
    ),
  ];

  // The demo's mix on 2026-11-17: 13 USD, 3 EUR, 1 GBP — most rows in a
  // currency that is not the company's (EUR).
  final rows = [
    for (var i = 0; i < 17; i++)
      ReportRow(
        cells: [
          ReportStringCell(value: 'Client $i', displayValue: 'Client $i'),
          ReportStringCell(
            value: i == 6
                ? 'GBP'
                : (i == 4 || i == 11 || i == 13 ? 'EUR' : 'USD'),
          ),
          ReportNumberCell(value: Decimal.fromInt(100 + i), isMoney: true),
        ],
      ),
  ];

  Future<ReportsViewModel> ran(List<ReportRow> order) async {
    final vm = ReportsViewModel(
      repo: FixtureReportsRepo(ReportPreview(columns: columns, rows: order)),
      statics: statics,
      initialReport: 'invoice',
      companyCurrencyId: () async => '3',
    );
    addTearDown(vm.dispose);
    await vm.runReport();
    return vm;
  }

  test('the same currency for every order the rows arrive in', () async {
    final random = Random(7);
    final orders = [
      rows,
      rows.reversed.toList(),
      for (var i = 0; i < 4; i++) [...rows]..shuffle(random),
    ];
    final seen = <String>{};
    for (final order in orders) {
      final vm = await ran(order);
      seen
        ..add(vm.buildView(companyCurrencyId: '3').currencyId)
        // The screen's Formatter not landed yet: the view model's own.
        ..add(vm.buildView().currencyId);
    }
    expect(seen, {'3'});
  });

  test('the screen\'s company currency is the one it asks for', () async {
    final vm = await ran(rows);
    expect(vm.buildView(companyCurrencyId: '1').currencyId, '1');
    expect(vm.buildView(companyCurrencyId: '3').currencyId, '3');
  });
}
