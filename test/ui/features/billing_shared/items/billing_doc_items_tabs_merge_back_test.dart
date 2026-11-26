import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/ui/features/billing_shared/items/billing_doc_items_tabs.dart';

LineItem _p(String key) =>
    emptyLineItem().copyWith(productKey: key, taskId: null, expenseId: null);

LineItem _t(String id) => emptyLineItem().copyWith(taskId: id);

LineItem _e(String id) => emptyLineItem().copyWith(expenseId: id);

bool _isTask(LineItem li) => (li.taskId ?? '').isNotEmpty;
bool _isProduct(LineItem li) =>
    (li.taskId ?? '').isEmpty && (li.expenseId ?? '').isEmpty;
bool _isExpense(LineItem li) => (li.expenseId ?? '').isNotEmpty;

void main() {
  group('mergeBackByType', () {
    test('reorder within tasks subset — products keep their slots', () {
      final original = [_p('P1'), _t('T1'), _p('P2'), _t('T2'), _p('P3')];
      final tasksUpdated = [_t('T2'), _t('T1')]; // swap

      final result = mergeBackByType(
        original: original,
        updatedSubset: tasksUpdated,
        inSubset: _isTask,
      );

      expect(result.map((li) => li.productKey + (li.taskId ?? '')).toList(), [
        'P1', // unchanged
        'T2', // first task slot now holds T2
        'P2', // unchanged
        'T1', // second task slot now holds T1
        'P3', // unchanged
      ]);
    });

    test('delete the only task — products preserved', () {
      final original = [_p('P1'), _t('T1'), _p('P2')];
      final tasksUpdated = <LineItem>[];

      final result = mergeBackByType(
        original: original,
        updatedSubset: tasksUpdated,
        inSubset: _isTask,
      );

      expect(result.map((li) => li.productKey + (li.taskId ?? '')).toList(), [
        'P1',
        'P2',
      ]);
    });

    test('append new task — net-new rows go to the end', () {
      final original = [_p('P1'), _t('T1')];
      final tasksUpdated = [_t('T1'), _t('T2')]; // extra

      final result = mergeBackByType(
        original: original,
        updatedSubset: tasksUpdated,
        inSubset: _isTask,
      );

      expect(result.map((li) => li.productKey + (li.taskId ?? '')).toList(), [
        'P1',
        'T1',
        'T2', // appended after the original list
      ]);
    });

    test('reorder products — tasks keep their slots', () {
      final original = [_p('P1'), _t('T1'), _p('P2'), _t('T2'), _p('P3')];
      final productsUpdated = [_p('P3'), _p('P1'), _p('P2')];

      final result = mergeBackByType(
        original: original,
        updatedSubset: productsUpdated,
        inSubset: _isProduct,
      );

      expect(result.map((li) => li.productKey + (li.taskId ?? '')).toList(), [
        'P3', // first product slot now holds P3
        'T1', // unchanged
        'P1', // second product slot now holds P1
        'T2', // unchanged
        'P2', // third product slot now holds P2
      ]);
    });

    test('expense subset edits leave products + tasks alone', () {
      final original = [_p('P1'), _e('E1'), _t('T1'), _e('E2')];
      final expensesUpdated = [_e('E2'), _e('E1')]; // swap expenses

      final result = mergeBackByType(
        original: original,
        updatedSubset: expensesUpdated,
        inSubset: _isExpense,
      );

      expect(
        result
            .map(
              (li) => li.productKey + (li.taskId ?? '') + (li.expenseId ?? ''),
            )
            .toList(),
        ['P1', 'E2', 'T1', 'E1'],
      );
    });

    test('empty original + appended new rows', () {
      final original = <LineItem>[];
      final tasksUpdated = [_t('T1'), _t('T2')];

      final result = mergeBackByType(
        original: original,
        updatedSubset: tasksUpdated,
        inSubset: _isTask,
      );

      expect(result.map((li) => li.taskId).toList(), ['T1', 'T2']);
    });

    test('no overlap with subset — original returned verbatim', () {
      final original = [_p('P1'), _p('P2')];
      final tasksUpdated = <LineItem>[];

      final result = mergeBackByType(
        original: original,
        updatedSubset: tasksUpdated,
        inSubset: _isTask,
      );

      expect(result.map((li) => li.productKey).toList(), ['P1', 'P2']);
    });
  });

  // invoiceninja/app#217: a design that prints lines in their saved order
  // needs Move to top / bottom on a per-kind tab to pass the other kinds.
  group('moveLineToDocumentEdge', () {
    String keys(List<LineItem> items) =>
        items.map((li) => li.productKey + (li.taskId ?? '')).join(',');

    test('the only service goes to the end, past later products', () {
      final t1 = _t('T1');
      final original = [t1, _p('P1'), _p('P2')];

      final result = moveLineToDocumentEdge(
        original: original,
        updatedSubset: [t1],
        inSubset: _isTask,
        index: 0,
        toEnd: true,
      );

      expect(keys(result), 'P1,P2,T1');
    });

    test('a line moved to the top of its tab leads the document', () {
      final t1 = _t('T1');
      final t2 = _t('T2');
      final original = [_p('P1'), t1, t2];

      final result = moveLineToDocumentEdge(
        original: original,
        // The table already put T2 first among the tasks.
        updatedSubset: [t2, t1],
        inSubset: _isTask,
        index: 0,
        toEnd: false,
      );

      expect(keys(result), 'T2,P1,T1');
    });

    test('other kinds keep their order, and an edit in the subset lands', () {
      final p1 = _p('P1');
      final edited = p1.copyWith(productKey: 'P1x');
      final original = [p1, _t('T1'), _p('P2'), _e('E1')];

      final result = moveLineToDocumentEdge(
        original: original,
        updatedSubset: [edited, _p('P2')],
        inSubset: _isProduct,
        index: 0,
        toEnd: true,
      );

      expect(keys(result), 'T1,P2,,P1x');
      expect(result[2].expenseId, 'E1');
    });

    test('an index outside the subset only merges back', () {
      final t1 = _t('T1');
      final original = [t1, _p('P1')];

      final result = moveLineToDocumentEdge(
        original: original,
        updatedSubset: [t1],
        inSubset: _isTask,
        index: 5,
        toEnd: true,
      );

      expect(keys(result), 'T1,P1');
    });
  });
}
