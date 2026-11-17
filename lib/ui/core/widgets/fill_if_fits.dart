import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Lays its child out at the full [width] when the child's natural width fits
/// it — a [SegmentedButton] given a tight width shares it equally among its
/// segments — and at its natural width otherwise, for a scroll view around it
/// to scroll. Decided by measurement, because the labels are translated: the
/// same row fits in English and not in German.
///
/// Shared by `SegmentedSettingRow`, `SettingRow` (the stacked control of a
/// narrow row) and `InSegmented` (its fill-the-line mode).
class FillIfFits extends SingleChildRenderObjectWidget {
  const FillIfFits({super.key, required this.width, required super.child});

  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFillIfFits(width);

  @override
  void updateRenderObject(BuildContext context, RenderFillIfFits renderObject) {
    renderObject.width = width;
  }
}

/// The render object behind [FillIfFits].
class RenderFillIfFits extends RenderProxyBox {
  RenderFillIfFits(this._width);

  double _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(RenderBox child) =>
      child.getMaxIntrinsicWidth(double.infinity) <= _width
      ? BoxConstraints.tightFor(width: _width)
      : const BoxConstraints();

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(child.getDryLayout(_childConstraints(child)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(child), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }
}
