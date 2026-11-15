import 'package:admin/data/repositories/dashboard_repository.dart';

/// One row of the wide dashboard's panel grid: a pair of panels side by side,
/// one panel across the whole row, or — only when nothing else is possible —
/// one panel in half a row.
class PanelRow {
  const PanelRow.pair(this.first, String this.second) : spans = false;

  const PanelRow.span(this.first) : second = null, spans = true;

  const PanelRow.half(this.first) : second = null, spans = false;

  /// The row's first (or only) panel.
  final String first;

  /// The panel beside [first], or null when the row holds one panel.
  final String? second;

  /// Whether [first] takes the whole row. False for a pair, and for the lone
  /// half-width panel a [PanelRow.half] is.
  final bool spans;

  @override
  bool operator ==(Object other) =>
      other is PanelRow &&
      other.first == first &&
      other.second == second &&
      other.spans == spans;

  @override
  int get hashCode => Object.hash(first, second, spans);

  @override
  String toString() => second != null
      ? 'pair($first, $second)'
      : (spans ? 'span($first)' : 'half($first)');
}

/// Lays [kinds] — the panels to show, in the user's order — out as rows with
/// as few empty half rows as possible.
///
/// The grid used to fill two columns in order, so an odd number of panels left
/// half a row blank, and which panel sat beside the gap changed every time one
/// emptied out and was hidden. The rules, in order:
///
///  * **Panels pair up in order.**
///  * **An odd count gives one list panel the whole row**, chosen so the rest
///    still pair in order: the last panel at an even position that may span.
///    A spanning list panel flows its rows into two columns
///    (`DashboardRecordRows`), so it fills the width instead of stretching
///    each row across it.
///  * **[kNeverSpanPanels] are never stretched.** The task calendar's month
///    grid is capped at 440 px, so across a whole row it is an island; the
///    Invoices and Quotes panels lead with a status strip whose tabs would
///    sit in one corner. When none of the panels could span, the last one
///    keeps its half and the other half stays empty.
///
/// With one column every panel is its own row.
List<PanelRow> layoutPanelRows(List<String> kinds, {required int columns}) {
  if (columns <= 1) {
    return [for (final k in kinds) PanelRow.span(k)];
  }
  // Which panel, if any, takes a whole row so that the others pair.
  var spanAt = -1;
  if (kinds.length.isOdd) {
    for (var i = kinds.length - 1; i >= 0; i -= 2) {
      if (!kNeverSpanPanels.contains(kinds[i])) {
        spanAt = i;
        break;
      }
    }
  }
  final rows = <PanelRow>[];
  var i = 0;
  while (i < kinds.length) {
    if (i == spanAt) {
      rows.add(PanelRow.span(kinds[i]));
      i += 1;
    } else if (i + 1 < kinds.length) {
      rows.add(PanelRow.pair(kinds[i], kinds[i + 1]));
      i += 2;
    } else {
      // Only reachable when no panel at an even position may span.
      rows.add(PanelRow.half(kinds[i]));
      i += 1;
    }
  }
  return rows;
}

/// Panels that keep their half rather than span a row — see
/// [layoutPanelRows].
const Set<String> kNeverSpanPanels = {
  DashboardKind.taskCalendar,
  DashboardKind.invoicesPipeline,
  DashboardKind.quotesPipeline,
};
