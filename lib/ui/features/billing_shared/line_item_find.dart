import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/domain/billing/line_item_find.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

/// The state of a billing document's find in line items
/// (`docs/find-in-line-items.md`): whether the bar is open, the query, and
/// which hit is the current one.
///
/// Two owners, one per screen, each publishing it through
/// [LineItemFindScope]:
///
///  * **The record** (`BillingDocRecordBody`, which all five billing documents
///    share). Two widgets read it: the bar ([LineItemFindBar], pinned under the
///    tab strip so it stays on screen while the page scrolls from hit to hit)
///    and the read-only line-items table, which highlights. The table is also
///    where the searched texts come from — it hands each drawn line's texts in
///    through [updateRows], exactly as it draws them, so the bar's count and
///    the table's highlights cannot disagree.
///  * **The editor** (`BillingDocEditLayout`), where every line is a row of
///    editable fields, so nothing is highlighted inside a field: the matching
///    lines are tinted instead ([LineItemFindRowMarker]), one row per line of
///    the draft, and [oneHitPerLine] makes a step always move to another line.
class LineItemFindController extends ChangeNotifier {
  LineItemFindController({this.oneHitPerLine = false}) {
    query.addListener(_onQueryChanged);
  }

  /// Count a line once, however often it matches — the editor's mode. A
  /// tinted row cannot show which of two hits inside it is the current one,
  /// so stepping between them would change the count and nothing on screen.
  final bool oneHitPerLine;

  /// The find field's text.
  final TextEditingController query = TextEditingController();

  /// The find field's focus — requested on every [open], so ⌘F pressed again
  /// goes back to the field and selects the query, as a browser's does.
  final FocusNode field = FocusNode(debugLabel: 'line-item-find');

  /// One key per drawn line, always on it — never moved to the line holding
  /// the current hit, which would remount both lines on every step — so
  /// [_reveal] can find the current one.
  final List<GlobalKey> _rowKeys = [];

  /// The key of drawn line [row].
  GlobalKey rowKey(int row) {
    while (_rowKeys.length <= row) {
      _rowKeys.add(GlobalKey(debugLabel: 'line-item-find-row'));
    }
    return _rowKeys[row];
  }

  bool _open = false;
  bool _disposed = false;
  String _lastQuery = '';
  int _current = 0;
  List<Map<LineFindSegment, String>> _rows = const [];
  List<LineFindSegment> _order = LineFindSegment.values;

  /// When Enter last stepped, as a key event — see [submitted].
  DateTime? _keyStepAt;
  List<FindHit>? _hits;
  Set<int>? _hitRows;
  bool _notifyScheduled = false;
  int _revealGeneration = 0;

  /// The editor's tinted rows, by row — the context [_reveal] scrolls to,
  /// registered by each [LineItemFindRowMarker]. A context rather than a
  /// [rowKey]: the editor's rows reorder, and a `GlobalKey` that followed an
  /// index would move the editable row under it from line to line.
  final Map<int, BuildContext> _rowContexts = {};

  bool get isOpen => _open;

  /// The query as it is matched — blank is "no search".
  String get normalizedQuery => normalizeFindQuery(query.text);

  /// Every hit, in reading order — with [oneHitPerLine], each line's first.
  /// Recomputed only when the query or the rows change.
  List<FindHit> get hits => _hits ??= _computeHits();

  List<FindHit> _computeHits() {
    final all = findHits(_rows, query.text, order: _order);
    if (!oneHitPerLine) return all;
    final seen = <int>{};
    return [
      for (final hit in all)
        if (seen.add(hit.row)) hit,
    ];
  }

  /// The rows holding at least one hit.
  Set<int> get hitRows => _hitRows ??= {for (final hit in hits) hit.row};

  /// Bumped each time the current hit is to be brought into view — an open, a
  /// step, a new query — and never otherwise. A listener that has to *move*
  /// something to show the hit (the editor's Products / Tasks / Expenses tabs)
  /// acts only when this changes, so a notification from a rows update can't
  /// drag the user back to a tab they just left.
  int get revealGeneration => _revealGeneration;

  /// How drawn line [row] is marked: the current hit's line, another line with
  /// a hit, or neither — always neither while the bar is closed.
  LineItemFindMark markFor(int row) {
    if (!_open || normalizedQuery.isEmpty || row < 0) {
      return LineItemFindMark.none;
    }
    if (active?.row == row) return LineItemFindMark.current;
    return hitRows.contains(row)
        ? LineItemFindMark.match
        : LineItemFindMark.none;
  }

