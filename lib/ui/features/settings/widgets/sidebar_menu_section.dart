import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/domain/sidebar_menu.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/in_segmented.dart';
import 'package:admin/ui/features/settings/widgets/customize_menu_sheet.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';

/// Search keys for the settings sidebar search. Colocated with the section so
/// adding / renaming a field updates both ends in one place (see
/// `search_catalog_consistency_test`).
///
/// The layout option labels (`list` / `grid`) are deliberately absent: they are
/// values, not fields, and searching for a field surfaces the row that holds
/// both.
const kSidebarMenuSearchKeys = <String>[
  'main_menu',
  'main_menu_help',
  'layout',
  'menu_item_order',
  'menu_item_order_help',
  'customize',
];

/// Device Settings → Appearance → Main menu, its first card: how the
/// sidebar's nav block is laid out, and the order and visibility of its items
/// (invoiceninja/flutter#125).
///
/// The section's title and description are this card's; the counters card
/// after it (`SidebarCountersSection`) is title-less, so beside a wide page's
/// title column the two cards read as one section — what the rows *are*, then
/// what their numbers *count*.
class SidebarMenuSection extends StatelessWidget {
  const SidebarMenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<Services>().sidebarMenu;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => FormSection(
        title: context.tr('main_menu'),
        description: context.tr('main_menu_help'),
        flush: true,
        children: withSettingDividers([
          SettingRow(
            icon: const Icon(Icons.grid_view_outlined),
            title: context.tr('layout'),
            control: InSegmented<SidebarMenuLayout>(
              segments: [
                for (final layout in SidebarMenuLayout.values)
                  InSegment(
                    value: layout,
                    label: context.tr(_layoutLabelKey(layout)),
                    icon: _layoutIcon(layout),
                  ),
              ],
              selected: controller.layout,
              onChanged: controller.setLayout,
            ),
          ),
          SettingRow(
            icon: const Icon(Icons.reorder),
            // Never the bundled `order`: that key is the invoicing noun and is
            // translated as the *purchase order* in ten locales (de
            // "Bestellung", fr "Commande", nl "Bestelling", ja "発注"), so
            // this row would read as a purchase-order setting sitting next to
            // Layout. An app-local key, machine-translated until Transifex
            // carries it.
            title: context.tr('menu_item_order'),
            subtitle: context.tr('menu_item_order_help'),
            stackWhenNarrow: false,
            control: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: () => openCustomizeMenu(context),
              child: Text(context.tr('customize')),
            ),
          ),
        ]),
      ),
    );
  }
}

String _layoutLabelKey(SidebarMenuLayout layout) => switch (layout) {
  SidebarMenuLayout.list => 'list',
  SidebarMenuLayout.grid => 'grid',
};

IconData _layoutIcon(SidebarMenuLayout layout) => switch (layout) {
  SidebarMenuLayout.list => Icons.view_list_outlined,
  SidebarMenuLayout.grid => Icons.grid_view_outlined,
};
