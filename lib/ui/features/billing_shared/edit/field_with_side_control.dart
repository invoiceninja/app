import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// A field with a control beside it — the billing editor's discount and its
/// `%` / amount switch — the control built at the height of the field's
/// input box, top and bottom level with it.
///
/// Measured, because neither half has a fixed height. The field's box is
/// 36–54 px depending on the platform's density, the list density (label
/// above or inside) and the text scale. And a `SegmentedButton` cannot be
/// stretched: it sizes its segments from their own intrinsic height and
/// ignores a taller constraint, so under `IntrinsicHeight` + stretch its
/// render box grew to 44 px while the segments it paints stayed 32 (macOS,
/// compact density) — the gap under the `$` Hillel saw (2026-11-17). The
/// control has to be told the height and size its segments to it.
///
/// The height is the input box's alone (`InputDecorator.containerOf`), never
/// the field's whole height: a 422 error or a helper line under the box
/// would otherwise grow the control past the box's bottom.
///
/// When the row is too narrow for the control at its natural width plus
/// [minFieldWidth] of field (large text, a narrow card), the control drops
/// under the field instead, full width — it overflowed the card by 37–107 px
/// at 2x text (5.1.31 review).
///
/// [control] is called with null until the field has been laid out once,
/// then with its box's height; a change (text scale, density, an error line)
/// rebuilds it on the next frame. docs/form-fields.md § A billing document's
/// details are three cards across the top.
class FieldWithSideControl extends StatefulWidget {
  const FieldWithSideControl({
    super.key,
    required this.field,
    required this.control,
    this.minFieldWidth = 64,
  });

  final Widget field;

  /// The control, at `height` — the field's measured input-box height, or
  /// null before the first measurement.
  final Widget Function(BuildContext context, double? height) control;

  /// The narrowest the field may get beside the control, before the text
  /// scale (which multiplies it) — room for a value like `100.00`. Narrower,
  /// the control stacks under it.
  final double minFieldWidth;

  @override
  State<FieldWithSideControl> createState() => _FieldWithSideControlState();
}

class _FieldWithSideControlState extends State<FieldWithSideControl> {
  final _fieldKey = GlobalKey();
  double? _height;

  /// After a layout of the field: its input box's height, or — for a field
  /// that is not an `InputDecorator` — the field's own.
  void _onFieldLayout(double fieldHeight) {
    if (!mounted) return;
    final height = _boxHeight() ?? fieldHeight;
    if (height == _height) return;
    setState(() => _height = height);
  }

  double? _boxHeight() {
    final root = _fieldKey.currentContext;
    if (root == null) return null;
    Element? decorator;
    void find(Element e) {
      if (decorator != null) return;
      if (e.widget is InputDecorator) {
        decorator = e;
        return;
      }
      e.visitChildElements(find);
    }

    (root as Element).visitChildElements(find);
    if (decorator == null) return null;
    // `containerOf` looks up from below the decorator's render object, so
    // ask from a leaf: every leaf of the decorator lies inside one of its
    // slots.
    var leaf = decorator!;
    for (;;) {
      Element? first;
      leaf.visitChildElements((child) => first ??= child);
      if (first == null) break;
      leaf = first!;
    }
    final box = InputDecorator.containerOf(leaf);
    return (box != null && box.hasSize) ? box.size.height : null;
  }

  @override
  Widget build(BuildContext context) {
    return _SideControlLayout(
      gap: InSpacing.sm,
      minFieldWidth: MediaQuery.textScalerOf(
        context,
      ).scale(widget.minFieldWidth),
      textDirection: Directionality.of(context),
      children: [
        _HeightReporter(
          key: _fieldKey,
          onHeight: _onFieldLayout,
          child: widget.field,
        ),
        widget.control(context, _height),
      ],
    );
  }
}

/// The field (first child) and the control (second): side by side when the
/// field keeps [minFieldWidth] beside the control's natural width, the
/// control under the field at full width when it does not.
class _SideControlLayout extends MultiChildRenderObjectWidget {
  const _SideControlLayout({
    required this.gap,
    required this.minFieldWidth,
    required this.textDirection,
    required super.children,
  });

  final double gap;
  final double minFieldWidth;
  final TextDirection textDirection;

  @override
  _RenderSideControlLayout createRenderObject(BuildContext context) =>
      _RenderSideControlLayout(
        gap: gap,
        minFieldWidth: minFieldWidth,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSideControlLayout renderObject,
  ) {
    renderObject
      ..gap = gap
      ..minFieldWidth = minFieldWidth
      ..textDirection = textDirection;
  }
}

class _SideControlParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSideControlLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SideControlParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SideControlParentData> {
  _RenderSideControlLayout({
    required double gap,
    required double minFieldWidth,
    required TextDirection textDirection,
  }) : _gap = gap,
       _minFieldWidth = minFieldWidth,
       _textDirection = textDirection;

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _minFieldWidth;
  set minFieldWidth(double v) {
    if (v == _minFieldWidth) return;
    _minFieldWidth = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  RenderBox get _field => firstChild!;
  RenderBox get _control => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SideControlParentData) {
      child.parentData = _SideControlParentData();
    }
  }

  /// Whether, at [maxWidth], the control goes under the field.
  bool _stacks(double maxWidth) {
    if (!maxWidth.isFinite) return false;
    final controlWidth = _control.getMaxIntrinsicWidth(double.infinity);
    return maxWidth - _gap - controlWidth < _minFieldWidth;
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final maxWidth = constraints.maxWidth;
    Size lay(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    if (_stacks(maxWidth)) {
      final full = BoxConstraints.tightFor(width: maxWidth);
      final field = lay(_field, full);
      final control = lay(_control, full);
      if (!dry) {
        (_field.parentData! as _SideControlParentData).offset = Offset.zero;
        (_control.parentData! as _SideControlParentData).offset = Offset(
          0,
          field.height + _gap,
        );
      }
      return constraints.constrain(
        Size(maxWidth, field.height + _gap + control.height),
      );
    }

    final control = lay(_control, BoxConstraints(maxWidth: maxWidth));
    final fieldWidth = maxWidth.isFinite
        ? math.max(0.0, maxWidth - _gap - control.width)
        : _field.getMaxIntrinsicWidth(double.infinity);
    final field = lay(_field, BoxConstraints.tightFor(width: fieldWidth));
    final width = fieldWidth + _gap + control.width;
    if (!dry) {
      final ltr = _textDirection == TextDirection.ltr;
      (_field.parentData! as _SideControlParentData).offset = Offset(
        ltr ? 0 : width - fieldWidth,
        0,
      );
      (_control.parentData! as _SideControlParentData).offset = Offset(
        ltr ? fieldWidth + _gap : 0,
        0,
      );
    }
    return constraints.constrain(
      Size(width, math.max(field.height, control.height)),
    );
  }

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _minFieldWidth + _gap + _control.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _field.getMaxIntrinsicWidth(height) +
      _gap +
      _control.getMaxIntrinsicWidth(height);

  double _intrinsicHeight(double width, double Function(RenderBox) of) {
    if (_stacks(width)) return of(_field) + _gap + of(_control);
    return math.max(of(_field), of(_control));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (c) => c.getMaxIntrinsicHeight(width));

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Reports, after the frame, that its child was laid out at a new height.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({
    super.key,
    required this.onHeight,
    required super.child,
  });

  final ValueChanged<double> onHeight;

  @override
  _RenderHeightReporter createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // Not during layout: the listener rebuilds the control.
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
