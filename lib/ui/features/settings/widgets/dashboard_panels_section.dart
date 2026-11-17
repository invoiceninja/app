import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/dashboard/helpers/hide_empty_panels.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';

/// Search keys for the settings sidebar search. Colocated with the row so
/// adding a field updates both ends in one place (see
/// `search_catalog_consistency_test`).
const kDashboardPanelsSearchKeys = <String>[
  'hide_empty_dashboard_panels',
  'hide_empty_panels_help',
];

/// Device Settings row for the "Hide empty panels" preference
/// (invoiceninja/flutter#161): leave a dashboard panel off the dashboard while
/// it has nothing to show, instead of rendering "No upcoming quotes".
///
/// The same controller as the switch in the dashboard's Customize → Panels
/// tab; this row is the one settings search can find. Here it says
/// "dashboard" in its own title (`hide_empty_dashboard_panels`), because it
/// shares a card with the list switches rather than sitting under a
/// Dashboard heading of its own.
///
/// **The switch shows the effective value**, not the stored one. Stored null
/// means automatic — on for a phone, off for a tablet or a desktop — so it is
/// resolved against this window through `effectiveIn`, the same helper the
/// dashboard uses. Flipping it to what this device would pick anyway goes
/// back to automatic; only a different answer is stored as an override.
///
/// The last row of Device Settings → Appearance → Lists & dashboard, above
/// the long Main menu cards, so on a phone, the device the default is for,
/// it is in reach.
class HideEmptyPanelsTile extends StatelessWidget {
  const HideEmptyPanelsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<Services>().hideEmptyPanels;
    return ValueListenableBuilder<bool?>(
      valueListenable: controller,
      builder: (context, _, _) => SettingRow.toggle(
        icon: const Icon(Icons.dashboard_customize_outlined),
        title: context.tr('hide_empty_dashboard_panels'),
        subtitle: context.tr('hide_empty_panels_help'),
        value: controller.effectiveIn(context),
        onChanged: (value) => controller.setIn(context, value),
      ),
    );
  }
}
