import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

/// The two children of a [TrailingIfRoom].
enum TrailingIfRoomSlot { lead, trailing }

/// [lead] at the start edge at its own width, and [trailing] at the end edge
/// — but only when it fits beside [lead] with [gap] to spare. When it does
/// not, [trailing] is neither painted, hit nor read out, and [lead] keeps the
/// whole width: the trailing widget can never push, squeeze or overflow the
/// lead one.
///
/// Built for the status strip's row, where a list's totals line sits in the
/// space after the tabs (docs/entity-lists.md § A money list's totals line).
/// [lead] is laid out with loose constraints, so a horizontal scroller there
/// shrink-wraps its content until the content is wider than the row. [trailing]
/// is measured by its max intrinsic width — a `Text` answers that exactly —
/// and never laid out narrower, so it is shown whole or not at all.
///
/// A render object rather than a `LayoutBuilder`: the decision needs the
/// lead's laid-out width, which changes when its counts load, and a
/// `LayoutBuilder` only rebuilds for a change of its own constraints.
class TrailingIfRoom
    extends SlottedMultiChildRenderObjectWidget<TrailingIfRoomSlot, RenderBox> {
  const TrailingIfRoom({
    required this.lead,
    required this.trailing,
    this.gap = 16,
    super.key,
  });

  final Widget lead;
  final Widget? trailing;

  /// The least space kept between [lead] and [trailing].
  final double gap;

  @override
  Iterable<TrailingIfRoomSlot> get slots => TrailingIfRoomSlot.values;

  @override
  Widget? childForSlot(TrailingIfRoomSlot slot) => switch (slot) {
    TrailingIfRoomSlot.lead => lead,
    TrailingIfRoomSlot.trailing => trailing,
  };

  @override
  RenderTrailingIfRoom createRenderObject(BuildContext context) =>
      RenderTrailingIfRoom(gap: gap, textDirection: Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTrailingIfRoom renderObject,
  ) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

/// The render object behind [TrailingIfRoom].
class RenderTrailingIfRoom extends RenderBox
    with SlottedContainerRenderObjectMixin<TrailingIfRoomSlot, RenderBox> {
  RenderTrailingIfRoom({
    required double gap,
    required TextDirection textDirection,
  }) : _gap = gap,
       _textDirection = textDirection;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Whether the last layout found room for the trailing child.
  bool get showsTrailing => _showsTrailing;
  bool _showsTrailing = false;

  RenderBox? get _lead => childForSlot(TrailingIfRoomSlot.lead);
  RenderBox? get _trailing => childForSlot(TrailingIfRoomSlot.trailing);

  @override
  Iterable<RenderBox> get children => [?_lead, ?_trailing];

  static Offset _offsetOf(RenderBox child) =>
      (child.parentData! as BoxParentData).offset;

  static void _place(RenderBox child, Offset offset) =>
      (child.parentData! as BoxParentData).offset = offset;

  @override
  double computeMinIntrinsicWidth(double height) =>
      _lead?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (_lead?.getMaxIntrinsicWidth(height) ?? 0) +
      (_trailing == null ? 0 : _gap + _trailing!.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _lead?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _lead?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final lead = _lead?.getDryLayout(constraints.loosen()) ?? Size.zero;
    return constraints.constrain(Size(constraints.maxWidth, lead.height));
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final lead = _lead;
    final leadSize = lead == null
        ? Size.zero
        : (lead..layout(constraints.loosen(), parentUsesSize: true)).size;
    size = constraints.constrain(
      Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : leadSize.width,
        leadSize.height,
      ),
    );
    final rtl = _textDirection == TextDirection.rtl;
    if (lead != null) {
      _place(lead, Offset(rtl ? size.width - leadSize.width : 0, 0));
    }

    _showsTrailing = false;
    final trailing = _trailing;
    if (trailing == null) return;
    final room = size.width - leadSize.width - _gap;
    final wanted = trailing.getMaxIntrinsicWidth(size.height);
    final fits = room > 0 && wanted <= room;
    // Laid out either way (a render object must lay out every child), but
    // with no width when there is no room: it is neither painted nor hit.
    trailing.layout(
      BoxConstraints(maxWidth: fits ? wanted : 0, maxHeight: size.height),
      parentUsesSize: true,
    );
    if (!fits) {
      _place(trailing, Offset.zero);
      return;
    }
    _showsTrailing = true;
    final dy = math.max(0.0, (size.height - trailing.size.height) / 2);
    _place(trailing, Offset(rtl ? 0 : size.width - trailing.size.width, dy));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_lead case final lead?) {
      context.paintChild(lead, offset + _offsetOf(lead));
    }
    if (_showsTrailing) {
      final trailing = _trailing!;
      context.paintChild(trailing, offset + _offsetOf(trailing));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [if (_showsTrailing) _trailing!, ?_lead]) {
      final hit = result.addWithPaintOffset(
        offset: _offsetOf(child),
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_lead case final lead?) visitor(lead);
    if (_showsTrailing) visitor(_trailing!);
  }
}
