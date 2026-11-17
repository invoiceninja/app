import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/scroll_edge_fades.dart';

/// The start inset of every settings [TabBar] (`padding:`): with Material's
/// 16 px label padding it puts the first label at [InSpacing.xl], the edge of
/// the content `SettingsFormShell` lays out under it. A strip that narrows its
/// label padding passes [settingsTabBarPadding] its own.
EdgeInsetsGeometry settingsTabBarPadding({double labelPadding = 16}) =>
    EdgeInsetsDirectional.only(start: InSpacing.xl - labelPadding);

/// A settings page's tab strip: the [tabBar] — start-aligned, scrollable —
/// under edge fades that say when a tab runs past the pane (R5 / D5 of the
/// settings pass). A [PreferredSizeWidget], so it drops into an `AppBar`'s
/// `bottom:` as the bare [TabBar] did; it works in a `Column` too.
///
/// [color] is the surface behind the strip, which the fades dissolve into:
/// the AppBar's background by default. A strip in a page body passes the
/// scaffold's.
class SettingsTabStrip extends StatelessWidget implements PreferredSizeWidget {
  const SettingsTabStrip({super.key, required this.tabBar, this.color});

  /// Built with `isScrollable: true` and `tabAlignment: TabAlignment.start` —
  /// `start` asserts on a non-scrollable bar, so it can't live in the theme.
  final TabBar tabBar;
  final Color? color;

  @override
  Size get preferredSize => tabBar.preferredSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScrollEdgeFades(
      color:
          color ??
          theme.appBarTheme.backgroundColor ??
          theme.colorScheme.surface,
      child: tabBar,
    );
  }
}
