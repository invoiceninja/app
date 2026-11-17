import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Equal-width cards side by side, stretched to the tallest one's height —
/// the wide billing editor's top row (docs/form-fields.md § A billing
/// document's details are three cards across the top).
///
/// Not `IntrinsicHeight` + `CrossAxisAlignment.stretch`: the cards hold
/// pickers, date fields and custom-field pairs, and any `LayoutBuilder` under
/// an intrinsic pass throws. This lays each card out at its own height
/// first, then the shorter ones again with the tallest's as their floor —
/// ordinary layouts, no intrinsics (the shape of `_EvenBand`, the record
/// screen's band, for three equal columns instead of two weighted ones).
/// Children are placed start to end in the ambient text direction.
class BillingDocDetailsRow extends MultiChildRenderObjectWidget {
  const BillingDocDetailsRow({
    super.key,
    required this.gap,
    required super.children,
  });

  /// The space between two cards.
  final double gap;

  @override
  RenderBillingDocDetailsRow createRenderObject(BuildContext context) =>
      RenderBillingDocDetailsRow(
        gap: gap,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBillingDocDetailsRow renderObject,
  ) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class _DetailsRowParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object behind [BillingDocDetailsRow].
class RenderBillingDocDetailsRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DetailsRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DetailsRowParentData> {
  RenderBillingDocDetailsRow({
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

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DetailsRowParentData) {
      child.parentData = _DetailsRowParentData();
    }
  }

  double _childWidth(double width) =>
      childCount == 0 ? 0 : (width - _gap * (childCount - 1)) / childCount;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    assert(width.isFinite, 'BillingDocDetailsRow needs a bounded width');
    final childWidth = math.max(0.0, _childWidth(width));
    var height = 0.0;
    // Each card at its own height first …
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(
        BoxConstraints(minWidth: childWidth, maxWidth: childWidth),
        parentUsesSize: true,
      );
      height = math.max(height, child.size.height);
    }
    // … then each shorter one again, at the tallest's — as a FLOOR, never a
    // tight height: a tightly constrained child is a relayout boundary, so a
    // card that later grew (a partial due date appearing, an error line)
    // would re-lay itself out inside the old height and overflow without
    // this row hearing (the trap `_EvenBand` in entity_record_column.dart
    // documents).
    var x = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.size.height < height) {
        child.layout(
          BoxConstraints(
            minWidth: childWidth,
            maxWidth: childWidth,
            minHeight: height,
          ),
          parentUsesSize: true,
        );
      }
      final dx = _textDirection == TextDirection.rtl
          ? width - x - childWidth
          : x;
      (child.parentData! as _DetailsRowParentData).offset = Offset(dx, 0);
      x += childWidth + _gap;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _maxChildHeight(width, (c, w) => c.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _maxChildHeight(width, (c, w) => c.getMaxIntrinsicHeight(w));

  double _maxChildHeight(
    double width,
    double Function(RenderBox child, double width) measure,
  ) {
    final childWidth = width.isFinite
        ? math.max(0.0, _childWidth(width))
        : double.infinity;
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      height = math.max(height, measure(child, childWidth));
    }
    return height;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _sumChildWidths(height, (c, h) => c.getMinIntrinsicWidth(h));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _sumChildWidths(height, (c, h) => c.getMaxIntrinsicWidth(h));

  /// Equal widths: every card as wide as the widest needs.
  double _sumChildWidths(
    double height,
    double Function(RenderBox child, double height) measure,
  ) {
    var widest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      widest = math.max(widest, measure(child, height));
    }
    return childCount == 0 ? 0 : widest * childCount + _gap * (childCount - 1);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final childWidth = math.max(0.0, _childWidth(width));
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      height = math.max(
        height,
        child
            .getDryLayout(
              BoxConstraints(minWidth: childWidth, maxWidth: childWidth),
            )
            .height,
      );
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
