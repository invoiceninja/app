import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/billing/line_item_custom_fields.dart';
import 'package:admin/domain/billing/line_item_find.dart';
import 'package:admin/domain/date_placeholders.dart';
import 'package:admin/domain/tasks/line_item_notes_display.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/billing_shared/line_item_find.dart';
import 'package:admin/ui/core/widgets/cell_copy_hover.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

// Column widths for the wide (table) layout. Item / Description flex; the
// numeric columns are fixed so they line up down the table.
const double _kQtyW = 60;
const double _kCostW = 96;
const double _kDiscW = 84;
const double _kTaxW = 104;
const double _kTotalW = 112;
const double _kGap = 10;

/// From this many drawn lines the table's header carries a Find button — the
/// way into find in line items without a keyboard. Under it the whole
/// document is on one screen; ⌘F / Ctrl+F still opens the bar there.
const int kLineItemFindButtonMinLines = 5;

/// Read-only line-items table for the billing-doc detail Overview (Invoice /
/// Quote / Credit). Mirrors the edit screen's column set
/// (`line_item_editor/line_item_table_desktop.dart`) minus all interactivity.
///
/// Column visibility is data-driven: the Tax column shows only when some line
/// carries a tax, the Discount column only when some line carries one — so a
/// plain invoice stays a clean Item · Qty · Unit cost · Total grid. When the
/// fixed columns would crush the Item/Description flex (narrow detail panel),
/// the rows reflow into stacked cards.
///
/// Line total renders `gross` (`cost × quantity`, pre-discount/pre-tax) to
/// match what the edit table shows per row; document-level discount/tax land
/// in the totals card below.
///
/// A line's custom values ("Color: Red") read under its description rather
/// than as columns: product and hourly lines share this table but label their
/// four values from different company fields (`product1..4` / `task1..4`), so
/// no single header could name a slot.
///
/// With [onTapItem], each line is one tap target into the edit screen with
/// that line's editor open — admin-portal's tap-a-line-to-edit, which the
/// rebuild had lost to Edit → Items → tap the line.
///
/// With [find], the table is where the record screen's find in line items
/// looks (`docs/find-in-line-items.md`): it hands the controller each drawn
/// line's texts as it draws them, highlights every hit while the bar is open,
/// and lifts the three-line cap on a line that has one, so no hit is hidden
/// behind an ellipsis.
class LineItemsReadonlyTable extends StatelessWidget {
  const LineItemsReadonlyTable({
    super.key,
    required this.items,
    this.formatter,
    this.currencyId,
    this.discountIsAmount = false,
    this.customFields,
    this.onTapItem,
    this.footer,
    this.find,
  });

  final List<LineItem> items;
  final Formatter? formatter;
  final String? currencyId;

  /// How to render any per-line discount (mirrors the document-level
  /// `isAmountDiscount`): currency amount vs. percentage.
  final bool discountIsAmount;

  /// The company's `custom_fields` definitions, naming each line's custom
  /// values. Null (company not loaded yet) shows none.
  final Map<String, String>? customFields;

  /// Edit the line at this index of [items] — blank lines counted, though
  /// they are not drawn. Null (a deleted record, a user who may not edit it)
  /// leaves the rows inert.
  final ValueChanged<int>? onTapItem;

  /// Drawn inside the card under the last line, on the header's surface —
  /// the document's totals. The lines and what they add up to are one table
  /// on the page, and as two cards the sum sat a gap away from its column.
  final Widget? footer;

  /// The record screen's find in line items, or null where there is none.
  final LineItemFindController? find;

  @override
  Widget build(BuildContext context) {
    final find = this.find;
    if (find == null) return _build(context, null);
    return ListenableBuilder(
      listenable: find,
      builder: (context, _) => _build(context, find),
    );
  }

  Widget _build(BuildContext context, LineItemFindController? find) {
    final tokens = context.inTheme;
    // Each drawn line keeps its index in [items], which is what [onTapItem]
    // hands back: the edit view model's draft holds the blank lines too.
    final indexes = [
      for (var i = 0; i < items.length; i++)
        if (!items[i].isBlank) i,
    ];
    final rows = [for (final i in indexes) items[i]];
    final texts = [for (final it in rows) _findTexts(context, it)];
    final query = (find != null && find.isOpen) ? find.normalizedQuery : '';
    final active = query.isEmpty ? null : find?.active;
    _RowFind rowFind(int i) => _RowFind(
      query: query,
      texts: texts[i],
      active: active?.row == i ? active : null,
    );
    // Every line carries its key, so the controller can scroll to the one
    // holding the current hit. Always, not only on that line: moving one key
    // between lines remounted both on every step.
    Widget keyed(int i, Widget row) =>
        find == null ? row : KeyedSubtree(key: find.rowKey(i), child: row);
    final findButton =
        find != null && rows.length >= kLineItemFindButtonMinLines
        ? _findButton(context, find)
        : null;
    final footer = this.footer;
    final foot = footer == null
        ? null
        : Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            child: footer,
          );
    if (rows.isEmpty) return _empty(context, tokens, foot);

