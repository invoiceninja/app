import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/widgets/centered_form_column.dart';

/// Everything a record screen shows above its tabs, in the one order every
/// entity uses:
///
///   identity → quick actions → standing → comments → profile
///
/// **The profile is always shown.** It used to sit behind a remembered
/// disclosure row, closed by default, with a one-contact summary above it; in
/// use that read as hiding the address behind a click, and the row and the
/// summary are gone.
///
/// **One order at every width.** At [Breakpoints.entityFormMultiColumn] and
/// up, identity and quick actions sit beside the standing card. A hub record
/// (a client, a vendor, a project) on a page of `kRecordRailMinWidth` or more draws
/// this column in two parts instead ([part]): identity and actions above the
/// tabs, the rest in a rail beside them. A rail was once dropped on paper for
/// leaving the embedded tables 640-800 px wide and for resetting the tabs as
/// the pane changes width; the threshold and a keyed tab body answer both
/// (docs/detail-screen-layout.md § The rail).
///
/// Slots are plain widgets and this takes no `Services`, so a host that cannot
/// give up the page — a billing document, whose scroll view shares a row with
/// the PDF pane — can drop the column into its own scroll view.
class EntityRecordColumn extends StatelessWidget {
  const EntityRecordColumn({
    super.key,
    required this.header,
    this.quickActions,
    this.standing,
    this.comments,
    this.profile,
    this.timestamps,
    this.part = RecordColumnPart.all,
  });

  /// Which of the slots this instance draws: all of them (the one layout
  /// every width used to get), or one side of the wide rail layout
  /// (`EntityRecordPage.rail`), where identity and actions lead the lists and
  /// the rest sits in a column beside them. Same slots, same order.
  final RecordColumnPart part;

  final Widget header;

  /// **Owns its trailing gap.** The strip can empty itself after it is built
  /// (a phone-action preference flips while the screen sits behind
  /// `/settings`), so only it knows whether there is a gap to pay.
  final Widget? quickActions;

  final Widget? standing;

  /// **Owns its trailing gap** — `EntityCommentsCard` is always mounted and
  /// hides itself, which is the documented exception to "gate the entry".
  final Widget? comments;

  /// The record's reference fields — contacts, details, address, notes — as
  /// the host lays them out. Last above the tabs.
  final Widget? profile;

  /// Created / updated — a `RecordTimestampsLine`, which draws only on a
  /// phone (where the Details card leaves those rows out) and **owns its
  /// trailing gap**. On a phone the column has the profile pay the gap above
  /// it, only when the profile draws. Last above the tabs.
  final Widget? timestamps;

  @override
  Widget build(BuildContext context) {
    final gapSize = InSpacing.lg(context);
    final gap = SizedBox(height: gapSize);
    final profile = this.profile;
    final timestamps = this.timestamps;
    final below = <Widget>[
      ?comments,
      // With the dates line under it, the profile pays the gap between them —
      // but only when it draws something. The line cannot tell a card above
      // it from the standing card's own trailing gap, and a fixed gap of its
      // own sat 20 px under one and 8 px under the other.
      if (profile != null)
        timestamps is RecordTimestampsLine && timestamps.drawsIn(context)
            ? _GapAfterIfPainted(gap: gapSize, child: profile)
            : profile,
      ?timestamps,
    ];
    if (part == RecordColumnPart.lead) {
      return RecordColumnScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The strip owns its own trailing gap; with none, the header pays
            // the gap down to the tabs.
            header,
            gap,
            ?quickActions,
          ],
        ),
      );
    }
    if (part == RecordColumnPart.rail) {
      final standing = this.standing;
      return RecordColumnScope(
        part: RecordColumnPart.rail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (standing != null) ...[standing, gap],
            ...below,
          ],
        ),
      );
    }
    return RecordColumnScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= Breakpoints.entityFormMultiColumn;
          final standing = this.standing;
          if (!wide) {
            // Capped and centred like every single-column entity form, so on a
            // tablet-width pane the header, cards and comments share one edge.
            return CenteredFormColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  gap,
                  ?quickActions,
                  if (standing != null) ...[standing, gap],
                  ...below,
                ],
              ),
            );
          }
          // `spaceBetween`: at its own height this is just the two stacked. When
          // the band stretches it — the standing card beside it is the taller
          // one — the header stays at the top and the tiles drop to the bottom
          // line, level with the foot of that card.
          final lead = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: gapSize),
                child: header,
              ),
              ?quickActions,
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (standing == null)
                lead
              else
                _EvenBand(
                  gap: gapSize,
                  // Each side carries its own trailing gap — the lead ends in
                  // the header's or the quick actions' own, the card in this
                  // padding — so the band ends exactly one gap below both.
                  children: [
                    lead,
                    Padding(
                      padding: EdgeInsets.only(bottom: gapSize),
                      child: standing,
                    ),
                  ],
                ),
              ...below,
            ],
          );
        },
      ),
    );
  }
}

/// The slots an [EntityRecordColumn] draws.
enum RecordColumnPart {
  /// Everything, above the tabs.
  all,

  /// Identity and quick actions: what stays above the tabs beside a rail.
  lead,

  /// Standing, comments, profile and dates, stacked: the rail itself.
  rail,
}

/// Marks everything above a record's tabs, so a shared widget can tell it is
/// on a record screen rather than on the dashboard — the Compact density
/// trims of `DashboardCardShell` apply here (the profile cards and the
/// Comments card alike, deliberately: they sit in one stack) and not there
/// (`docs/list-density.md` § What Compact changes).
class RecordColumnScope extends InheritedWidget {
  const RecordColumnScope({
    super.key,
    this.part = RecordColumnPart.all,
    required super.child,
  });

