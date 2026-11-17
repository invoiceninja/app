import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/ui/core/widgets/fill_if_fits.dart';
import 'package:admin/ui/core/widgets/in_segmented.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';

/// Below this row width a [SettingRow] stacks its control under its text: a
/// three- or four-segment picker beside a title leaves the title no room.
const double kSettingRowStackWidth = 520;

/// The leading icon's box.
const double _kIconSize = 20;

/// Between the icon and the text.
const double _kIconGap = 14;

/// The narrowest the text column may be squeezed by a wide row's control
/// before the control scrolls instead.
const double _kMinTextWidth = 140;

/// The start inset of everything that lines up with a row's text — its
/// divider, a [SettingBlock], a stacked control.
double settingRowTextInset(BuildContext context) =>
    _hPad(context) + _kIconSize + _kIconGap;

double _hPad(BuildContext context) =>
    FormSection.isFlush(context) ? InSpacing.lg(context) : 0;

/// One row of a settings card (Device Settings): a 20 px `ink3` icon, a title
/// over an optional subtitle, and a [control] at the end.
///
/// * In a flush [FormSection] the row pads itself `InSpacing.lg` at the sides,
///   so its hover tint and its divider ([SettingRowDivider]) reach the card's
///   edges; in an ordinary card it sits on the card's own padding.
/// * Below [kSettingRowStackWidth] the control drops under the text, starting
///   at the text's edge. An [InSegmented] there fills the line (an
///   [InSegmentedFill]); one too wide even for that scrolls.
/// * At least 44 px tall on a touch platform.
///
/// [SettingRow.toggle] is the switch row: the whole row toggles, the switch
/// never stacks, and the row is at least 48 px tall — what `SwitchListTile`
/// gave the rows it replaced.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.details,
    this.control,
    this.onTap,
    this.stackWhenNarrow = true,
  }) : _toggle = null;

  /// A switch row. [onChanged] null disables it.
  const SettingRow.toggle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.details,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) : control = null,
       onTap = null,
       stackWhenNarrow = false,
       _toggle = (value: value, onChanged: onChanged);

  /// An [Icon] (or anything icon-sized): drawn 20 px in `ink3`.
  final Widget icon;
  final String title;
  final String? subtitle;

  /// More under the subtitle — a second line that takes a parameter.
  final Widget? details;
  final Widget? control;

  /// Makes the whole row a button — a disclosure row.
  final VoidCallback? onTap;

  /// False for a control that always fits beside the text: a switch, a
  /// button, a chevron.
  final bool stackWhenNarrow;

  final ({bool value, ValueChanged<bool>? onChanged})? _toggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final hPad = _hPad(context);
    final toggle = _toggle;
    final control = toggle == null
        ? this.control
        : Switch(value: toggle.value, onChanged: toggle.onChanged);
    final minHeight = toggle != null
        ? 48.0
        : Env.isTouchPrimary
        ? InSizes.touchTarget
        : 0.0;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (subtitle case final s? when s.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            s,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink2),
          ),
        ],
        if (details case final d?) ...[
          const SizedBox(height: InSpacing.xs),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink2),
            child: d,
          ),
        ],
      ],
    );
    final leading = IconTheme.merge(
      data: IconThemeData(size: _kIconSize, color: tokens.ink3),
      child: SizedBox(
        width: _kIconSize,
        child: Center(child: icon),
      ),
    );

    Widget body = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final head = Row(
          children: [
            leading,
            const SizedBox(width: _kIconGap),
            Expanded(child: text),
          ],
        );
        if (control == null) return head;
        if (!stackWhenNarrow || width >= kSettingRowStackWidth) {
          // Beside the text while the text keeps [_kMinTextWidth]; under it
          // when the control is too wide for that — a long translation, 2x
          // text — rather than squeezing the title into a column of letters.
          return _BesideOrBelow(
            gap: InSpacing.lg(context),
            belowInset: _kIconSize + _kIconGap,
            minHeadWidth: _kIconSize + _kIconGap + _kMinTextWidth,
            children: [
              head,
              stackWhenNarrow
                  // A picker wider even than the whole row scrolls.
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: control,
                    )
                  : control,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            head,
            const SizedBox(height: InSpacing.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _kIconSize + _kIconGap,
              ),
              child: LayoutBuilder(
                builder: (context, inner) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: FillIfFits(
                    width: inner.maxWidth,
                    child: InSegmentedFill(child: control),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    body = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: hPad,
        vertical: InSpacing.md(context),
      ),
      child: body,
    );

    final tap =
        onTap ??
        (toggle?.onChanged == null
            ? null
            : () => toggle!.onChanged!(!toggle.value));
    if (tap == null) return body;
    final ink = InkWell(
      onTap: tap,
      // A switch row's one stop is its switch (Space toggles it); a second,
      // the row, would read the same thing twice.
      canRequestFocus: toggle == null,
      child: body,
    );
    // One node for a screen reader: the title, the subtitle and the switch's
    // state, as `SwitchListTile` read.
    return toggle == null ? ink : MergeSemantics(child: ink);
  }
}

/// The rule between two [SettingRow]s, inset to their text column, in
/// `border`.
class SettingRowDivider extends StatelessWidget {
  const SettingRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: settingRowTextInset(context)),
      child: Divider(height: 1, thickness: 1, color: context.inTheme.border),
    );
  }
}

/// [rows] with a [SettingRowDivider] between each two. Leave a row that does
/// not apply out of the list rather than passing an empty box, or it costs a
/// divider.
List<Widget> withSettingDividers(List<Widget> rows) => [
  for (var i = 0; i < rows.length; i++) ...[
    if (i > 0) const SettingRowDivider(),
    rows[i],
  ],
];

