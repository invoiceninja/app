import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:admin/app/router.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/copy_entity_link.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/detail/entity_quick_actions.dart';
import 'package:admin/ui/core/detail/standard_entity_action_items.dart';
import 'package:admin/ui/core/detail/standard_entity_actions.dart';
import 'package:admin/ui/core/sync/require_synced.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';

/// Where the group screens live.
const String kGroupSettingsBasePath = '/settings/group_settings';

/// The page "Configure Settings" opens on: the first page the narrowed
/// settings list offers at group scope, as the client's Settings action does.
const String kGroupSettingsLandingRoute = '/settings/localization';

/// What can be done to a group from its record screen.
enum GroupSettingAction {
  edit,
  configureSettings,
  copyLink,
  archive,
  restore,
  delete,
}

class GroupSettingActions {
  GroupSettingActions._();

  static String _subject(GroupSetting g) => g.name;

  static List<EntityActionItem<GroupSettingAction>> itemsFor(
    BuildContext context,
    GroupSetting group,
    void Function(GroupSettingAction) onTap,
  ) {
    final archived = group.archivedAt != null;
    return [
      editActionItem(
        context: context,
        kind: GroupSettingAction.edit,
        onTap: () => onTap(GroupSettingAction.edit),
      ),
      // The settings editor at group scope saves the group's own `settings`
      // through the outbox, but its pages also ask the server about the
      // scope (the live PDF preview, the gateway order) by the group's id —
      // which the server does not know until the create has synced. Disabled
      // with the reason until then, as the client's Settings action is.
      EntityActionItem(
        kind: GroupSettingAction.configureSettings,
        icon: Icons.tune,
        label: context.tr('configure_settings'),
        enabled: !isUnsynced(group.id) && !group.isDeleted,
        // A deleted group says why through the state banner instead.
        disabledTooltipKey: 'sync_first_generic',
        onTap: () => onTap(GroupSettingAction.configureSettings),
      ),
      ?copyLinkActionItem(
        context: context,
        kind: GroupSettingAction.copyLink,
        entityId: group.id,
        onTap: () => onTap(GroupSettingAction.copyLink),
      ),
      ?archiveActionItem(
        context: context,
        subject: _subject(group),
        kind: GroupSettingAction.archive,
        canArchive: !archived && !group.isDeleted,
        onTap: () => onTap(GroupSettingAction.archive),
      ),
      ?restoreActionItem(
        context: context,
        kind: GroupSettingAction.restore,
        canRestore: archived || group.isDeleted,
        onTap: () => onTap(GroupSettingAction.restore),
      ),
      ?deleteActionItem(
        context: context,
        subject: _subject(group),
        kind: GroupSettingAction.delete,
        canDelete: !group.isDeleted,
        onTap: () => onTap(GroupSettingAction.delete),
      ),
    ];
  }

  /// The record screen's one tile: Configure Settings, the thing a group is
  /// for. A second render of the item [itemsFor] built, so its disabled
  /// state and reason carry over. A deleted group is read-only and gets none.
  static List<EntityQuickAction<GroupSettingAction>> quickItemsFor(
    BuildContext context,
    GroupSetting group,
    void Function(GroupSettingAction) onTap,
  ) {
    if (group.isDeleted) return const [];
    final item = findActionItem<GroupSettingAction>(
      itemsFor(context, group, onTap),
      GroupSettingAction.configureSettings,
    );
    if (item == null) return const [];
    return [EntityQuickAction(item: item, shortLabel: context.tr('settings'))];
  }

  static Future<void> dispatch(
    BuildContext context,
    Services services,
    String companyId,
    GroupSetting group,
    GroupSettingAction action,
  ) async {
    switch (action) {
      case GroupSettingAction.edit:
        goEntityEdit(context, kGroupSettingsBasePath, group.id);
      case GroupSettingAction.configureSettings:
        configureGroupSettings(context, services, group);
      case GroupSettingAction.copyLink:
        await copyEntityLink(context, EntityType.group, group.id);
      case GroupSettingAction.archive:
        await StandardEntityActions.archive(
          context: context,
          wireName: 'group',
          op: () => services.groupSettings.archive(
            companyId: companyId,
            id: group.id,
          ),
          undoOp: () => services.groupSettings.restore(
            companyId: companyId,
            id: group.id,
          ),
        );
      case GroupSettingAction.restore:
        await StandardEntityActions.restore(
          context: context,
          wireName: 'group',
          op: () => services.groupSettings.restore(
            companyId: companyId,
            id: group.id,
          ),
        );
      case GroupSettingAction.delete:
        if (!requireSynced(context, group.id)) return;
        await StandardEntityActions.delete(
          context: context,
          wireName: 'group',
          op: () =>
              services.groupSettings.delete(companyId: companyId, id: group.id),
          undoOp: () => services.groupSettings.restore(
            companyId: companyId,
            id: group.id,
          ),
        );
    }
  }
}

/// Open the settings editor scoped to [group] — the same entry the client's
/// Settings action uses (`ClientAction.settings`): the settings list narrows
/// to the pages that apply below the company, the "Group Settings: `name`"
/// banner leads every page, and each field carries its override checkbox.
/// [route] picks the page; the Overview's per-section Configure passes its
/// section's.
void configureGroupSettings(
  BuildContext context,
  Services services,
  GroupSetting group, {
  String route = kGroupSettingsLandingRoute,
}) {
  if (!requireSynced(context, group.id)) return;
  services.settingsLevel.setLevel(
    SettingsLevel.group,
    targetId: group.id,
    targetName: group.name,
  );
  context.go(route);
}
