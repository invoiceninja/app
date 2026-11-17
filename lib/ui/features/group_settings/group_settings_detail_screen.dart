import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/build_standard_documents_tab.dart';
import 'package:admin/ui/core/detail/detail_tab_indices.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/detail/entity_detail_header.dart';
import 'package:admin/ui/core/detail/entity_detail_scaffold.dart';
import 'package:admin/ui/core/detail/entity_detail_tabs.dart';
import 'package:admin/ui/core/detail/entity_list_empty_action.dart';
import 'package:admin/ui/core/detail/entity_quick_actions.dart';
import 'package:admin/ui/core/detail/entity_record_column.dart';
import 'package:admin/ui/core/detail/entity_state_banner.dart';
import 'package:admin/ui/core/detail/generic_detail_view_model.dart';
import 'package:admin/ui/core/detail/record_screen_controller.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/detail/standing_card.dart';
import 'package:admin/ui/core/list/embedded_list_parent_scope.dart';
import 'package:admin/ui/core/sync/require_synced.dart';
import 'package:admin/ui/core/widgets/formatter_host_mixin.dart';
import 'package:admin/ui/features/clients/views/client_list_screen.dart';
import 'package:admin/ui/features/group_settings/group_setting_actions.dart';
import 'package:admin/ui/features/group_settings/group_setting_overrides.dart';
import 'package:admin/ui/features/group_settings/group_settings_overview.dart';

/// `/settings/group_settings/:id` — a group's record screen, on the record
/// layout (`docs/detail-screen-layout.md`): its name, the Configure Settings
/// tile, a standing card of how many clients it holds and how many settings
/// it overrides, above a pinned strip of Overview / Clients / Documents.
///
/// **Overview leads and is where a fresh pane lands** — it is what a group
/// is for: the settings it overrides, by page, with their values
/// (`GroupSettingsOverview`). A new group is saved straight onto it
/// (`GroupSettingsEditScreen`), under its `tmp_` id while offline; the row
/// watch follows the id remap when the create syncs.
///
/// The name — the only field on the group itself — is edited at `…/edit`.
class GroupSettingsDetailScreen extends StatefulWidget {
  const GroupSettingsDetailScreen({required this.id, super.key});

  final String id;

  @override
  State<GroupSettingsDetailScreen> createState() =>
      _GroupSettingsDetailScreenState();
}