/// Content in a flush card that is not a [SettingRow] — a field pair, a
/// status line, a button — padded like a row, and by default starting at the
/// rows' text edge.
class SettingBlock extends StatelessWidget {
  const SettingBlock({super.key, required this.child, this.indent = true});

  final Widget child;

  /// False starts it at the row's icon edge instead.
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final hPad = _hPad(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        indent ? settingRowTextInset(context) : hPad,
        InSpacing.sm,
        hPad,
        InSpacing.md(context),
      ),
      child: child,
    );
  }
}

/// A row's text and its control: side by side while the text keeps
/// [minHeadWidth], the control's natural width beside it; otherwise the
/// control drops under the text, [belowInset] in from the start. Decided by
/// measuring the control, because its width depends on the language and the
/// text scale.
class _BesideOrBelow extends MultiChildRenderObjectWidget {
  const _BesideOrBelow({
    required this.gap,
    required this.belowInset,
    required this.minHeadWidth,
    required super.children,
  });

  final double gap;
  final double belowInset;
  final double minHeadWidth;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBesideOrBelow(
    gap: gap,
    belowInset: belowInset,
    minHeadWidth: minHeadWidth,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBesideOrBelow renderObject,
  ) {
    renderObject
      ..gap = gap
      ..belowInset = belowInset
      ..minHeadWidth = minHeadWidth
      ..textDirection = Directionality.of(context);
  }
}

class _BesideOrBelowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderBesideOrBelow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BesideOrBelowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BesideOrBelowParentData> {
  _RenderBesideOrBelow({
    required double gap,
    required double belowInset,
    required double minHeadWidth,
    required TextDirection textDirection,
  }) : _gap = gap,
       _belowInset = belowInset,
       _minHeadWidth = minHeadWidth,
       _textDirection = textDirection;

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _belowInset;
  set belowInset(double v) {
    if (v == _belowInset) return;
    _belowInset = v;
    markNeedsLayout();
  }

  double _minHeadWidth;
  set minHeadWidth(double v) {
    if (v == _minHeadWidth) return;
    _minHeadWidth = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  /// Between the text and a control under it.
  static const double _belowGap = InSpacing.sm;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BesideOrBelowParentData) {
      child.parentData = _BesideOrBelowParentData();
    }
  }

  RenderBox get _head => firstChild!;
  RenderBox get _control => lastChild!;

  bool _beside(double width) =>
      width - _control.getMaxIntrinsicWidth(double.infinity) - _gap >=
      _minHeadWidth;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _head.getMinIntrinsicWidth(height),
    _belowInset + _control.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _head.getMaxIntrinsicWidth(height) +
      _gap +
      _control.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _heightFor(width, (b, w) => b.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _heightFor(width, (b, w) => b.getMaxIntrinsicHeight(w));

  double _heightFor(double width, double Function(RenderBox, double) h) {
    if (!width.isFinite) {
      return math.max(h(_head, width), h(_control, width));
    }
    if (_beside(width)) {
      final cw = math.min(
        _control.getMaxIntrinsicWidth(double.infinity),
        width - _minHeadWidth - _gap,
      );
      return math.max(h(_head, width - cw - _gap), h(_control, cw));
    }
    return h(_head, width) +
        _belowGap +
        h(_control, math.max(0, width - _belowInset));
  }

  ({Size head, Size control, bool beside}) _sizes(
    BoxConstraints constraints,
    Size Function(RenderBox, BoxConstraints) lay,
  ) {
    final width = constraints.maxWidth;
    if (_beside(width)) {
      final control = lay(
        _control,
        BoxConstraints(maxWidth: math.max(0, width - _minHeadWidth - _gap)),
      );
      final head = lay(
        _head,
        BoxConstraints.tightFor(
          width: math.max(0, width - control.width - _gap),
        ),
      );
      return (head: head, control: control, beside: true);
    }
    final head = lay(_head, BoxConstraints.tightFor(width: width));
    final control = lay(
      _control,
      BoxConstraints(maxWidth: math.max(0, width - _belowInset)),
    );
    return (head: head, control: control, beside: false);
  }

  Size _sizeOf(
    ({Size head, Size control, bool beside}) s,
    BoxConstraints constraints,
  ) => constraints.constrain(
    Size(
      constraints.maxWidth,
      s.beside
          ? math.max(s.head.height, s.control.height)
          : s.head.height + _belowGap + s.control.height,
    ),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _sizeOf(_sizes(constraints, (b, c) => b.getDryLayout(c)), constraints);

  @override
  void performLayout() {
    final s = _sizes(constraints, (b, c) {
      b.layout(c, parentUsesSize: true);
      return b.size;
    });
    size = _sizeOf(s, constraints);
    final rtl = _textDirection == TextDirection.rtl;
    final headData = _head.parentData! as _BesideOrBelowParentData;
    final controlData = _control.parentData! as _BesideOrBelowParentData;
    if (s.beside) {
      final headTop = (size.height - s.head.height) / 2;
      final controlTop = (size.height - s.control.height) / 2;
      headData.offset = Offset(rtl ? size.width - s.head.width : 0, headTop);
      controlData.offset = Offset(
        rtl ? 0 : size.width - s.control.width,
        controlTop,
      );
    } else {
      headData.offset = Offset.zero;
      controlData.offset = Offset(
        rtl ? size.width - _belowInset - s.control.width : _belowInset,
        s.head.height + _belowGap,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
