import 'package:material_ui/material_ui.dart';
import 'package:overflow_view/overflow_view.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_create_fab.dart';

/// The widest the strip may grow.
const double kDashboardCreateStripMaxWidth = 720;

/// The most create buttons the strip shows, the primary among them; the rest
/// are under More however wide the window is. It showed as many as fit in
/// 720 px, about six: a row of equal "+" buttons where the one the user comes
/// for had to be found among them.
const int kDashboardCreateStripMaxButtons = 3;

/// The wide dashboard's create buttons: "+ Quote", "+ Payment", More, then the
/// one filled "New Invoice" — everything the user may start, from the order
/// the phone's `+` sheet uses.
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
/// **How many secondaries show is measured, not guessed.** `OverflowView`
/// lays out as many as fit and hands the rest to the More menu, so German's
/// longer nouns or a narrower window move the cut without a breakpoint table
/// to keep in step. That is also why no button here carries a `Tooltip`:
/// `OverflowView` lays its children out inside a layout callback, where an
/// `OverlayPortal` cannot mount (see `EntityOverflowActionBar`). A slot too
/// narrow for the primary and a More is the host's to collapse
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
    final capped = rest.sublist(inline.length);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: kDashboardCreateStripMaxWidth,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rest.isNotEmpty) ...[
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
                  // The capped creates' own More, last so it is the first
                  // child `OverflowView` hides; the builder's More then
                  // carries them with whatever else did not fit.
                  if (capped.isNotEmpty)
                    _MoreCreates(options: capped, onCreate: onCreate),
                ],
                builder: (context, remaining) {
                  // `remaining` counts hidden children from the end, the
                  // capped More among them. Clamped: in a slot too tight for
                  // even one secondary it can reach the whole run.
                  final hiddenButtons = capped.isEmpty
                      ? remaining
                      : remaining - 1;
                  final hidden = hiddenButtons > inline.length
                      ? inline.length
                      : (hiddenButtons < 0 ? 0 : hiddenButtons);
                  return _MoreCreates(
                    options: [
                      ...inline.sublist(inline.length - hidden),
                      ...capped,
                    ],
                    onCreate: onCreate,
                  );
                },
              ),
            ),
            const SizedBox(width: InSpacing.sm),
          ],
          _CreateButton(
            option: primary,
            primary: true,
            onTap: () => onCreate(primary),
          ),
        ],
      ),
    );
  }
}

/// The narrowest slot that still holds the strip's floor — the primary, and a
/// More beside it when there is anything else — at the current text size.
///
/// The host collapses the strip to [DashboardCreateMenuButton] below this. It
/// is measured from the labels rather than a constant because the primary now
/// reads as a phrase, and "Neue Rechnung" at 140 % text is a different width
/// from "New Invoice" at 100 %. The chrome figures are the button themes'
/// (`theme.dart`): 18 px padding a side on a filled button, 14 on an outlined
/// one, an icon, and the 8 px icon gap.
double dashboardCreateStripMinWidth(
  BuildContext context,
  List<QuickCreateOption> options,
) {
  if (options.isEmpty) return 0;
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  double measure(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final label = theme.textTheme.labelLarge;
  final primary =
      measure(
        context.tr(options.first.labelKey),
        label?.copyWith(fontWeight: FontWeight.w600),
      ) +
      18 * 2 +
      16 +
      8;
  if (options.length == 1) return primary.ceilToDouble() + 4;
  final more = measure(context.tr('more'), label) + 14 * 2 + 18 + 8;
  // A few pixels of slack: the measured run must never be the one that clips.
  return (primary + InSpacing.sm + more).ceilToDouble() + 8;
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

/// The creates that did not fit, under a labelled More button drawn like its
/// neighbours.
class _MoreCreates extends StatelessWidget {
  const _MoreCreates({
    required this.options,
    required this.onCreate,
    this.compact = false,
  });

  final List<QuickCreateOption> options;
  final ValueChanged<QuickCreateOption> onCreate;

  /// A square filled `+` instead of a labelled "More" — the whole strip in one
  /// button, for a slot too tight for anything else.
  final bool compact;

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
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        if (compact) {
          return IconButton.filled(
            tooltip: context.tr('create'),
            onPressed: toggle,
            icon: const Icon(Icons.add, size: 20),
            constraints: BoxConstraints.tightFor(width: height, height: height),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(InRadii.r2),
              ),
            ),
          );
        }
        return OutlinedButton.icon(
          onPressed: toggle,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(64, height),
            maximumSize: Size(double.infinity, height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.more_vert, size: 18),
          label: Text(context.tr('more')),
        );
      },
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
    return _MoreCreates(options: options, onCreate: onCreate, compact: true);
  }
}
