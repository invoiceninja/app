import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/domain/billing/line_item_search.dart';

LineItem _line(
  String productKey, {
  String notes = '',
  String cost = '0',
  String quantity = '1',
  String custom1 = '',
  String taxName1 = '',
}) => emptyLineItem().copyWith(
  productKey: productKey,
  notes: notes,
  cost: Decimal.parse(cost),
  quantity: Decimal.parse(quantity),
  customValue1: custom1,
  taxName1: taxName1,
);

void main() {
  final items = [
    _line('Widget Pro', notes: 'Anodised aluminium housing', cost: '1250'),
    _line('Gasket', notes: 'Für Müller GmbH', cost: '4.5', quantity: '12'),
    emptyLineItem(),
    _line('Consulting', notes: 'On-site widget install', custom1: 'Blue'),
    _line('Freight', taxName1: 'GST'),
  ];

  test('every word must match, each in any field', () {
    // `widget` is in the name of line 0 and the description of line 3;
    // `install` only in line 3's description.
    expect(lineItemSearchMatches(items, 'widget'), [0, 3]);
    expect(lineItemSearchMatches(items, 'install widget'), [3]);
    // One word from the name, one from a custom value.
    expect(lineItemSearchMatches(items, 'consulting blue'), [3]);
    // …and a word nothing holds matches nothing.
    expect(lineItemSearchMatches(items, 'widget zebra'), isEmpty);
  });

  test('case and accents are folded, as in every list search', () {
    expect(lineItemSearchMatches(items, 'MULLER'), [1]);
    expect(lineItemSearchMatches(items, 'für'), [1]);
  });

  test('figures and tax names are searchable', () {
    expect(lineItemSearchMatches(items, '1250'), [0]);
    expect(lineItemSearchMatches(items, 'gst'), [4]);
    expect(lineItemSearchMatches(items, '4.5'), [1]);
  });

  test('a zero figure is not text on the line', () {
    // No discount anywhere, and `Freight` has no cost: neither is a `0` on
    // screen, so `0` finds only the lines that print one (`1250`).
    expect(lineItemSearchMatches(items, '0'), [0]);
    final plain = [_line('Widget', cost: '5', quantity: '3')];
    expect(lineItemSearchMatches(plain, '0'), isEmpty);
  });

  test('the line total is the caller\'s: the one its screen prints', () {
    // 4.5 x 12 = 54 is not searched on its own account…
    expect(lineItemSearchMatches(items, '54'), isEmpty);
    // …only as the total the screen shows for that line.
    expect(
      lineItemSearchMatches(
        items,
        '54',
        alsoShown: (it) => [if (it.productKey == 'Gasket') '54.00'],
      ),
      [1],
    );
  });

  test('what the screen prints is findable through alsoShown', () {
    expect(lineItemSearchMatches(items, '1.250,00'), isEmpty);
    expect(
      lineItemSearchMatches(
        items,
        '1.250,00',
        alsoShown: (it) => [if (it.productKey == 'Widget Pro') '1.250,00'],
      ),
      [0],
    );
  });

  test('a blank query matches nothing, and a blank line never matches', () {
    expect(lineItemSearchMatches(items, ''), isEmpty);
    expect(lineItemSearchMatches(items, '   '), isEmpty);
    // The empty line's quantity is 1; that does not find it.
    expect(lineItemSearchMatches(items, '1'), isNot(contains(2)));
  });

  test('task markup in a description is not searched', () {
    final task = _line(
      'Design',
      notes: '<div class="project-header">Website</div>Homepage mockups',
    );
    expect(lineItemSearchMatches([task], 'website mockups'), [0]);
    expect(lineItemSearchMatches([task], 'project-header'), isEmpty);
  });
}
