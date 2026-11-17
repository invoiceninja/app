import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import 'package:admin/app/design_tokens.dart';

/// Page-level actions a settings shell hands to the page body below it — the
/// Invoice Design shell's Show Preview, which belongs to the page, not to any
/// one tab, but has to sit on the tab body's intro row.
///
/// `SettingsFormShell` reads it and draws these after its own `actions`, on
/// the one row it shares with the page's intro sentence
/// ([SettingsPageIntro]). The shell re-provides an empty scope under itself,
/// so a nested shell never draws them twice.
///
/// See `docs/settings-screens.md` § A page's intro and its actions share one
/// row.
class SettingsPageActions extends InheritedWidget {
  const SettingsPageActions({
    super.key,
    required this.actions,
    required super.child,
  });

  final List<Widget> actions;

  /// The nearest scope's actions, or none.
  static List<Widget> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsPageActions>()
          ?.actions ??
      const <Widget>[];

  // The actions are rebuilt widgets, so nothing cheaper than "always" would
  // be right — and only a page's one shell depends on this.
  @override
  bool updateShouldNotify(SettingsPageActions oldWidget) => true;
}

/// The row above a settings page's first card: the page's intro sentence at
/// the start, its page-level actions at the end — never each on a row of its
/// own.
///
/// The sentence takes the width the actions leave and wraps; the actions sit
/// level with its **first** line — on a phone too. Only when the column
/// left for the sentence would be unreadably narrow (under 140 px: 2x text
/// on a 320 px phone) do the actions drop under it, end-aligned — never an
/// overflow.
///
/// With no [text] the actions sit at the end on their own; with no [actions]
/// it is the sentence alone.
class SettingsPageIntro extends StatelessWidget {
  const SettingsPageIntro({
    super.key,
    this.text,
    this.actions = const <Widget>[],
  });

  final String? text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final sentence = text == null
        ? null
        : Text(
            text!,
            key: const ValueKey('settings-page-subtitle'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.ink2),
          );
    if (actions.isEmpty) return sentence ?? const SizedBox.shrink();
    final buttons = Wrap(
      key: const ValueKey('settings-page-actions'),
      spacing: InSpacing.sm,
      runSpacing: InSpacing.sm,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    if (sentence == null) {
      return Align(alignment: AlignmentDirectional.centerEnd, child: buttons);
    }
    return _IntroRow(
      gap: InSpacing.md(context),
      textDirection: Directionality.of(context),
      children: [sentence, buttons],
    );
  }
}

/// The narrowest the sentence's column may get beside the actions before
/// they move under it. Phones keep the one row too — a 390 px phone has
/// ~220 px for the sentence beside Preview, and it wraps to as many lines as
/// it needs; only an unreadably narrow column (2x text on a 320 px phone)
/// stacks.
const double _kMinSentenceWidth = 140;

/// Two children — the sentence, then the actions. A `Row` cannot do this: it
/// has no way to move the actions under the sentence when the sentence would
/// be crushed, and a `Wrap` cannot let the sentence wrap beside them.
class _IntroRow extends MultiChildRenderObjectWidget {
  const _IntroRow({
    required this.gap,
    required this.textDirection,
    required super.children,
  });

  final double gap;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntroRow(gap: gap, textDirection: textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderIntroRow renderObject) {
    renderObject
      ..gap = gap
      ..textDirection = textDirection;
  }
}

class _IntroParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderIntroRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _IntroParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _IntroParentData> {
  _RenderIntroRow({required double gap, required TextDirection textDirection})
    : _gap = gap,
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

  RenderBox get _sentence => firstChild!;
  RenderBox get _actions => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _IntroParentData) {
      child.parentData = _IntroParentData();
    }
  }

  double _widthOf(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : constraints.constrainWidth(
          _sentence.getMaxIntrinsicWidth(double.infinity) +
              _gap +
              _actions.getMaxIntrinsicWidth(double.infinity),
        );

  /// Room left for the sentence beside actions [actionsWidth] wide, or null
  /// when that is too narrow and the actions go underneath.
  double? _inlineRoom(double width, double actionsWidth) {
    final room = width - actionsWidth - _gap;
    return room >= _kMinSentenceWidth ? room : null;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = _widthOf(constraints);
    final actions = _actions.getDryLayout(BoxConstraints(maxWidth: width));
    final room = _inlineRoom(width, actions.width);
    if (room != null) {
      final sentence = _sentence.getDryLayout(BoxConstraints(maxWidth: room));
      return constraints.constrain(
        Size(width, math.max(sentence.height, actions.height)),
      );
    }
    final sentence = _sentence.getDryLayout(BoxConstraints(maxWidth: width));
    return constraints.constrain(
      Size(width, sentence.height + InSpacing.sm + actions.height),
    );
  }

  @override
  void performLayout() {
    final width = _widthOf(constraints);
    final sentence = _sentence;
    final actions = _actions;
    actions.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final room = _inlineRoom(width, actions.size.width);
    final rtl = _textDirection == TextDirection.rtl;
    final sentenceData = sentence.parentData! as _IntroParentData;
    final actionsData = actions.parentData! as _IntroParentData;
    if (room == null) {
      // Stacked: the sentence across the row, the actions under it at the end.
      sentence.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      final actionsTop = sentence.size.height + InSpacing.sm;
      sentenceData.offset = Offset(rtl ? width - sentence.size.width : 0, 0);
      actionsData.offset = Offset(
        rtl ? 0 : width - actions.size.width,
        actionsTop,
      );
      size = constraints.constrain(
        Size(width, actionsTop + actions.size.height),
      );
      return;
    }
    sentence.layout(BoxConstraints(maxWidth: room), parentUsesSize: true);
    // Level with the sentence's FIRST line: the actions' centre on that
    // line's. Not baselines — an icon button's highest baseline is its
    // icon's, which sits well above the label's. One line's height is the
    // sentence's height at the width that holds it on one line.
    final firstLine = math.min(
      sentence.size.height,
      sentence.getMaxIntrinsicHeight(
        sentence.getMaxIntrinsicWidth(double.infinity),
      ),
    );
    final lift = (actions.size.height - firstLine) / 2;
    final sentenceTop = math.max(0.0, lift);
    final actionsTop = math.max(0.0, -lift);
    sentenceData.offset = Offset(
      rtl ? width - sentence.size.width : 0,
      sentenceTop,
    );
    actionsData.offset = Offset(
      rtl ? 0 : width - actions.size.width,
      actionsTop,
    );
    size = constraints.constrain(
      Size(
        width,
        math.max(
          sentenceTop + sentence.size.height,
          actionsTop + actions.size.height,
        ),
      ),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _sentence.getMinIntrinsicWidth(height),
    _actions.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _sentence.getMaxIntrinsicWidth(height) +
      _gap +
      _actions.getMaxIntrinsicWidth(height);

  // The stacked height — an upper bound for the inline one.
  @override
  double computeMinIntrinsicHeight(double width) =>
      _sentence.getMinIntrinsicHeight(width) +
      InSpacing.sm +
      _actions.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sentence.getMaxIntrinsicHeight(width) +
      InSpacing.sm +
      _actions.getMaxIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
