/// Find within a billing document's line items — the in-app answer to the
/// browser's Ctrl+F, which finds nothing on a Flutter web page because the
/// page is painted, not laid out as text (`docs/find-in-line-items.md`).
///
/// A leaf over plain strings: the read-only table hands in each drawn line's
/// texts exactly as it renders them, so a match is always something on screen
/// and the count the bar shows is the count the table highlights.
library;

/// The texts of one drawn line. A slot the line does not draw (no discount,
/// no tax) is the empty string, which never matches. The declaration order is
/// the wide table's reading order; [kStackedFindOrder] is the stacked one's.
enum LineFindSegment {
  name,
  notes,
  custom,
  quantity,
  cost,
  discount,
  tax,
  total,
}

/// The stacked (phone) layout draws the line total on the title line, beside
/// the name, so it is counted second there — stepping would otherwise jump
/// back up the line from the figures at its foot.
const List<LineFindSegment> kStackedFindOrder = [
  LineFindSegment.name,
  LineFindSegment.total,
  LineFindSegment.notes,
  LineFindSegment.custom,
  LineFindSegment.quantity,
  LineFindSegment.cost,
  LineFindSegment.discount,
  LineFindSegment.tax,
];

/// One occurrence of the query: in drawn line [row], in its [segment] text,
/// over `[start, end)`.
class FindHit {
  const FindHit(this.row, this.segment, this.start, this.end);

  final int row;
  final LineFindSegment segment;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is FindHit &&
      other.row == row &&
      other.segment == segment &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(row, segment, start, end);

  @override
  String toString() => 'FindHit($row, ${segment.name}, $start, $end)';
}

/// The query as it is matched: surrounding whitespace dropped, nothing else.
/// Blank means "no search".
String normalizeFindQuery(String query) => query.trim();

/// Every `[start, end)` at which [query] occurs in [text], ignoring case,
/// without overlaps — what a browser's find counts. Matched by a
/// case-insensitive `RegExp` over the original text rather than by lowering
/// both sides, because lowering can change a string's length (`İ` becomes two
/// code units) and the offsets would then point into the wrong characters.
List<(int, int)> findOccurrences(String text, String query) {
  final q = normalizeFindQuery(query);
  if (q.isEmpty || text.isEmpty) return const [];
  final pattern = RegExp(RegExp.escape(q), caseSensitive: false, unicode: true);
  return [for (final m in pattern.allMatches(text)) (m.start, m.end)];
}

/// Every hit of [query] across [rows] — one map of segment texts per drawn
/// line — in reading order: line by line, then slot by slot in [order] (the
/// order the layout draws them), then left to right.
List<FindHit> findHits(
  List<Map<LineFindSegment, String>> rows,
  String query, {
  List<LineFindSegment> order = LineFindSegment.values,
}) {
  if (normalizeFindQuery(query).isEmpty) return const [];
  final hits = <FindHit>[];
  for (var r = 0; r < rows.length; r++) {
    for (final segment in order) {
      final text = rows[r][segment] ?? '';
      for (final (start, end) in findOccurrences(text, query)) {
        hits.add(FindHit(r, segment, start, end));
      }
    }
  }
  return hits;
}
