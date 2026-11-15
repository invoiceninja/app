import 'package:material_ui/material_ui.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_panel_pref.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_panel_menu.dart';
import 'package:admin/ui/features/dashboard/widgets/manage_dashboard_cards_sheet.dart';

/// Wraps the panel [kind] in its `⋮` menu (`DashboardPanelMenuScope`).
///
/// Hide writes the same flag as the Customize sheet's switch, so it syncs
/// through `company_user.settings` like any other panel change, and the toast says
/// where to turn it back on — with an Undo for the tap that was a slip.
Widget withDashboardPanelMenu(
  BuildContext context, {
  required DashboardViewModel vm,
  required String kind,
  required Widget child,
}) => DashboardPanelMenuScope(
  onHide: () => hideDashboardPanel(context, vm: vm, kind: kind),
  onCustomize: () =>
      openManageDashboardCards(context, vm: vm, initialTab: ManagePane.panels),
  child: child,
);

void hideDashboardPanel(
  BuildContext context, {
  required DashboardViewModel vm,
  required String kind,
}) {
  vm.setPanelVisible(kind, false);
  Notify.info(
    context,
    context.tr('panel_hidden', {'panel': context.tr(panelTitleKey(kind))}),
    detail: context.tr('show_panel_again_in_customize'),
    action: NotifyAction(
      context.tr('undo'),
      () => vm.setPanelVisible(kind, true),
    ),
  );
}
