import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';

/// The wide dashboard's Refresh: a small icon button at the end of the
/// freshness line under the company's name (issue #26 — the stamp used to sit
/// at the very bottom of the scroll, so refreshing meant scrolling past every
/// card and back).
///
/// It sits beside the stamp it renews rather than among the header's actions:
/// those are about making things, and a labelled Refresh there was one more
/// equal-weight button between the user and New Invoice.
///
/// **The glyph swaps to a spinner while a pass is in flight**, and the button
/// is disabled — the app's established vocabulary (`SidebarSyncButton`, the
/// entity-edit Save button) — and its extent never changes, so an in-flight
/// refresh cannot reflow the line under the user's cursor.
///
/// **24 px with a pointer, 44 px on touch** (`docs/touch-targets.md`). The
/// density is pinned to `standard`: the desktop theme's `compact` takes 8 px
/// off an `IconButton`'s explicit constraints, which would make the pointer
/// size 16. The tooltip is also the button's screen-reader label, and it
/// scopes this against the sidebar's one-tap Sync, which re-downloads every
/// entity — this only refetches the dashboard's own sections.
class DashboardRefreshButton extends StatelessWidget {
  const DashboardRefreshButton({
    super.key,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final bool isRefreshing;
  final VoidCallback onRefresh;

  /// The square the button occupies.
  static double extent() => Env.isTouchPrimary ? InSizes.touchTarget : 24;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final size = extent();
    return IconButton(
      tooltip: context.tr('refresh_dashboard_data'),
      onPressed: isRefreshing ? null : onRefresh,
      iconSize: 16,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        foregroundColor: tokens.ink2,
        disabledForegroundColor: tokens.ink3,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InRadii.r1),
        ),
      ),
      icon: isRefreshing
          ? const RepaintBoundary(
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            )
          : const Icon(Icons.refresh),
    );
  }
}