  /// Register [context] as drawn line [row], for [_reveal]. See
  /// [_rowContexts].
  void attachRow(int row, BuildContext context) => _rowContexts[row] = context;

  /// Undo [attachRow] — only if [row] still names [context]: a reorder can
  /// hand the row to another marker before this one lets go of it.
  void detachRow(int row, BuildContext context) {
    if (identical(_rowContexts[row], context)) _rowContexts.remove(row);
  }

  /// Index of the current hit in [hits], or -1 when there is none.
  int get activeIndex {
    final n = hits.length;
    if (n == 0) return -1;
    return _current.clamp(0, n - 1);
  }

  FindHit? get active {
    final i = activeIndex;
    return i < 0 ? null : hits[i];
  }

  /// Show the bar (if it is not showing) and put the caret in it with the
  /// query selected, then bring the current hit back into view. Notifies even
  /// when the bar was already open: a surface that must move to show the hit
  /// (a tab the line is on) listens for [revealGeneration].
  void open() {
    _open = true;
    _revealGeneration++;
    notifyListeners();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      field.requestFocus();
      query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: query.text.length,
      );
      _reveal();
    });
  }

  /// Hide the bar. The query is kept, like a browser's, for the next [open] —
  /// but nothing is highlighted while the bar is closed.
  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  /// Step to the next hit, wrapping past the last.
  void next() => _step(1);

  /// Step to the previous hit, wrapping past the first.
  void previous() => _step(-1);

  /// Enter / Shift+Enter in the field, as a key event.
  void stepFromKey(int delta) {
    _keyStepAt = DateTime.now();
    _step(delta);
  }

  /// The field's text-input action (a soft keyboard's Search key): the next
  /// hit — unless the same press already stepped as a key event. On the web
  /// the engine reports every Return to the field as an action as well,
  /// whether or not the key was handled, so Enter moved two hits and
  /// Shift+Enter, stepping back and then forward, did not move at all.
  void submitted() {
    final at = _keyStepAt;
    _keyStepAt = null;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(milliseconds: 500)) {
      return;
    }
    next();
  }

  void _step(int delta) {
    final n = hits.length;
    if (n == 0) return;
    _current = (activeIndex + delta) % n;
    _revealGeneration++;
    notifyListeners();
    _scheduleReveal();
  }

  /// The table's drawn lines, as it draws them, and the order the layout it
  /// chose draws a line's slots in. Called from the table's build, so it
  /// never notifies there: a change is announced after the frame, for the
  /// bar's count — the table itself is already rebuilding.
  void updateRows(
    List<Map<LineFindSegment, String>> rows, {
    List<LineFindSegment> order = LineFindSegment.values,
  }) {
    if (listEquals(order, _order) &&
        const DeepCollectionEquality().equals(rows, _rows)) {
      return;
    }
    _rows = rows;
    _order = order;
    _hits = null;
    _hitRows = null;
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _onQueryChanged() {
    // The controller also notifies for a caret or selection move.
    final q = normalizedQuery;
    if (q == _lastQuery) return;
    _lastQuery = q;
    _hits = null;
    _hitRows = null;
    _current = 0;
    _revealGeneration++;
    notifyListeners();
    _scheduleReveal();
  }

  void _scheduleReveal() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// Scroll the line holding the current hit to the middle of the page — the
  /// middle, because the tab strip and this bar are pinned over the top of it.
  void _reveal() {
    if (_disposed || !_open) return;
    final row = active?.row;
    if (row == null) return;
    final context = _rowContexts[row] ?? rowKey(row).currentContext;
    if (context == null || !context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: InMotion.of(context)(InMotion.fast),
      curve: InMotion.move,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    query
      ..removeListener(_onQueryChanged)
      ..dispose();
    field.dispose();
    super.dispose();
  }
}

/// Publishes a record screen's [LineItemFindController] to its line items.
class LineItemFindScope extends InheritedWidget {
  const LineItemFindScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final LineItemFindController controller;

  /// Non-subscribing: the controller never changes for the screen's lifetime,
  /// and its readers listen to it directly.
  static LineItemFindController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LineItemFindScope>()?.controller;

  @override
  bool updateShouldNotify(LineItemFindScope oldWidget) =>
      !identical(oldWidget.controller, controller);
}

/// How a drawn line is marked while find is open — see
/// [LineItemFindController.markFor].
enum LineItemFindMark { none, match, current }

/// The draft index of each line a subset editor draws, in its order — for the
/// editor's Products / Tasks / Expenses tabs, each of which draws only its own
/// kind of line (`BillingDocItemsTabs`). The controller's rows are the whole
/// draft, so a tab's row `i` is draft line `draftIndexes[i]`. With no scope
/// the editor draws the whole draft and the two indexes are the same.
class LineItemFindRows extends InheritedWidget {
  const LineItemFindRows({
    super.key,
    required this.draftIndexes,
    required super.child,
  });

  final List<int> draftIndexes;

  /// The enclosing tab's draft indexes, or null when the editor draws the
  /// whole draft. Subscribing: the indexes move whenever a line of another
  /// kind is added or removed. Read it in a `build`, then map each row with
  /// [draftIndexFor].
  static List<int>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LineItemFindRows>()
      ?.draftIndexes;

  @override
  bool updateShouldNotify(LineItemFindRows oldWidget) =>
      !listEquals(oldWidget.draftIndexes, draftIndexes);
}

/// The draft index of drawn row [row], given [LineItemFindRows.of]: -1 for a
/// row past the subset (the desktop table's trailing blank row), which is
/// never marked.
int draftIndexFor(List<int>? draftIndexes, int row) {
  if (draftIndexes == null) return row;
  return row >= 0 && row < draftIndexes.length ? draftIndexes[row] : -1;
}

/// One editor row's find mark (`docs/find-in-line-items.md` § The editor
/// tints the matching lines). Rebuilds [builder] only when this row's mark
/// changes, so a step repaints two rows, not the table, and registers the row
/// with the controller so a step can scroll it into view.
///
/// Always mount it where a find exists — on every row, the blank ones
/// included (pass a [row] of -1) — never only on a row that matches: a
/// wrapper that came and went would remount the editable row under it and
/// drop the field the user is typing in.
class LineItemFindRowMarker extends StatefulWidget {
  const LineItemFindRowMarker({
    super.key,
    required this.controller,
    required this.row,
    required this.builder,
  });

  final LineItemFindController controller;

  /// The draft line this row draws, or -1 for one that is not a line yet.
  final int row;

  final Widget Function(BuildContext context, LineItemFindMark mark) builder;

  @override
  State<LineItemFindRowMarker> createState() => _LineItemFindRowMarkerState();
}

class _LineItemFindRowMarkerState extends State<LineItemFindRowMarker> {
  late LineItemFindMark _mark = widget.controller.markFor(widget.row);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFind);
    _attach();
  }

  @override
  void didUpdateWidget(LineItemFindRowMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onFind);
      widget.controller.addListener(_onFind);
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.row != widget.row) {
      if (oldWidget.row >= 0) {
        oldWidget.controller.detachRow(oldWidget.row, context);
      }
      _attach();
    }
    _mark = widget.controller.markFor(widget.row);
  }

  void _attach() {
    if (widget.row >= 0) widget.controller.attachRow(widget.row, context);
  }

  void _onFind() {
    final mark = widget.controller.markFor(widget.row);
    if (mark != _mark) setState(() => _mark = mark);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFind);
    if (widget.row >= 0) widget.controller.detachRow(widget.row, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _mark);
}

