import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:overflow_view/overflow_view.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_create_fab.dart';

/// The widest the strip may grow.
const double kDashboardCreateStripMaxWidth = 720;

/// The most create buttons the strip shows, the primary among them: "+ Quote",
/// "+ Payment" and the split "New Invoice". Everything else is in the split
/// button's menu however wide the window is. It once showed as many as fit in
/// 720 px, about six: a row of equal "+" buttons where the one the user comes
/// for had to be found among them.
const int kDashboardCreateStripMaxButtons = 3;

/// The wide dashboard's create buttons: "+ Quote", "+ Payment", then the one
/// filled "New Invoice" — a split button whose ▾ opens every other create the
/// user may start, in the order the phone's `+` sheet uses.
///
/// It lives in the dashboard's fixed top bar, not in the page. A row of create
/// buttons in the scrolling body is what the phone layout once had and lost
/// (invoiceninja/flutter#164): it scrolled away with the page, so the one thing
/// a user comes to the dashboard to do most was off screen as soon as they
/// read anything.
///
/// **The first option is the primary, and it sits at the trailing end** —
/// the corner a primary action takes in a toolbar — outside the measured run,
/// so no squeeze can fold it away. It reads as the full phrase ("New
/// Invoice"): it stands apart from its neighbours, and a bare noun in a filled
/// button reads as a label rather than a verb. The secondaries keep the bare
/// noun beside a `+`.
///
/// **The ▾ is the strip's only menu, and it lists every other create** —
/// the outlined secondaries included. There was a separate "⋮ More" button
/// beside the primary; it is gone, and the ▾ took its job: one place to look
/// for "the rest", attached to the thing it is the rest *of*. Listing the
/// visible secondaries again costs two menu rows and buys a menu that never
/// changes with the window's width.
///
/// **How many secondaries show is measured, not guessed.** `OverflowView`
/// lays out as many as fit and simply drops the rest — they are already in
/// the ▾ menu — so German's longer nouns or a narrower window move the cut
/// without a breakpoint table to keep in step. That is also why no button in
/// the run carries a `Tooltip`: `OverflowView` lays its children out inside a
/// layout callback, where an `OverlayPortal` cannot mount (see
/// `EntityOverflowActionBar`). The split button is outside the run, so its ▾
/// may. A slot too narrow for the split button is the host's to collapse
/// ([dashboardCreateStripMinWidth], [DashboardCreateMenuButton]).
///
/// Renders nothing — and takes no space — when [options] is empty, so a user
/// who may create nothing gets no strip rather than an empty one.
class DashboardCreateStrip extends StatelessWidget {
  const DashboardCreateStrip({
    super.key,
    required this.options,
    required this.onCreate,
  });

  /// What the user may create, already gated by `quickCreateEntities` and in
  /// its order. The first is drawn as the primary.
  final List<QuickCreateOption> options;

  final ValueChanged<QuickCreateOption> onCreate;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final primary = options.first;
    final rest = options.sublist(1);
    final inline = rest.length < kDashboardCreateStripMaxButtons
        ? rest
        : rest.sublist(0, kDashboardCreateStripMaxButtons - 1);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: kDashboardCreateStripMaxWidth,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inline.isNotEmpty) ...[
            // Loose: the run takes what the primary leaves, and no more.
            Flexible(
              child: OverflowView.flexible(
                spacing: InSpacing.sm,
                children: [
                  for (final option in inline)
                    _CreateButton(
                      option: option,
                      primary: false,
                      onTap: () => onCreate(option),
                    ),
                ],
                // A secondary that does not fit is simply not drawn: the ▾
                // menu lists it already.
                builder: (context, remaining) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: InSpacing.sm),
          ],
          if (rest.isEmpty)
            _CreateButton(
              option: primary,
              primary: true,
              onTap: () => onCreate(primary),
            )
          else
            _SplitCreateButton(
              primary: primary,
              others: rest,
              onCreate: onCreate,
            ),
        ],
      ),
    );
  }
}

/// The narrowest slot that still holds the strip's floor — the split primary
/// (or the plain one when there is nothing else) — at the current text size.
///
/// The host collapses the strip to [DashboardCreateMenuButton] below this. It
/// is measured from the label rather than a constant because the primary
/// reads as a phrase, and "Neue Rechnung" at 140 % text is a different width
/// from "New Invoice" at 100 %. The chrome figures are the button themes'
/// (`theme.dart`): 18 px padding a side on a filled button, an icon, and the
/// 8 px icon gap; then the ▾ segment and its 1 px seam.
double dashboardCreateStripMinWidth(
  BuildContext context,
  List<QuickCreateOption> options,
) {
  if (options.isEmpty) return 0;
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final painter = TextPainter(
    text: TextSpan(
      text: context.tr(options.first.labelKey),
      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final primary = painter.width + 18 * 2 + 16 + 8;
  painter.dispose();
  if (options.length == 1) return primary.ceilToDouble() + 4;
  // A few pixels of slack: the measured run must never be the one that clips.
  return (primary + 1 + _splitSegmentWidth()).ceilToDouble() + 8;
}

/// One height for every button in the strip. The theme floors a filled button
/// at 44 and an outlined one at 40, which left the primary 4 px taller than
/// its neighbours; on touch all of them take the touch target.
double _stripButtonHeight() => Env.isTouchPrimary ? InSizes.touchTarget : 40;

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.option,
    required this.primary,
    required this.onTap,
  });

  final QuickCreateOption option;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = Size(64, _stripButtonHeight());
    // An action (Scan Receipt) wears its own icon: it is not a `+ <noun>`.
    final icon = Icon(
      option.action == null ? Icons.add : option.icon,
      size: 16,
    );
    final label = Text(
      context.tr(primary ? option.labelKey : option.nounKey),
      maxLines: 1,
      softWrap: false,
    );
    final Widget button = primary
        ? FilledButton.icon(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              minimumSize: size,
              maximumSize: Size(double.infinity, size.height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: icon,
            label: label,
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              maximumSize: Size(double.infinity, size.height),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: icon,
            label: label,
          );
    // The visible label is the bare noun beside a `+`; a screen reader gets the
    // full phrase the phone's sheet and the list screens use ("New Invoice",
    // "Enter Payment"). `onTap` is re-declared because `excludeSemantics`
    // drops the button's own.
    return Semantics(
      button: true,
      label: context.tr(option.labelKey),
      onTap: onTap,
      excludeSemantics: true,
      child: button,
    );
  }
}

