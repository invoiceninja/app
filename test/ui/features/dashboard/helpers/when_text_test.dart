import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/value/date.dart';
import 'package:admin/ui/features/dashboard/helpers/when_text.dart';

/// The table rows' relative sub-line: near or late only, nothing far off,
/// nothing on a closed document (the caller passes a null deadline).
void main() {
  const today = Date(2026, 11, 17);

  group('invoiceRowWhen', () {
    test('a passed due date is late, by whole days', () {
      expect(
        invoiceRowWhen(due: const Date(2026, 11, 5), today: today),
        const RowWhen(RowWhenKind.late, 12),
      );
      expect(
        invoiceRowWhen(due: const Date(2026, 11, 5), today: today)!.isLate,
        isTrue,
      );
    });

    test('within the window it counts down; today is day 0', () {
      expect(
        invoiceRowWhen(due: today, today: today),
        const RowWhen(RowWhenKind.dueIn, 0),
      );
      expect(
        invoiceRowWhen(due: const Date(2026, 12, 17), today: today),
        const RowWhen(RowWhenKind.dueIn, 30),
      );
    });

    test('past the window, or with no deadline, it says nothing', () {
      expect(
        invoiceRowWhen(due: const Date(2026, 12, 18), today: today),
        isNull,
      );
      expect(invoiceRowWhen(due: null, today: today), isNull);
    });

    test('counts calendar days across a month end', () {
      expect(
        invoiceRowWhen(due: const Date(2026, 10, 31), today: today),
        const RowWhen(RowWhenKind.late, 17),
      );
    });
  });

  group('quoteRowWhen', () {
    test('a lapsed valid-until is expired, in the late tone', () {
      final w = quoteRowWhen(validUntil: const Date(2026, 11, 1), today: today);
      expect(w?.kind, RowWhenKind.expired);
      expect(w?.isLate, isTrue);
    });

    test('within the window it says when it expires', () {
      expect(
        quoteRowWhen(validUntil: const Date(2026, 11, 20), today: today),
        const RowWhen(RowWhenKind.expiresIn, 3),
      );
    });

    test('far off, or closed, it says nothing', () {
      expect(
        quoteRowWhen(validUntil: const Date(2027, 2, 1), today: today),
        isNull,
      );
      expect(quoteRowWhen(validUntil: null, today: today), isNull);
    });
  });
}