/// The fill a marked editor row is tinted with: amber for a line with a hit,
/// the accent for the current one. Opaque — blended over [base], the row's
/// own surface — so it can paint a card's background. Null when unmarked.
Color? lineItemFindRowFill(
  InTheme tokens,
  LineItemFindMark mark, {
  required Color base,
}) => switch (mark) {
  LineItemFindMark.none => null,
  // The amber at a fifth, not `warningSoft`: in the dark themes that is all
  // but the card's own colour (the same reason the record's marks use it).
  LineItemFindMark.match => Color.alphaBlend(
    tokens.warning.withValues(alpha: 0.2),
    base,
  ),
  LineItemFindMark.current => Color.alphaBlend(
    tokens.accent.withValues(alpha: 0.16),
    base,
  ),
};

/// The bar while find is open, nothing while it is closed — one shape either
/// way, so a host that mounts it beside its content never remounts that
/// content when the bar opens.
class LineItemFindBarSlot extends StatelessWidget {
  const LineItemFindBarSlot({super.key, required this.controller});

  final LineItemFindController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => controller.isOpen
        ? LineItemFindBar(controller: controller)
        : const SizedBox.shrink(),
  );
}

/// The find bar: a field, the "3 of 12" count, previous / next and close.
///
/// Enter and ↓ go to the next hit, Shift+Enter and ↑ to the previous, Esc
/// closes. On a soft keyboard the action key is Search and steps to the next.
class LineItemFindBar extends StatelessWidget {
  const LineItemFindBar({super.key, required this.controller});