class _GroupSettingsDetailScreenState extends State<GroupSettingsDetailScreen>
    with FormatterHostMixin {
  late final GenericDetailViewModel<GroupSetting> _vm;
  late final RecordScreenController _record;
  late final Services _services;
  late final String _companyId;

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    _companyId = _services.auth.session.value!.currentCompanyId;
    _vm = GenericDetailViewModel<GroupSetting>.bound(
      _services.groupSettings.watch(companyId: _companyId, id: widget.id),
    );
    _record = RecordScreenController(
      services: _services,
      companyId: _companyId,
      routeId: widget.id,
      entityWireName: 'group',
      refreshRecord: (id) => _services.groupSettings.refreshByIds(
        companyId: _companyId,
        ids: [id],
      ),
      hasRecord: () => _vm.item != null,
      // `ClientFilters::group_settings_id` — the key the embedded list sends.
      countFilterKey: 'group_settings_id',
      countFetchers: {DetailTabIds.clients: _services.clients.api.count},
    );
    // Documents are not in the `/login` bundle, and the list's delta refresh
    // skips a group already synced: a full sweep (include=documents) is what
    // brings this group's attachments down.
    unawaited(_refreshDocuments());
    loadFormatter(_services, _companyId);
  }

  /// Best effort: a failure leaves the documents the bundle already had.
  Future<void> _refreshDocuments() async {
    try {
      await _services.groupSettings.refreshAll(
        companyId: _companyId,
        full: true,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _record.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _dispatch(GroupSetting group, GroupSettingAction action) =>
      GroupSettingActions.dispatch(
        context,
        _services,
        _companyId,
        group,
        action,
      );

  /// Configure on one page — the Overview's per-section button, and its
  /// empty state. Null while the group cannot be configured, which draws
  /// them disabled; the banner above the page says why.
  void Function(String route)? _configureFor(GroupSetting g) =>
      isUnsynced(g.id) || g.isDeleted
      ? null
      : (route) => configureGroupSettings(context, _services, g, route: route);

  @override
  Widget build(BuildContext context) {
    return EntityDetailScaffold<GroupSetting>(
      id: widget.id,
      vm: _vm,
      hydrate: () => _services.groupSettings.ensureLoaded(
        companyId: _companyId,
        id: widget.id,
      ),
      emptyAction: entityListEmptyAction(context, EntityType.group),
      emptyIcon: Icons.group_work_outlined,
      emptyTitle: context.tr('group'),
      actionsForItem: (context, g) =>
          EntityDetailActionsRow<GroupSettingAction>(
            items: GroupSettingActions.itemsFor(
              context,
              g,
              (a) => _dispatch(g, a),
            ),
          ),
      compactTitleForItem: (context, g) => Text(
        _name(context, g),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: context.inTheme.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      // A deleted group is read-only until restored.
      isReadOnly: (g) => g.isDeleted,
      onRefresh: _record.refresh,
      bannerForItem: (context, g) => recordStateBanner<GroupSettingAction>(
        context,
        items: GroupSettingActions.itemsFor(context, g, (a) => _dispatch(g, a)),
        restoreKind: GroupSettingAction.restore,
        entityId: g.id,
        isDeleted: g.isDeleted,
        archivedAt: g.archivedAt,
        formatter: formatter,
      ),
      bodyBuilder: _body,
    );
  }

  static String _name(BuildContext context, GroupSetting g) =>
      g.name.trim().isEmpty ? context.tr('untitled') : g.name;

  Widget _body(BuildContext context, GroupSetting g) {
    _record.attach(
      recordId: g.id,
      revision: g.updatedAt,
      tabIds: const {DetailTabIds.clients},
    );
    final overrides = overriddenSettingKeys(g.settings).length;
    final clients = _record.countFor(DetailTabIds.clients);
    final top = EntityRecordColumn(
      header: EntityDetailHeader(
        seedForAvatar: g.id,
        displayName: _name(context, g),
        createdAt: g.createdAt,
        updatedAt: g.updatedAt,
        isDeleted: g.isDeleted,
        isArchived: g.archivedAt != null,
        isDirty: g.isDirty,
        formatter: formatter,
        fallbackIcon: Icons.group_work_outlined,
        nameMaxLines: 2,
        // The banner above the page already says Deleted / Archived.
        showStatePills: !g.isDeleted && g.archivedAt == null,
        subtitle: DetailSubtitle(segments: [Text(context.tr('group'))]),
      ),
      quickActions: EntityQuickActions<GroupSettingAction>(
        priority: GroupSettingActions.quickItemsFor(
          context,
          g,
          (a) => _dispatch(g, a),
        ),
      ),
      standing: StandingCard(
        primary: [
          StandingFigure(
            label: context.tr('clients'),
            // A server total; blank (not zero) until it is known.
            value: clients == null ? '' : '$clients',
            copyable: false,
            onTap: () => _record.selectTab.selectId(DetailTabIds.clients),
            semanticsHint: context.tr('clients'),
          ),
          StandingFigure(
            label: context.tr('settings'),
            value: '$overrides',
            copyable: false,
            onTap: () => _record.selectTab.selectId(DetailTabIds.overview),
            semanticsHint: context.tr('overview'),
          ),
        ],
      ),
      timestamps: RecordTimestampsLine(
        createdAt: g.createdAt,
        updatedAt: g.updatedAt,
        formatter: formatter,
      ),
    );
    // The scope tells the embedded clients list what it cannot know from a
    // group id alone: that the group is deleted (no New), or not yet synced.
    return EmbeddedListParentScope(
      parentId: g.id,
      readOnly: g.isDeleted,
      intents: _record.listIntents,
      child: ListenableBuilder(
        // A count lands after the strip is on screen.
        listenable: _record,
        builder: (context, _) => EntityDetailTabs(
          selectTab: _record.selectTab,
          onReveal: _record.page.revealTabs,
          layoutBuilder: (context, strip, body) =>
              _record.buildPage(strip: strip, body: body, top: top),
          tabs: [
            EntityDetailTab(
              id: DetailTabIds.overview,
              label: context.tr('overview'),
              icon: Icons.tune_outlined,
              bodyBuilder: (_) => Padding(
                padding: EdgeInsets.all(InSpacing.lg(context)),
                child: GroupSettingsOverview(
                  group: g,
                  companyId: _companyId,
                  formatter: formatter,
                  onConfigure: _configureFor(g),
                ),
              ),
            ),
            EntityDetailTab(
              id: DetailTabIds.clients,
              count: _record.countFor(DetailTabIds.clients),
              label: context.tr('clients'),
              icon: Icons.people_outline,
              // Keyed on the group's id: a list builds its view model once,
              // with the id it was first given, and a group opened while
              // still `tmp_…` comes back through here with its server id.
              bodyBuilder: (_) => KeyedSubtree(
                key: ValueKey<String>(g.id),
                child: ClientListScreen(groupSettingsId: g.id, embedded: true),
              ),
            ),
            buildStandardDocumentsTab(
              context: context,
              companyId: _companyId,
              entityId: g.id,
              documents: g.documents,
              repo: _services.groupSettings,
            ),
          ],
        ),
      ),
    );
  }
}
