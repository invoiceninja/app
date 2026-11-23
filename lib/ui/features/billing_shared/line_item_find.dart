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
/// Owned by `BillingDocRecordBody`, which all five billing documents share,
/// and published through [LineItemFindScope]. Two widgets read it: the bar
/// ([LineItemFindBar], pinned under the tab strip so it stays on screen while
/// the page scrolls from hit to hit) and the read-only line-items table, which
/// highlights. The table is also where the searched texts come from — it
/// hands each drawn line's texts in through [updateRows], exactly as it draws
/// them, so the bar's count and the table's highlights cannot disagree.
class LineItemFindController extends ChangeNotifier {
  LineItemFindController() {
    query.addListener(_onQueryChanged);
  }

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
  bool _notifyScheduled = false;

  bool get isOpen => _open;

  /// The query as it is matched — blank is "no search".
  String get normalizedQuery => normalizeFindQuery(query.text);

  /// Every hit, in reading order. Recomputed only when the query or the rows
  /// change.
  List<FindHit> get hits =>
      _hits ??= findHits(_rows, query.text, order: _order);

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
  /// query selected, then bring the current hit back into view.
  void open() {
    if (!_open) {
      _open = true;
      notifyListeners();
    }
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
    _current = 0;
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
    final context = rowKey(row).currentContext;
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