  final LineItemFindController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final total = controller.hits.length;
        final hasQuery = controller.normalizedQuery.isNotEmpty;
        final compact = !Env.isTouchPrimary;
        final density = compact ? VisualDensity.compact : null;
        return Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          padding: EdgeInsetsDirectional.only(
            start: InSpacing.lg(context),
            end: InSpacing.xs,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: tokens.ink3),
              const SizedBox(width: 8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter): () =>
                        controller.stepFromKey(1),
                    const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                        controller.stepFromKey(1),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): () =>
                        controller.stepFromKey(-1),
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      shift: true,
                    ): () =>
                        controller.stepFromKey(-1),
                    const SingleActivator(LogicalKeyboardKey.arrowDown):
                        controller.next,
                    const SingleActivator(LogicalKeyboardKey.arrowUp):
                        controller.previous,
                    const SingleActivator(LogicalKeyboardKey.escape):
                        controller.close,
                  },
                  child: TextField(
                    controller: controller.query,
                    focusNode: controller.field,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TextStyle(fontSize: 13.5, color: tokens.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      // No chord in the hint: the hint bar and the `?` dialog draw it
                      // as caps, which plain text cannot.
                      hintText: context.tr('find_in_items'),
                      hintStyle: TextStyle(fontSize: 13.5, color: tokens.ink3),
                    ),
                    // A soft keyboard's Search key: step, and keep the field
                    // (the default would close the keyboard).
                    onSubmitted: (_) {
                      controller.submitted();
                      controller.field.requestFocus();
                    },
                  ),
                ),
              ),
              if (hasQuery) ...[
                const SizedBox(width: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    total == 0
                        ? context.tr('find_no_matches')
                        : context.tr('find_match_count', {
                            'current': '${controller.activeIndex + 1}',
                            'total': '$total',
                          }),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: total == 0 ? tokens.overdue : tokens.ink2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                tooltip: context.tr('previous'),
                visualDensity: density,
                iconSize: 20,
                onPressed: total == 0 ? null : controller.previous,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: context.tr('next'),
                visualDensity: density,
                iconSize: 20,
                onPressed: total == 0 ? null : controller.next,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                tooltip: context.tr('close'),
                visualDensity: density,
                iconSize: 18,
                onPressed: controller.close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [text] with every occurrence of [query] marked: a soft fill on each, and
/// the accent on [activeStart] — the current hit — when it is in this text.
/// Plain [Text] when nothing matches, so an unsearched table renders as it
/// always did. [ltr] lays a value (an amount, a quantity) out left to right in
/// every locale, as `LtrText` does.
Widget findHighlightedText(
  BuildContext context,
  String text, {
  required String query,
  required int? activeStart,
  required TextStyle style,
  int? maxLines,
  TextOverflow? overflow,
  TextAlign textAlign = TextAlign.start,
  bool ltr = false,
}) {
  final ranges = findOccurrences(text, query);
  if (ranges.isEmpty) {
    if (ltr) {
      return LtrText(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
  final ambient = Directionality.of(context);
  final flip = ltr && ambient == TextDirection.rtl;
  final tokens = context.inTheme;
  final spans = <TextSpan>[];
  var at = 0;
  for (final (start, end) in ranges) {
    if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
    final current = start == activeStart;
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: TextStyle(
          // The amber at a third, not `warningSoft`: that is a card tint, and
          // in the dark themes it is all but the card's own colour.
          backgroundColor: current
              ? tokens.accent
              : tokens.warning.withValues(alpha: 0.35),
          color: current ? tokens.onAccent : tokens.ink,
        ),
      ),
    );
    at = end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return Text.rich(
    TextSpan(style: style, children: spans),
    maxLines: maxLines,
    overflow: overflow,
    textDirection: flip ? TextDirection.ltr : null,
    textAlign: flip ? physicalTextAlign(textAlign, ambient) : textAlign,
  );
}
