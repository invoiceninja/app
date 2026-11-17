import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/router.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/db/dao/payment_link_dao.dart';
import 'package:admin/data/models/domain/payment_link.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/quick_create.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/list/entity_sort_filter_sheet.dart';
import 'package:admin/ui/core/list/master_detail_layout.dart';
import 'package:admin/ui/core/list/no_match_actions.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';
import 'package:admin/ui/features/payment_links/view_models/payment_link_list_view_model.dart';
import 'package:admin/ui/features/payment_links/widgets/payment_link_actions.dart';
import 'package:admin/ui/features/payment_links/widgets/payment_link_list_tile.dart';
import 'package:admin/ui/features/payment_links/widgets/payment_link_token_search_field.dart';
import 'package:admin/ui/features/settings/widgets/no_gateway_warning.dart';
import 'package:admin/ui/features/settings/widgets/plan_gate_banner.dart';

/// Labels surfaced on the list screen for the in-app settings search
/// index. Mirrors the convention from other settings screens (e.g.
/// `kCompanyDetailsDetailsSearchKeys`): only the **fields actually
/// rendered** by this screen. Section title (`payment_links`) and
/// affordance labels (`new_payment_link`) live on the
/// `SettingsSectionDef` / `EntityModuleSpec` configs and don't need
/// duplicate entries here.
const kPaymentLinksListSearchKeys = <String>[
  'name',
  'price',
  'purchase_page',
  'last_updated',
];

/// `/settings/payment_links` — Payment Links list. Reached only from the
/// Settings sidebar (Settings → Advanced). Mirrors
/// [ExpenseCategoryListScreen] — uses the canonical
/// [EntityListScreenScaffold] for chrome and renders each row via
/// [PaymentLinkListTile] so the visual vocabulary matches every other
/// settings list.
class PaymentLinkListScreen extends StatelessWidget {
  const PaymentLinkListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<Services>().auth.session.value;
    final hasAccess = session?.hasProAccess ?? false;
    final me = session?.currentCompany;
    final mayCreate = mayCreateEntity(
      EntityType.paymentLink,
      can: (p) => me?.can(p) ?? false,
      isAdmin: me?.isAdmin == true || me?.isOwner == true,
    );
    return EntityListScreenScaffold<PaymentLink, PaymentLinkListViewModel>(
      titleKey: 'payment_links',
      newRoute: '/settings/payment_links/new',
      newLabelKey: 'new_payment_link',
      // Default "Price" column renders via cellMoney (company currency) and
      // the opt-in "Last Updated" via cellDate — both need FormatterScope.
      wantsFormatter: true,
      // The first-run state explains what a link is for and offers the
      // create button by name — the unlabelled FAB was the only way in. A
      // filtered list that matched nothing keeps the scaffold's own copy.
      emptyStateBuilder: (context, vm) => vm.hasActiveFilters
          ? EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: context.tr('no_records_found'),
              action: NoMatchActions(vm: vm),
            )
          : EmptyState(
              icon: Icons.link_outlined,
              title: context.tr('payment_links_empty'),
              subtitle: context.tr('payment_links_empty_help'),
              action: hasAccess && mayCreate
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 44),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('new_payment_link')),
                      onPressed: () =>
                          context.go('/settings/payment_links/new'),
                    )
                  : null,
            ),
      // Each bar hides itself when it has nothing to say.
      headerBanner: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PlanGateBanner(style: PlanGateStyle.stripe),
          NoGatewayWarning(
            messageKey: 'payment_links_need_gateway',
            style: NoGatewayWarningStyle.stripe,
          ),
        ],
      ),
      canCreate: hasAccess,
      buildVm: (services, companyId) => PaymentLinkListViewModel(
        repo: services.paymentLinks,
        companyId: companyId,
        navStateDao: services.db.navStateDao,
        userSettings: services.userSettings,
        savedViews: services.savedViews,
      ),
      sortOptions: (context) => [
        SortOption(id: PaymentLinkFieldIds.name, label: context.tr('name')),
        SortOption(id: PaymentLinkFieldIds.price, label: context.tr('price')),
        SortOption(
          id: PaymentLinkFieldIds.updatedAt,
          label: context.tr('last_updated'),
        ),
      ],
      // Nothing to search until a link exists: an empty company saw a
      // search box over "No payment links yet". A typed search or a filter
      // keeps it, so the user can always clear what they set.
      searchFieldBuilder: (context, vm, wide) =>
          vm.items.isEmpty &&
              !vm.hasActiveFilters &&
              !vm.isLoadingPage &&
              !vm.refillPending
          ? const SizedBox.shrink()
          : PaymentLinkTokenSearchField(vm: vm, wide: wide),
      tileBuilder: (context, vm, paymentLink, index, options) {
        final isUrlSelected = options.selectedId == paymentLink.id;
        return PaymentLinkListTile(
          paymentLink: paymentLink,
          columns: options.wide ? vm.columns : const [],
          wide: options.wide,
          editable: options.editable,
          hideBottomDivider: options.bottomDividerHidden,
          selecting: options.selecting,
          selected: vm.isSelected(paymentLink.id) || isUrlSelected,
          urlSelected: isUrlSelected,
          onTap: options.selecting
              ? () => vm.toggleSelected(paymentLink.id)
              : isUrlSelected
              ? () => MasterDetailNavScope.requestClose(
                  context,
                  basePath: '/settings/payment_links',
                )
              : () => goEntityRecord(context, vm.entityType, paymentLink.id),
          onLongPress: () => vm.toggleSelected(paymentLink.id),
          onSelectTap: () => vm.toggleSelected(paymentLink.id),
          onAction: options.selecting
              ? null
              : (action) => PaymentLinkActions.dispatch(
                  context,
                  context.read<Services>(),
                  vm.companyId,
                  paymentLink,
                  action,
                ),
        );
      },
      bulkActions: const [
        EntityListBulkAction(
          actionId: 'archive',
          icon: Icons.archive_outlined,
          tooltipKey: 'archive',
          singleSuccessKey: 'archived_payment_link',
          pluralSuccessKey: 'archived_payment_links',
          nothingKey: 'nothing_to_archive',
        ),
        EntityListBulkAction(
          actionId: 'restore',
          icon: Icons.unarchive_outlined,
          tooltipKey: 'restore',
          singleSuccessKey: 'restored_payment_link',
          pluralSuccessKey: 'restored_payment_links',
          nothingKey: 'nothing_to_restore',
        ),
        EntityListBulkAction(
          actionId: 'delete',
          icon: Icons.delete_outline,
          tooltipKey: 'delete',
          singleSuccessKey: 'deleted_payment_link',
          pluralSuccessKey: 'deleted_payment_links',
          nothingKey: 'nothing_to_delete',
        ),
      ],
    );
  }
}
