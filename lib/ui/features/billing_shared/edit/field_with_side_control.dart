import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// A field with a control beside it — the billing editor's discount and its
/// `%` / amount switch — the control built at the field's own measured
/// height, top and bottom level with the field's box.
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
/// [control] is called with null until the field has been laid out once,
/// then with its height; a change (text scale, density) rebuilds it on the
/// next frame. docs/form-fields.md § A billing document's details are three
/// cards across the top.
class FieldWithSideControl extends StatefulWidget {
  const FieldWithSideControl({
    super.key,
    required this.field,
    required this.control,
  });

  final Widget field;

  /// The control, at `height` — the field's measured height, or null before
  /// the first measurement.
  final Widget Function(BuildContext context, double? height) control;

  @override
  State<FieldWithSideControl> createState() => _FieldWithSideControlState();
}

class _FieldWithSideControlState extends State<FieldWithSideControl> {
  double? _height;

  void _onFieldHeight(double height) {
    if (!mounted || height == _height) return;
    setState(() => _height = height);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _HeightReporter(onHeight: _onFieldHeight, child: widget.field),
        ),
        const SizedBox(width: InSpacing.sm),
        widget.control(context, _height),
      ],
    );
  }
}

/// Reports its child's laid-out height after the frame, whenever it changes.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

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