    final showTax = rows.any(_hasTax);
    final showDiscount = rows.any((it) => it.discount != Decimal.zero);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r3),
        color: tokens.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fixed =
              _kQtyW +
              _kCostW +
              _kTotalW +
              (showDiscount ? _kDiscW : 0) +
              (showTax ? _kTaxW : 0);
          // Keep ~200px for the Item column (the name over its description);
          // below that the table is unreadable, so stack instead.
          final stacked = constraints.maxWidth - fixed < 200;
          // Counted in the order this layout draws a line's slots.
          find?.updateRows(
            texts,
            order: stacked ? kStackedFindOrder : LineFindSegment.values,
          );
          if (stacked) {
            return Column(
              children: [
                // No column heads to hang it on here, so the button gets a
                // slim head of its own, naming the list.
                if (findButton != null)
                  _headBar(
                    context,
                    findButton: true,
                    child: Row(
                      children: [
                        _flexHead(context.tr('items'), tokens),
                        findButton,
                      ],
                    ),
                  ),
                for (var i = 0; i < rows.length; i++)
                  keyed(
                    i,
                    _tappable(
                      indexes[i],
                      _stackedRow(
                        context,
                        rows[i],
                        rowFind(i),
                        isLast: i == rows.length - 1,
                        showTax: showTax,
                        showDiscount: showDiscount,
                      ),
                    ),
                  ),
                ?foot,
              ],
            );
          }
          return Column(
            children: [
              _headerRow(
                context,
                showTax: showTax,
                showDiscount: showDiscount,
                findButton: findButton,
              ),
              for (var i = 0; i < rows.length; i++)
                keyed(
                  i,
                  _tappable(
                    indexes[i],
                    _dataRow(
                      context,
                      rows[i],
                      rowFind(i),
                      isLast: i == rows.length - 1,
                      showTax: showTax,
                      showDiscount: showDiscount,
                    ),
                  ),
                ),
              ?foot,
            ],
          );
        },
      ),
    );
  }

  /// [row] as one tap target when the rows are editable. The ink goes on a
  /// local transparent `Material`, above the table's own surface colour —
  /// splashed onto a `Material` further up it would paint under that colour
  /// and never show.
  Widget _tappable(int index, Widget row) {
    final onTap = onTapItem;
    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        child: InkWell(onTap: () => onTap(index), child: row),
      ),
    );
  }

  // ── Wide layout ────────────────────────────────────────────────────────

  Widget _headerRow(
    BuildContext context, {
    required bool showTax,
    required bool showDiscount,
    Widget? findButton,
  }) {
    final tokens = context.inTheme;
    return _headBar(
      context,
      findButton: findButton != null,
      child: Row(
        children: [
          if (findButton == null)
            _flexHead(context.tr('item'), tokens)
          else
            // Beside the Item head it names, not at the end of the column,
            // where it read as a control of the Quantity column beside it.
            Expanded(
              child: Row(
                children: [
                  Flexible(child: _headText(context.tr('item'), tokens)),
                  const SizedBox(width: 4),
                  findButton,
                ],
              ),
            ),
          _numHead(_kQtyW, context.tr('quantity'), tokens),
          _numHead(_kCostW, context.tr('unit_cost'), tokens),
          if (showDiscount) _numHead(_kDiscW, context.tr('discount'), tokens),
          if (showTax) _numHead(_kTaxW, context.tr('tax'), tokens),
          _numHead(_kTotalW, context.tr('line_total'), tokens),
        ],
      ),
    );
  }

  /// The header band. A Find button is taller than a line of small capitals,
  /// so with one the band gives back the padding the button brings.
  Widget _headBar(
    BuildContext context, {
    required bool findButton,
    required Widget child,
  }) {
    final tokens = context.inTheme;
    final v = findButton ? (Env.isTouchPrimary ? 0.0 : 4.0) : 10.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: v,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: child,
    );
  }

  /// Opens find in line items. 28 px under a pointer; the touch floor on a
  /// touch platform, with Material's own 48 px layout inflation switched off.
  Widget _findButton(BuildContext context, LineItemFindController find) {
    final size = Env.isTouchPrimary ? InSizes.touchTarget : 28.0;
    return IconButton(
      tooltip: context.tr('find_in_items'),
      onPressed: find.open,
      iconSize: 16,
      padding: EdgeInsets.zero,
      // The desktop theme's compact density would take 8 off these.
      visualDensity: VisualDensity.standard,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      color: context.inTheme.ink2,
      icon: const Icon(Icons.search),
    );
  }

  Widget _dataRow(
    BuildContext context,
    LineItem it,
    _RowFind f, {
    required bool isLast,
    required bool showTax,
    required bool showDiscount,
  }) {
    final tokens = context.inTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: 10,
      ),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _itemCell(context, it, f, tokens),
          _numCell(context, _kQtyW, f, LineFindSegment.quantity, tokens),
          _numCell(context, _kCostW, f, LineFindSegment.cost, tokens),
          if (showDiscount)
            _numCell(context, _kDiscW, f, LineFindSegment.discount, tokens),
          if (showTax)
            _numCell(context, _kTaxW, f, LineFindSegment.tax, tokens),
          _numCell(
            context,
            _kTotalW,
            f,
            LineFindSegment.total,
            tokens,
            strong: true,
          ),
        ],
      ),
    );
  }

  // ── Narrow (stacked) layout ──────────────────────────────────────────────

  Widget _stackedRow(
    BuildContext context,
    LineItem it,
    _RowFind f, {
    required bool isLast,
    required bool showTax,
    required bool showDiscount,
  }) {
    final tokens = context.inTheme;
    final notes = f.text(LineFindSegment.notes);
    final custom = f.text(LineFindSegment.custom);
    final metaStyle = TextStyle(
      fontSize: 11.5,
      color: tokens.ink3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Each value its own span, so a hit in one is marked where it is.
    Widget metaValue(LineFindSegment s) =>
        f.highlight(context, s, style: metaStyle, ltr: true);
    const sep = SizedBox(width: 16);
    final meta = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        metaValue(LineFindSegment.quantity),
        Text(' × ', style: metaStyle),
        metaValue(LineFindSegment.cost),
        if (showDiscount && it.discount != Decimal.zero) ...[
          sep,
          Text('${context.tr('discount')}: ', style: metaStyle),
          metaValue(LineFindSegment.discount),
        ],
        if (showTax && _hasTax(it)) ...[
          sep,
          Text('${context.tr('tax')}: ', style: metaStyle),
          metaValue(LineFindSegment.tax),
        ],
      ],
    );
    final hasKey = it.productKey.isNotEmpty;
    // With no item name, the title is the first line of the description —
    // and the description is not repeated under it, so a hit in a later line
    // of it would be invisible: while one is there the whole description is
    // the title.
    final titleIsNotes = !hasKey && notes.isNotEmpty;
    final titleStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: tokens.ink,
    );
    final Widget titleText;
    if (hasKey) {
      titleText = f.highlight(context, LineFindSegment.name, style: titleStyle);
    } else if (titleIsNotes && f.hasHits) {
      titleText = f.highlight(
        context,
        LineFindSegment.notes,
        style: titleStyle,
      );
    } else {
      titleText = Text(
        // One line only for the title — the rest of the note follows in the
        // subtitle below when there's a product key to head the row.
        titleIsNotes ? notes.split('\n').first : '—',
        style: titleStyle,
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: 12,
      ),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // Only an item name copies: a title borrowed from the first
                // line of the description is not the item's name.
                child: _copyable(it.productKey, titleText),
              ),
              const SizedBox(width: 12),
              f.highlight(
                context,
                LineFindSegment.total,
                ltr: true,
                style: moneyTextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.ink,
                ),
              ),
            ],
          ),
          if (hasKey && notes.isNotEmpty) ...[
            const SizedBox(height: 2),
            f.highlight(
              context,
              LineFindSegment.notes,
              style: TextStyle(fontSize: 12, color: tokens.ink2),
            ),
          ],
          if (custom.isNotEmpty) ...[
            const SizedBox(height: 2),
            f.highlight(
              context,
              LineFindSegment.custom,
              style: _customStyle(tokens),
            ),
          ],
          const SizedBox(height: 4),
          meta,
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, InTheme tokens, Widget? foot) =>
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(InRadii.r3),
          color: tokens.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.tr('no_records_found'),
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.ink3, fontSize: 13),
              ),
            ),
            ?foot,
          ],
        ),
      );

  // ── Cell helpers ─────────────────────────────────────────────────────────

  /// The wide layout's Item column: the name, then under it the description
  /// and the line's custom values. One column rather than two — side by side
  /// the description took four sevenths of the row to say "Molestias.", and
  /// the name it describes was a column away. Neither is capped to fewer
  /// lines than the notes always had: this is the one place a value too long
  /// for the edit table can be read.
  Widget _itemCell(
    BuildContext context,
    LineItem it,
    _RowFind f,
    InTheme tokens,
  ) {
    final notes = f.text(LineFindSegment.notes);
    final custom = f.text(LineFindSegment.custom);
    final hasKey = it.productKey.isNotEmpty;
    // A hit past the third line must not sit behind the ellipsis.
    final cap = f.hasHits ? null : 3;
    return Expanded(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: _kGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // A line with no item name leads with its description in the
            // name's ink rather than a dash over it.
            if (hasKey || notes.isEmpty)
              _copyable(
                it.productKey,
                hasKey
                    ? f.highlight(
                        context,
                        LineFindSegment.name,
                        maxLines: cap,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                        ),
                      )
                    : Text(
                        '—',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                        ),
                      ),
              ),
            if (notes.isNotEmpty) ...[
              if (hasKey) const SizedBox(height: 2),
              f.highlight(
                context,
                LineFindSegment.notes,
                maxLines: cap,
                style: TextStyle(
                  fontSize: 13,
                  color: hasKey ? tokens.ink2 : tokens.ink,
                ),
              ),
            ],
            if (custom.isNotEmpty) ...[
              const SizedBox(height: 2),
              f.highlight(
                context,
                LineFindSegment.custom,
                style: _customStyle(tokens),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// `Label: value` for each custom value [it] holds, labelled from the
  /// company's `task1..4` for an hourly line and `product1..4` otherwise.
  String _customSummary(BuildContext context, LineItem it) =>
      lineItemCustomValueRows(
        it,
        lineItemCustomFields(customFields, task: lineItemUsesTaskFields(it)),
        yes: context.tr('yes'),
        no: context.tr('no'),
        formatter: formatter,
        // The dates the line will print, like its description (`_notesText`).
        expandDateKeywords: true,
      ).map((r) => '${r.label}: ${r.value}').join('   ·   ');

  TextStyle _customStyle(InTheme tokens) =>
      TextStyle(fontSize: 11.5, color: tokens.ink3);

  /// Column heads are small capitals in `ink2`: at 11 px the muted `ink3`
  /// is under the contrast floor on the header's surface.
  TextStyle _headStyle(InTheme tokens) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: tokens.ink2,
    letterSpacing: 0.5,
  );

  Widget _flexHead(String text, InTheme tokens) => Expanded(
    child: Padding(
      padding: const EdgeInsetsDirectional.only(end: _kGap),
      child: _headText(text, tokens),
    ),
  );

  Widget _headText(String text, InTheme tokens) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: _headStyle(tokens),
  );

  Widget _numHead(double w, String text, InTheme tokens) => SizedBox(
    width: w,
    child: Text(
      text.toUpperCase(),
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _headStyle(tokens),
    ),
  );

  /// [child] with the item name's copy affordance: the table-cell hover icon
  /// with a mouse (its click copies instead of opening the line), a
  /// long-press on touch — the row's tap is taken by [onTapItem], and a
  /// document's lines have no multi-select to spend a long-press on. An empty
  /// [value] is [child] unchanged.
  Widget _copyable(String value, Widget child) => CellCopyHover(
    value: value,
    touchLongPressCopies: true,
    // The cell's full width, so the icon keeps one column down the table
    // rather than chasing the end of each name.
    child: SizedBox(width: double.infinity, child: child),
  );

  /// A numeric column's cell: [segment]'s text, or a dash where the line
  /// has none (no discount, no tax).
  Widget _numCell(
    BuildContext context,
    double w,
    _RowFind f,
    LineFindSegment segment,
    InTheme tokens, {
    bool strong = false,
  }) {
    final style = moneyTextStyle(
      fontSize: 13,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
      color: tokens.ink,
    );
    return SizedBox(
      width: w,
      child: f.text(segment).isEmpty
          ? LtrText('—', textAlign: TextAlign.end, style: style)
          : f.highlight(
              context,
              segment,
              ltr: true,
              textAlign: TextAlign.end,
              // Like the Item cell: a hit must not sit behind an ellipsis.
              // No ellipsis without a cap either: with no `maxLines` one
              // stops the text at its first line.
              maxLines: f.hasHits ? null : 2,
              overflow: f.hasHits ? null : TextOverflow.ellipsis,
              style: style,
            ),
    );
  }

  /// Each drawn text of [it], by the slot find counts it in — what both
  /// layouts render, so a hit is the same hit whichever one is showing. A
  /// slot the line does not draw is empty.
  Map<LineFindSegment, String> _findTexts(BuildContext context, LineItem it) =>
      {
        LineFindSegment.name: it.productKey,
        LineFindSegment.notes: _notesText(it),
        LineFindSegment.custom: _customSummary(context, it),
        LineFindSegment.quantity: _qty(it.quantity),
        LineFindSegment.cost: _money(it.cost),
        LineFindSegment.discount: it.discount == Decimal.zero
            ? ''
            : _discountLabel(it),
        LineFindSegment.tax: _hasTax(it) ? _taxLabel(it) : '',
        LineFindSegment.total: _money(it.gross),
      };

  // ── Formatting ───────────────────────────────────────────────────────────

  bool _hasTax(LineItem it) =>
      it.taxName1.trim().isNotEmpty ||
      it.taxName2.trim().isNotEmpty ||
      it.taxName3.trim().isNotEmpty ||
      it.taxRate1 != Decimal.zero ||
      it.taxRate2 != Decimal.zero ||
      it.taxRate3 != Decimal.zero;

  String _money(Decimal v) =>
      formatter?.money(v, clientCurrencyId: currencyId) ?? v.toString();

  String _qty(Decimal v) => formatter?.decimal(v.toDouble()) ?? v.toString();

  /// Strip the PDF's presentational markup, then render any reserved date
  /// keyword as the date it becomes (invoiceninja/flutter#93).
  ///
  /// Both passes are needed and in this order: `lineItemNotesPlainText` drops
  /// the `<div class="project-header">` wrapper a task-generated note opens
  /// with, and expanding afterwards means no `/` from a closing tag can be
  /// mistaken for an arithmetic operator — the bug upstream works around with
  /// a `str_replace("</", "")` (`Helpers.php:272`).
  ///
  /// Worth doing even though the server expands and *persists* line-item notes
  /// when a document is created (`BaseRepository.php:217-227`): that guard runs
  /// only for a new model and never for a recurring invoice, so a keyword typed
  /// into an existing document stays raw in the database and is expanded only
  /// when the PDF is built.
  String _notesText(LineItem it) => expandDatePlaceholders(
    lineItemNotesPlainText(it.notes),
    formatter: formatter,
    // The server counts its caps on the notes as stored.
    measured: it.notes,
  );

  String _discountLabel(LineItem it) =>
      discountIsAmount ? _money(it.discount) : '${_qty(it.discount)}%';

  String _taxLabel(LineItem it) {
    final parts = <String>[];
    void add(String name, Decimal rate) {
      final n = name.trim();
      final hasRate = rate != Decimal.zero;
      if (n.isEmpty && !hasRate) return;
      final rateStr = hasRate ? '${_qty(rate)}%' : '';
      parts.add(
        [if (n.isNotEmpty) n, if (rateStr.isNotEmpty) rateStr].join(' '),
      );
    }

    add(it.taxName1, it.taxRate1);
    add(it.taxName2, it.taxRate2);
    add(it.taxName3, it.taxRate3);
    return parts.join(', ');
  }
}

/// One drawn line's find state: its texts, the query (blank while the bar is
/// closed) and, when the current hit is on this line, that hit.
class _RowFind {
  _RowFind({required this.query, required this.texts, required this.active})
    : hasHits =
          query.isNotEmpty &&
          texts.values.any((t) => findOccurrences(t, query).isNotEmpty);

  final String query;
  final Map<LineFindSegment, String> texts;
  final FindHit? active;

  /// Whether any text of this line matches — which lifts its line caps.
  final bool hasHits;

  String text(LineFindSegment segment) => texts[segment] ?? '';

  /// [segment]'s text, its hits marked.
  Widget highlight(
    BuildContext context,
    LineFindSegment segment, {
    required TextStyle style,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign textAlign = TextAlign.start,
    bool ltr = false,
  }) => findHighlightedText(
    context,
    text(segment),
    query: query,
    activeStart: active?.segment == segment ? active!.start : null,
    style: style,
    maxLines: maxLines,
    overflow: maxLines == null ? overflow : (overflow ?? TextOverflow.ellipsis),
    textAlign: textAlign,
    ltr: ltr,
  );
}
