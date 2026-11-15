import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';

/// Hands the dashboard panel beneath it a `⋮` menu — Hide, and Customize for
/// everything else.
///
/// A host wraps each panel it places in one (the wide grid, the phone's list,
/// and the needs-attention band's slot). `DashboardCardShell` reads it and
/// puts [DashboardPanelMenuButton] at the end of its header, so no card has to
/// thread the callbacks through its own constructor; the band, which draws no
/// header of its own, places the button itself.
///
/// It carries callbacks rather than the view model so the shell — used on
/// record and edit screens all over the app — does not import the dashboard's
/// view model or its Customize sheet.
class DashboardPanelMenuScope extends InheritedWidget {
  const DashboardPanelMenuScope({
    super.key,
    required this.onHide,
    required this.onCustomize,
    required super.child,
  });

  /// Switches the panel off (the same flag as the Customize sheet's switch).
  final VoidCallback onHide;

  /// Opens the Customize sheet on its Panels tab.
  final VoidCallback onCustomize;

  static DashboardPanelMenuScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardPanelMenuScope>();

  @override
  bool updateShouldNotify(DashboardPanelMenuScope oldWidget) =>
      oldWidget.onHide != onHide || oldWidget.onCustomize != onCustomize;
}

/// The panel's `⋮`: Hide, then Customize.
///
/// Muted (`ink3`) and small with a pointer so it reads as chrome beside the
/// card's title rather than as one of its actions; 44 px on touch.
class DashboardPanelMenuButton extends StatelessWidget {
  const DashboardPanelMenuButton({super.key, required this.scope});

  final DashboardPanelMenuScope scope;

  /// The button for the nearest scope, or nothing outside one.
  static Widget of(BuildContext context) {
    final scope = DashboardPanelMenuScope.maybeOf(context);
    return scope == null
        ? const SizedBox.shrink()
        : DashboardPanelMenuButton(scope: scope);
  }

  /// Pointer size: under the title row's line height plus its padding, so the
  /// header does not grow for it.
  static const double _pointerSide = 24;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final side = Env.isTouchPrimary ? InSizes.touchTarget : _pointerSide;
    return BackDismissibleMenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.visibility_off_outlined, size: 18),
          onPressed: scope.onHide,
          child: Text(context.tr('hide')),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.tune, size: 18),
          onPressed: scope.onCustomize,
          child: Text(context.tr('customize')),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: Icon(Icons.more_vert, size: 18, color: tokens.ink3),
        tooltip: context.tr('actions'),
        // Pinned exactly, as `EntityActionsPopupButton` explains: no
        // `visualDensity`, min / max cleared so `fixedSize` is the only input,
        // and `shrinkWrap` so the padded tap target does not re-inflate it.
        style: IconButton.styleFrom(
          fixedSize: Size(side, side),
          minimumSize: Size.zero,
          maximumSize: Size.infinite,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