  /// Which of the column's layouts this is — [RecordColumnPart.rail] for the
  /// fixed `kRecordRailWidth` column beside a hub record's tabs.
  final RecordColumnPart part;

  /// Whether [context] is inside an [EntityRecordColumn]. Does not subscribe:
  /// the answer cannot change for a mounted widget.
  static bool contains(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RecordColumnScope>() != null;

  /// Whether [context] is inside the rail, whose width is known in advance
  /// (`kRecordRailWidth`) — so a card there can decide what fits without a
  /// `LayoutBuilder`, which a card levelled with `IntrinsicHeight` elsewhere
  /// may not contain. Does not subscribe: crossing the rail threshold mounts
  /// the cards under a different column.
  static bool isRail(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RecordColumnScope>()?.part ==
      RecordColumnPart.rail;

  @override
  bool updateShouldNotify(RecordColumnScope oldWidget) =>
      oldWidget.part != part;
}

/// [child], then [gap] below it — unless [child] laid itself out at zero
/// height (a profile whose every card hid itself), when it costs nothing.
///
/// A render object because whether the child draws is only known after its
/// layout: each profile card decides that itself.
class _GapAfterIfPainted extends SingleChildRenderObjectWidget {
  const _GapAfterIfPainted({required this.gap, required super.child});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGapAfterIfPainted(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGapAfterIfPainted renderObject,
  ) => renderObject.gap = gap;
}

class _RenderGapAfterIfPainted extends RenderProxyBox {
  _RenderGapAfterIfPainted(this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // Width as given (a stretched column); only the height is the child's.
    child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    final h = child.size.height;
    size = constraints.constrain(Size(child.size.width, h > 0 ? h + _gap : 0));
  }

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason: 'Whether the gap is paid depends on the child\'s real layout.',
      ),
    );
    return Size.zero;
  }
}

/// How the wide band splits its width: identity and actions, then standing.
const int _kLeadFlex = 11;
const int _kStandingFlex = 9;

/// Two boxes side by side that **end on the same line**: each is laid out at
/// its own height, and the shorter is then laid out again at the taller one's.
///
/// The band used to be a `Row` aligned to the top, so whichever side was
/// shorter simply stopped short — the Balance card ended 26 px above the
/// tiles beside it on a client with no credit, and the tiles ended above the
/// card on one with a past-due line and a credit balance. Neither side is
/// reliably the taller.
///
/// A render object, because the two ordinary answers do not work here.
/// `IntrinsicHeight` + `CrossAxisAlignment.stretch` needs intrinsic heights,
/// and both sides contain a `LayoutBuilder` (the tiles count themselves
/// against their own width; the standing card's figures branch on theirs),
/// which has none. And a `Stack` with one side `Positioned.fill` only ever
/// stretches that side.
class _EvenBand extends MultiChildRenderObjectWidget {
  const _EvenBand({required this.gap, required super.children})
    : assert(children.length == 2);

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEvenBand(gap: gap, textDirection: Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderEvenBand renderObject) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class _EvenBandParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEvenBand extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EvenBandParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EvenBandParentData> {
  _RenderEvenBand({required double gap, required TextDirection textDirection})
    : _gap = gap,
      _textDirection = textDirection;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EvenBandParentData) {
      child.parentData = _EvenBandParentData();
    }
  }

  ({double lead, double standing}) _widths(double width) {
    final usable = math.max(0.0, width - gap);
    final lead = usable * _kLeadFlex / (_kLeadFlex + _kStandingFlex);
    return (lead: lead, standing: usable - lead);
  }

  @override
  void performLayout() {
    final lead = firstChild!;
    final standing = childAfter(lead)!;
    final width = constraints.maxWidth;
    final widths = _widths(width);

    // Once at its own height…
    lead.layout(
      BoxConstraints.tightFor(width: widths.lead),
      parentUsesSize: true,
    );
    standing.layout(
      BoxConstraints.tightFor(width: widths.standing),
      parentUsesSize: true,
    );
    final height = math.max(lead.size.height, standing.size.height);
    // …and the shorter one again, at the taller one's — as a **floor**, never
    // a fixed height. A child given tight constraints is a relayout boundary:
    // when its own content later grew (the past-due line arrives after the
    // first frame; a count lands; text scale changes) it re-laid itself out
    // inside the old height and overflowed, and this band never heard. With a
    // floor it is no boundary, so a change in either side comes back here.
    if (lead.size.height < height) {
      lead.layout(
        BoxConstraints(
          minWidth: widths.lead,
          maxWidth: widths.lead,
          minHeight: height,
        ),
        parentUsesSize: true,
      );
    }
    if (standing.size.height < height) {
      standing.layout(
        BoxConstraints(
          minWidth: widths.standing,
          maxWidth: widths.standing,
          minHeight: height,
        ),
        parentUsesSize: true,
      );
    }

    final leadFirst = textDirection == TextDirection.ltr;
    (lead.parentData! as _EvenBandParentData).offset = Offset(
      leadFirst ? 0 : widths.standing + gap,
      0,
    );
    (standing.parentData! as _EvenBandParentData).offset = Offset(
      leadFirst ? widths.lead + gap : 0,
      0,
    );
    size = constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  // Not answerable without laying the children out — which is the reason this
  // class exists. Nothing above the band asks.
  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(
      debugCannotComputeDryLayout(
        reason:
            'The band takes the height of its taller child, and both '
            'children contain a LayoutBuilder, which cannot be dry-laid out.',
      ),
    );
    return Size.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
