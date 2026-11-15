import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/domain/tasks/line_item_notes_display.dart';
import 'package:admin/utils/search_fold.dart';

/// Everything on [item] a search inside a document reads, each field as the
/// text a user would type to find it: the item name, the description without
/// its PDF markup, the four custom values, the tax names, and the figures the
/// line holds as plain decimals (`1250`, `12.5`).
///
/// A figure of zero is left out: an empty Discount cell is not a `0` on
/// screen, and with it the query `0` would match every line in the document.
///
/// The line total is not here. What a screen prints as the total depends on
/// the screen (discount, inclusive tax), so the caller passes it — with
/// anything else it prints that this cannot know, such as a figure in the
/// company's number format (`1.250,00`) or a custom value rendered as a date
/// — through [alsoShown], so that what is on screen is always findable.
List<String> lineItemSearchFields(
  LineItem item, {
  Iterable<String> alsoShown = const [],
}) => [
  item.productKey,
  lineItemNotesPlainText(item.notes),
  item.customValue1,
  item.customValue2,
  item.customValue3,
  item.customValue4,
  item.taxName1,
  item.taxName2,
  item.taxName3,
  for (final figure in [item.quantity, item.cost, item.discount])
    if (figure != Decimal.zero) figure.toString(),
  ...alsoShown,
];

/// The lines of [items] that match [query], as indexes into [items], in
/// document order.
///
/// A line matches when every word of the query occurs in at least one of its
/// fields, in any order and any field, ignoring case and accents — the rule
/// every list and picker search follows
/// (`docs/local-search-matching.md` § Every list search matches each word on
/// its own). A blank query matches nothing: this is "find", not "filter", so
/// an empty field means no matches rather than all of them. Blank lines (the
/// edit table's trailing empty row) never match.
///
/// Indexes, not lines, and never a reordered or shortened copy: the caller
/// highlights and scrolls to rows of the list it already has, so a search can
/// neither change the saved order nor drop a line from the document.
List<int> lineItemSearchMatches(
  List<LineItem> items,
  String query, {
  Iterable<String> Function(LineItem item)? alsoShown,
}) {
  final words = foldedSearchWords(query);
  if (words.isEmpty) return const [];
  return [
    for (var i = 0; i < items.length; i++)
      if (!items[i].isBlank &&
          fieldsMatchEveryWord(
            words,
            lineItemSearchFields(
              items[i],
              alsoShown: alsoShown?.call(items[i]) ?? const [],
            ),
          ))
        i,
  ];
}
