import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/billing/line_item_find.dart';

void main() {
  group('findOccurrences', () {
    test('ignores case and counts every occurrence, without overlap', () {
      expect(findOccurrences('Widget, WIDGET and widget', 'widget'), [
        (0, 6),
        (8, 14),
        (19, 25),
      ]);
      expect(findOccurrences('aaaa', 'aa'), [(0, 2), (2, 4)]);
    });

    test('a blank query, or one that is only spaces, finds nothing', () {
      expect(findOccurrences('anything', ''), isEmpty);
      expect(findOccurrences('anything', '   '), isEmpty);
    });

    test('surrounding spaces are not part of the query; inner ones are', () {
      expect(findOccurrences('red widget', ' red '), [(0, 3)]);
      expect(findOccurrences('red widget', 'd w'), [(2, 5)]);
    });

    test('the query is text, not a pattern', () {
      expect(findOccurrences(r'Cost (USD) $5.00', r'(USD) $5.'), [(5, 14)]);
      expect(findOccurrences('a.b', '.'), [(1, 2)]);
    });

    test('offsets point into the original text, even where lowering it '
        'would change its length', () {
      // `'İ'.toLowerCase()` is two code units; lowering both sides would shift
      // every offset after it by one.
      const text = 'İstanbul widget';
      final hits = findOccurrences(text, 'WIDGET');
      expect(hits, hasLength(1));
      final (start, end) = hits.single;
      expect(text.substring(start, end), 'widget');
    });
  });

  group('findHits', () {
    test('reading order: line, then the slot order, then left to right', () {
      final rows = [
        {
          LineFindSegment.total: r'$10.00',
          LineFindSegment.name: 'Ten',
          LineFindSegment.notes: 'ten and TEN',
        },
        {LineFindSegment.name: 'Other'},
        {LineFindSegment.custom: 'Size: Ten'},
      ];
      expect(findHits(rows, 'ten'), const [
        FindHit(0, LineFindSegment.name, 0, 3),
        FindHit(0, LineFindSegment.notes, 0, 3),
        FindHit(0, LineFindSegment.notes, 8, 11),
        FindHit(2, LineFindSegment.custom, 6, 9),
      ]);
    });

    test('an empty slot (a line with no discount or tax) never matches', () {
      expect(
        findHits([
          {LineFindSegment.discount: '', LineFindSegment.tax: ''},
        ], 'a'),
        isEmpty,
      );
    });
  });
}
