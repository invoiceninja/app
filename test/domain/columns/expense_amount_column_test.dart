import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/dao/expense_dao.dart';
import 'package:admin/data/db/dao/recurring_expense_dao.dart';
import 'package:admin/data/models/api/expense_api_model.dart';
import 'package:admin/data/models/api/recurring_expense_api_model.dart';
import 'package:admin/data/models/domain/expense.dart';
import 'package:admin/data/models/domain/recurring_expense.dart';
import 'package:admin/domain/columns/expense_columns.dart';
import 'package:admin/domain/columns/recurring_expense_columns.dart';

/// The expense lists' Amount is the gross amount — exclusive taxes added — as
/// React's lists (`useCalculateExpenseAmount`) and the server's entity totals
/// show it, so the totals line above the list adds up its rows
/// (docs/entity-lists.md § A money list's totals line).
void main() {
  test('an expense\'s Amount adds its exclusive tax', () {
    final e = Expense.fromApi(
      const ExpenseApi(
        id: 'e1',
        amount: '80',
        usesInclusiveTaxes: false,
        taxName1: 'VAT',
        taxRate1: 25,
        updatedAt: 1,
      ),
    );
    final value = expenseColumnsById[ExpenseFieldIds.amount]!.valueBuilder!(e);
    expect(Decimal.parse(value.toString()), Decimal.parse('100'));
  });

  test('a recurring expense\'s Amount adds its exclusive tax', () {
    final e = RecurringExpense.fromApi(
      const RecurringExpenseApi(
        id: 'r1',
        amount: '90',
        usesInclusiveTaxes: false,
        calculateTaxByAmount: true,
        taxAmount1: 10,
        updatedAt: 1,
      ),
    );
    final value = recurringExpenseColumnsById[RecurringExpenseFieldIds.amount]!
        .valueBuilder!(e);
    expect(Decimal.parse(value.toString()), Decimal.parse('100'));
  });
}
