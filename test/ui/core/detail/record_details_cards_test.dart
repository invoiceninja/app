import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/core/detail/record_details_cards.dart';
import 'package:admin/ui/core/detail/record_profile_layout.dart';

import '../../../_responsive_helper.dart';

/// `recordDetailsCards` splits a record's Details rows into Details and
/// Additional Info only when the card would be alone and both halves have
/// rows (`docs/detail-screen-layout.md` § A record whose Details card is alone
/// splits it in two).

List<Widget> _rows(List<String> labels) => [for (final l in labels) Text(l)];

Finder _card(String title) =>
    find.byWidgetPredicate((w) => w is RecordRowsCard && w.title == title);

Future<void> _pump(
  WidgetTester tester, {
  required List<String> facts,
  required List<String> bookkeeping,
  bool split = true,
  double width = 1200,
}) => pumpAt(
  tester,
  width,
  Builder(
    builder: (context) => RecordProfileLayout(
      lead: recordDetailsCards(
        context,
        facts: _rows(facts),
        bookkeeping: _rows(bookkeeping),
        split: split,
      ),
    ),
  ),
);

void main() {
  testWidgets('both halves: two level cards side by side on a wide row', (
    tester,
  ) async {
    await _pump(
      tester,
      facts: ['number', 'date', 'type', 'reference'],
      bookkeeping: ['created'],
    );
    final details = tester.getRect(_card('Details'));
    final info = tester.getRect(_card('Additional Info'));
    expect(info.top, details.top);
    expect(info.bottom, details.bottom);
    expect(info.left, greaterThan(details.right));
    expect(
      find.descendant(of: _card('Details'), matching: find.text('created')),
      findsNothing,
    );
  });

  testWidgets('both halves, narrow: stacked, Details first', (tester) async {
    await _pump(
      tester,
      facts: ['number'],
      bookkeeping: ['created'],
      width: 600,
    );
    final details = tester.getRect(_card('Details'));
    final info = tester.getRect(_card('Additional Info'));
    expect(info.top, greaterThan(details.bottom));
    expect(info.left, details.left);
  });

  testWidgets('one half empty: one Details card holding the other', (
    tester,
  ) async {
    await _pump(tester, facts: const [], bookkeeping: ['created', 'updated']);
    expect(_card('Additional Info'), findsNothing);
    expect(
      find.descendant(of: _card('Details'), matching: find.text('updated')),
      findsOneWidget,
    );
  });

  testWidgets('split: false keeps one Details card, facts first', (
    tester,
  ) async {
    await _pump(
      tester,
      facts: ['number'],
      bookkeeping: ['created'],
      split: false,
    );
    expect(_card('Additional Info'), findsNothing);
    expect(
      tester.getTopLeft(find.text('number')).dy,
      lessThan(tester.getTopLeft(find.text('created')).dy),
    );
  });

  testWidgets('no rows at all: no card', (tester) async {
    await _pump(tester, facts: const [], bookkeeping: const []);
    expect(find.byType(RecordRowsCard), findsNothing);
  });
}
