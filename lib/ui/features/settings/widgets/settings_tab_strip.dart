import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/scroll_edge_fades.dart';

/// A settings page's title bar — the AppBar's toolbar — and, on the wide
/// layout, the settings nav's "Settings" title row beside it, so the two
/// titles share a line.
const double kSettingsTitleBarHeight = kToolbarHeight;

/// A settings tab strip, its hairline included — Material's 46 px text tab
/// plus the 2 px indicator — and, on the wide layout, the nav's search row
/// beside it.
const double kSettingsTabStripHeight = 48;

/// The header block above the rule on a wide settings page: title bar plus
/// tab strip, the rule being its last pixel. The settings nav's title + search
/// block is this tall too, so the line under "Search Settings" and the line
/// under a page's tabs land on the same y (`settings_header_rule_test`).
const double kSettingsHeaderHeight =
    kSettingsTitleBarHeight + kSettingsTabStripHeight;

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

  /// Fixed rather than read off [tabBar], so the rule under the strip can't
  /// drift from the nav's beside it (a text tab with a 2 px indicator is this
  /// height anyway).
  @override
  Size get preferredSize => const Size.fromHeight(kSettingsTabStripHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScrollEdgeFades(
      color:
          color ??
          theme.appBarTheme.backgroundColor ??
          theme.colorScheme.surface,
      child: SizedBox(height: kSettingsTabStripHeight, child: tabBar),
    );
  }
}