/// The ▾ segment's width: the touch target on touch, else a narrow square-ish
/// segment beside the 40 px tall primary.
double _splitSegmentWidth() => Env.isTouchPrimary ? InSizes.touchTarget : 34;

/// "New Invoice ▾": the primary create, with every other create one tap away
/// on the ▾ segment attached to its end.
///
/// Two filled buttons sharing one rounded rectangle — the start corners on the
/// main part, the end corners on the ▾ — with a 1 px seam in the button's own
/// foreground at low opacity between them. The main part is the create; the
/// ▾ opens a [BackDismissibleMenuAnchor] (Android's back closes it) listing
/// [others] in their `quickCreateEntities` order.
class _SplitCreateButton extends StatelessWidget {
  const _SplitCreateButton({
    required this.primary,
    required this.others,
    required this.onCreate,
  });

  final QuickCreateOption primary;
  final List<QuickCreateOption> others;
  final ValueChanged<QuickCreateOption> onCreate;

  @override
  Widget build(BuildContext context) {
    final height = _stripButtonHeight();
    final scheme = Theme.of(context).colorScheme;
    const r = Radius.circular(InRadii.r2);
    final main = Semantics(
      button: true,
      label: context.tr(primary.labelKey),
      onTap: () => onCreate(primary),
      excludeSemantics: true,
      child: FilledButton.icon(
        onPressed: () => onCreate(primary),
        style: FilledButton.styleFrom(
          minimumSize: Size(64, height),
          maximumSize: Size(double.infinity, height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.horizontal(start: r),
          ),
        ),
        icon: const Icon(Icons.add, size: 16),
        label: Text(context.tr(primary.labelKey), maxLines: 1, softWrap: false),
      ),
    );
    final menu = BackDismissibleMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        for (final option in others)
          MenuItemButton(
            leadingIcon: Icon(option.icon, size: 18),
            onPressed: () => onCreate(option),
            child: Text(context.tr(option.labelKey)),
          ),
      ],
      builder: (context, controller, _) => FilledButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: FilledButton.styleFrom(
          minimumSize: Size(_splitSegmentWidth(), height),
          maximumSize: Size(_splitSegmentWidth(), height),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.horizontal(end: r),
          ),
        ),
        child: Tooltip(
          message: context.tr('more'),
          // The seam: the filled button's own ink, faint, so the two halves
          // read as one control with two targets. It is drawn inside this
          // half at half its height — a free-standing divider at the nominal
          // height stood taller than the buttons.
          // Sized to the height the main half actually renders at: the
          // theme's visual density takes 8 px off a button's minimum height
          // on desktop but not its maximum, so an expanding child made this
          // half taller than New Invoice.
          child: SizedBox(
            width: _splitSegmentWidth(),
            height: math.max(
              0,
              height + Theme.of(context).visualDensity.baseSizeAdjustment.dy,
            ),
            child: Stack(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    heightFactor: 0.5,
                    child: SizedBox(
                      width: 1,
                      child: ColoredBox(
                        color: Color.alphaBlend(
                          scheme.onPrimary.withValues(alpha: 0.35),
                          scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const Center(child: Icon(Icons.keyboard_arrow_down, size: 18)),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [main, menu]);
  }
}

/// Every create behind one filled `+` — what the strip becomes in a slot too
/// tight for the split button.
class _AllCreatesMenu extends StatelessWidget {
  const _AllCreatesMenu({required this.options, required this.onCreate});

  final List<QuickCreateOption> options;
  final ValueChanged<QuickCreateOption> onCreate;

  @override
  Widget build(BuildContext context) {
    final height = _stripButtonHeight();
    return BackDismissibleMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            leadingIcon: Icon(option.icon, size: 18),
            onPressed: () => onCreate(option),
            child: Text(context.tr(option.labelKey)),
          ),
      ],
      builder: (context, controller, _) => IconButton.filled(
        tooltip: context.tr('create'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add, size: 20),
        constraints: BoxConstraints.tightFor(width: height, height: height),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InRadii.r2),
          ),
        ),
      ),
    );
  }
}

/// Width (and height) of [DashboardCreateMenuButton].
double dashboardCreateMenuButtonExtent() => _stripButtonHeight();

/// Every create behind one `+` button — what the strip becomes in a slot too
/// tight for a labelled button. The wide layout has no `+` FAB, so however
/// little room the bar has, creating something must stay one tap and a pick
/// away.
class DashboardCreateMenuButton extends StatelessWidget {
  const DashboardCreateMenuButton({
    super.key,
    required this.options,
    required this.onCreate,
  });

  final List<QuickCreateOption> options;
  final ValueChanged<QuickCreateOption> onCreate;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return _AllCreatesMenu(options: options, onCreate: onCreate);
  }
}
