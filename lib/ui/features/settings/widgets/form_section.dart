import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';

/// Groups a related set of form fields under a single subheading, rendered
/// as a bordered card (surface + 1px border + r3 + shadow1) with a header
/// row + divider. Mirrors the v2 card pattern used by the dashboard and
/// client detail screens. The optional [trailing] widget renders on the
/// right of the header row (e.g. an "Upload" button on the Documents tab).
///
/// [spacing] (default `InSpacing.lg(context)`) is interleaved between adjacent
/// children so callers don't sprinkle `SizedBox(height: …)` between every
/// field — pass `0` if the section manages its own gaps (e.g. it places a
/// `Divider` between rows).
///
/// Two layouts. Stacked (the default, every width): the title, then the
/// [description], inside the card above the fields. Side by side, only under
/// a [FormSectionSideLayout] — which `SettingsFormShell` publishes when its
/// content has the width: the title and description in a fixed start
/// column, the card beside it holding just the fields.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.trailing,
    this.spacing,
    this.elevated = true,
    this.flush = false,
  });

  /// Section heading. When null, the header row + divider are omitted
  /// entirely and the card is just a padded container of [children] —
  /// used by the billing-doc edit cards which want a flat, title-less
  /// look. Settings screens pass a non-null title.
  ///
  /// Never the same words as a field label inside the section: a settings
  /// search hit flashes the first text on the page that reads its label, and
  /// the title comes first.
  final String? title;

  /// One or two sentences under the title saying what the section is for —
  /// only where that adds something the title and the field labels don't.
  /// Ignored without a [title].
  final String? description;
  final List<Widget> children;
  final Widget? trailing;

  /// When false, drop the drop shadow (keep the 1px border) for a
  /// flatter look. Default true preserves the existing settings /
  /// dashboard appearance.
  final bool elevated;

  /// Gap interleaved between adjacent children. Null falls back to the
  /// responsive `InSpacing.lg(context)` (12 narrow / 16 wide).
  final double? spacing;

  /// True for a card of `SettingRow`s: the body has no padding of its own
  /// (each row pads itself, so its hover tint and its divider can reach the
  /// card's edges), no gap between children, and the card clips to its
  /// corners. A child that is not a row pads itself — `SettingBlock`.
  /// `FormSection.isFlush` tells a row which card it is in.
  final bool flush;

  /// Whether the nearest card around [context] is [flush] — false outside any.
  static bool isFlush(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FlushScope>()?.flush ?? false;

  @override
  Widget build(BuildContext context) {
    final side = FormSectionSideLayout.maybeOf(context);
    final isSide = side != null && side.enabled;
    // Under a shell, one tree for both layouts — only widths and paddings
    // change — so a resize across the side-layout line keeps every field's
    // state (and focus) instead of re-inflating the card under a new parent.
    final titleBlock = title == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _title(context)),
                  // Beside the title when stacked; above the fields when
                  // side by side (the column has no room for a button).
                  if (!isSide) ?trailing,
                ],
              ),
              if (_description != null) ...[
                const SizedBox(height: InSpacing.xs),
                _descriptionText(context),
              ],
            ],
          );
    final Widget? header;
    if (isSide) {
      header = trailing == null
          ? null
          : Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                InSpacing.lg(context),
                InSpacing.md(context),
                InSpacing.lg(context),
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: trailing,
              ),
            );
    } else {
      header = titleBlock == null
          ? null
          : Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                InSpacing.lg(context),
                InSpacing.lg(context),
                InSpacing.lg(context),
                // A flush card's first row brings its own top padding.
                flush ? InSpacing.xs : InSpacing.md(context),
              ),
              child: titleBlock,
            );
    }
    final card = _card(
      context,
      header: header,
      // The fields open the card the way a title-less section's do when
      // nothing sits above them.
      topPad: header == null,
    );
    // Outside a `SettingsFormShell` (no scope at all) the card stands alone:
    // a FormSection on an edit form may sit where its width is unbounded,
    // and the Row's `Expanded` would throw there.
    if (side == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: InSpacing.lg(context)),
        child: card,
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        bottom: isSide ? InSpacing.xl : InSpacing.lg(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isSide ? side.startWidth : 0,
            child: isSide && titleBlock != null
                ? Padding(
                    // Level with the card's first line.
                    padding: EdgeInsetsDirectional.only(
                      top: InSpacing.lg(context),
                      end: InSpacing.lg(context),
                    ),
                    child: titleBlock,
                  )
                : null,
          ),
          SizedBox(width: isSide ? side.gap : 0),
          Expanded(child: card),
        ],
      ),
    );
  }

  String? get _description {
    final d = description?.trim();
    return title == null || d == null || d.isEmpty ? null : d;
  }

  /// A level-2 heading for a screen reader: the page title is level 1.
  Widget _title(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      headingLevel: 2,
      child: Text(
        title!,
        style: theme.textTheme.titleSmall?.copyWith(
          color: context.inTheme.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _descriptionText(BuildContext context) => Text(
    _description!,
    key: const ValueKey('form-section-description'),
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.inTheme.ink2),
  );

  Widget _card(
    BuildContext context, {
    required Widget? header,
    required bool topPad,
  }) {
    final tokens = context.inTheme;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(InRadii.r3),
        border: Border.all(color: tokens.border),
        boxShadow: elevated ? tokens.shadow1 : null,
      ),
      // A transparent Material gives descendant ListTiles/InkWells a Material
      // ancestor to paint ink on — without it, Flutter 3.44 asserts because
      // this Container's background would hide the ink.
      child: Material(
        type: MaterialType.transparency,
        // A flush card's rows paint their hover tint edge to edge; keep it
        // inside the rounded corners.
        shape: flush
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(InRadii.r3 - 1),
              )
            : null,
        clipBehavior: flush ? Clip.antiAlias : Clip.none,
        child: formCardListTileTheme(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?header,
              // No rule under the title: it sits in the card's padding and the
              // fields follow it, as on the edit forms (`DashboardCardShell`).
              Padding(
                // Keyed: a header arriving or leaving above it must not
                // re-inflate the fields.
                key: const ValueKey('form-section-body'),
                padding: flush
                    ? const EdgeInsets.symmetric(vertical: InSpacing.xs)
                    : EdgeInsetsDirectional.fromSTEB(
                        InSpacing.lg(context),
                        topPad ? InSpacing.lg(context) : 0,
                        InSpacing.lg(context),
                        InSpacing.lg(context),
                      ),
                // A section nested in a card never splits again.
                child: FormSectionSideLayout(
                  enabled: false,
                  child: _FlushScope(
                    flush: flush,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _interleave(
                        children,
                        // `sm`: a labelled field brings 8 px above and below
                        // itself (`kFieldVerticalGap`), so `lg` here made the
                        // settings pages' fields half again further apart
                        // than the edit forms'.
                        spacing ?? (flush ? 0 : InSpacing.sm),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _interleave(List<Widget> children, double spacing) {
    if (spacing == 0 || children.length < 2) return children;
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(height: spacing));
      out.add(children[i]);
    }
    return out;
  }
}

/// Tells every [FormSection] below it to lay out side by side: title and
/// description in a [startWidth] column, [gap], then the card. Published by
/// `SettingsFormShell` only when its content is wide enough that the card
/// keeps its full 720 px beside the column — never by a narrower page, where
/// the column would starve a `FormFieldPair`.
class FormSectionSideLayout extends InheritedWidget {
  const FormSectionSideLayout({
    super.key,
    this.startWidth = 200,
    this.gap = 40,
    this.enabled = true,
    required super.child,
  });

  final double startWidth;
  final double gap;

  /// False switches a subtree back to stacked — what a side-laid card puts
  /// around its own fields, so a section nested in it doesn't split again.
  final bool enabled;

  static FormSectionSideLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormSectionSideLayout>();

  @override
  bool updateShouldNotify(FormSectionSideLayout old) =>
      old.startWidth != startWidth || old.gap != gap || old.enabled != enabled;
}

/// Which kind of card a `SettingRow` sits in — see [FormSection.flush].
class _FlushScope extends InheritedWidget {
  const _FlushScope({required this.flush, required super.child});

  final bool flush;

  @override
  bool updateShouldNotify(_FlushScope old) => old.flush != flush;
}
