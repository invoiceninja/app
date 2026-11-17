import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/formatter_scope.dart';
import 'package:admin/utils/bidi.dart';

/// The share of the line the party's name is always left — see
/// [BillingRowSubtitle.build].
const double _kMinPartyShare = 0.4;

/// The second line of a narrow billing-document row: the party, then the
/// document's deadline — "Acme Ltd · Due 3 Nov 2026".
///
/// The number keeps the first line. The deadline is the one date a phone user
/// scans an invoice list for, and the wide table's Due Date column is not on a
/// phone at all, so without it the narrow row could say *that* an invoice is
/// past due (its pill) but never *when* it falls due.
///
/// [late] draws the date in the `overdue` ink — the caller passes the same
/// predicate the status pill and the wide table's date cell use
/// (`Invoice.isPastDueOn`, `Quote.isExpired`), so the three never disagree.
/// [lateText] is what a screen reader hears after the date ("12 days late");
/// the line itself never says how late — relative text is the pill's job.
///
/// No date, no deadline: the line is the party alone, with no trailing
/// separator. And while the company `Formatter` is still resolving the date is
/// left out rather than drawn in some other format for a frame.
///
/// The date is never cut while the name still has [_kMinPartyShare] of the
/// line; the name is what ellipsizes first.
class BillingRowSubtitle extends StatelessWidget {
  const BillingRowSubtitle({
    super.key,
    required this.party,
    required this.date,
    required this.dateLabelKey,
    this.late = false,
    this.lateText,
  });

  /// The party's name label, already styled — `ClientNameLabel` /
  /// `VendorNameLabel` — or null when the document has no party.
  final Widget? party;

  /// The deadline; null draws no date at all.
  final Date? date;

  /// A key carrying a `:date` placeholder — `due_on_date_label` ("Due :date")
  /// or `valid_until_date_label` ("Valid until :date").
  final String dateLabelKey;

  /// The deadline has passed — see the class doc.
  final bool late;

  /// Read after the date when [late]; null reads the date alone.
  final String? lateText;

  /// The line's text style; the party label is styled by its own caller to
  /// match, `ink2` (not `ink3`, ~3.9:1 at 12 px) so it stays above AA.
  static TextStyle styleFor(InTheme tokens, {bool late = false}) => TextStyle(
    color: late ? tokens.overdue : tokens.ink2,
    fontSize: 12,
    fontWeight: late ? FontWeight.w500 : FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final d = date;
    final formatted = d == null
        ? null
        : FormatterScope.maybeOf(context)?.date(d.toIso());
    final dateText = (formatted == null || formatted.isEmpty)
        ? null
        : context.tr(dateLabelKey, {
            'date': Directionality.of(context) == TextDirection.rtl
                ? ltrIsolate(formatted)
                : formatted,
          });
    final party = this.party;
    if (dateText == null) return party ?? const SizedBox.shrink();

    final spoken = late && lateText != null ? '$dateText, $lateText' : dateText;
    final dateWidget = Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(
        dateText,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: styleFor(tokens, late: late),
      ),
    );
    if (party == null) return dateWidget;
    final separator = ExcludeSemantics(
      child: Text(' · ', style: styleFor(tokens).copyWith(color: tokens.ink3)),
    );
    return _PartyDateLine(
      textDirection: Directionality.of(context),
      children: [party, separator, dateWidget],
    );
  }
}

/// Lays out `[party, separator, date]` on one line: both at their natural
/// widths when they fit; otherwise the name ellipsizes first, down to
/// [_kMinPartyShare] of the line (or its own width, if shorter), and only then
/// does the date give way.
///
/// A `Row` cannot say this: a `Flexible` name beside a rigid date hands the
/// date everything — "Bayer… · Valid until Nov 15, 2026" on a phone — and two
/// `Flexible`s split the line by ratio, cutting a long date beside a short name
/// while the rest of the line sits empty. The rule needs the name's natural
/// width, which only a render object can ask for.
class _PartyDateLine extends MultiChildRenderObjectWidget {
  const _PartyDateLine({required this.textDirection, required super.children})
    : assert(children.length == 3);

  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPartyDateLine(textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPartyDateLine renderObject,
  ) {
    renderObject.textDirection = textDirection;
  }
}

class _LineParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPartyDateLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LineParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LineParentData> {
  _RenderPartyDateLine(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LineParentData) {
      child.parentData = _LineParentData();
    }
  }

  List<RenderBox> get _kids => getChildrenAsList();

  /// The widths the party and the date get on a line [maxWidth] wide, after
  /// the separator's [sepWidth].
  (double, double) _widths(double maxWidth, double sepWidth) {
    final [party, _, date] = _kids;
    final partyNatural = party.getMaxIntrinsicWidth(double.infinity);
    final dateNatural = date.getMaxIntrinsicWidth(double.infinity);
    final available = (maxWidth - sepWidth).clamp(0.0, double.infinity);
    if (partyNatural + dateNatural <= available) {
      return (partyNatural, dateNatural);
    }
    final partyFloor = partyNatural.clamp(0.0, maxWidth * _kMinPartyShare);
    final dateWidth = dateNatural.clamp(
      0.0,
      (available - partyFloor).clamp(0.0, double.infinity),
    );
    return (available - dateWidth, dateWidth);
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final [party, sep, date] = _kids;
    Size measure(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    final sepSize = measure(sep, const BoxConstraints());
    final (partyMax, dateMax) = _widths(constraints.maxWidth, sepSize.width);
    final partySize = measure(party, BoxConstraints(maxWidth: partyMax));
    final dateSize = measure(date, BoxConstraints(maxWidth: dateMax));
    final height = [
      partySize.height,
      sepSize.height,
      dateSize.height,
    ].reduce((a, b) => a > b ? a : b);
    final width = partySize.width + sepSize.width + dateSize.width;
    if (!dry) {
      var x = 0.0;
      final ltr = _textDirection == TextDirection.ltr;
      for (final (child, size) in [
        (party, partySize),
        (sep, sepSize),
        (date, dateSize),
      ]) {
        final dx = ltr ? x : width - x - size.width;
        (child.parentData! as _LineParentData).offset = Offset(
          dx,
          (height - size.height) / 2,
        );
        x += size.width;
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _kids.fold(0.0, (sum, child) => sum + child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) => _kids.fold(0.0, (h, child) {
    final c = child.getMinIntrinsicHeight(width);
    return c > h ? c : h;
  });

  @override
  double computeMaxIntrinsicHeight(double width) => _kids.fold(0.0, (h, child) {
    final c = child.getMaxIntrinsicHeight(width);
    return c > h ? c : h;
  });

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
