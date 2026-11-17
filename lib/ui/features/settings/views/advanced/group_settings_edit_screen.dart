import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/group_settings/group_setting_actions.dart'
    show kGroupSettingsBasePath;
import 'package:admin/ui/features/settings/view_models/group_setting_edit_view_model.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/settings_entity_edit_scaffold.dart';
import 'package:admin/ui/features/settings/widgets/settings_text_field.dart';

/// `/settings/group_settings/new` and `/settings/group_settings/:id/edit`.
///
/// Like React and the legacy app, the only field edited directly on the
/// group is its **name** — every cascade setting (currency, language,
/// country, …) is configured through "Configure Settings" on the group's
/// record screen (`GroupSettingsDetailScreen`), which switches the settings
/// shell into group scope.
///
/// **A create lands on the new group's record screen**, whose Overview tab
/// is where a fresh pane opens: the group exists so its settings can be set,
/// and that tab is where Configure Settings is. Online the create has
/// usually synced by the time `save()` returns, so the route takes the
/// server id; offline it takes the `tmp_` id and the record's row watch
/// follows the remap when the create drains. An edit goes back to the
/// record it came from.
class GroupSettingsEditScreen extends StatelessWidget {
  const GroupSettingsEditScreen({this.existingId, super.key});

  final String? existingId;

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    final repo = services.groupSettings;
    final id = existingId;

    return SettingsEntityEditScaffold<GroupSetting, GroupSettingEditViewModel>(
      existingId: id,
      backRoute: id == null
          ? kGroupSettingsBasePath
          : '$kGroupSettingsBasePath/$id',
      createTitleKey: 'new_group',
      editTitleKey: 'edit_group',
      wireName: 'group',
      watchById: (id) => repo.watch(companyId: companyId, id: id),
      refreshAll: () => repo.refreshAll(companyId: companyId),
      onArchive: (id) => repo.archive(companyId: companyId, id: id),
      onRestore: (id) => repo.restore(companyId: companyId, id: id),
      onDelete: (id) => repo.delete(companyId: companyId, id: id),
      vmFactory: ({existing}) => GroupSettingEditViewModel(
        repo: repo,
        companyId: companyId,
        existing: existing,
        sync: services.sync,
        connectivity: services.connectivity,
      ),
      isArchivedOf: (g) => g.archivedAt != null,
      isDeletedOf: (g) => g.isDeleted,
      // Gated on `isSaving` (mutually exclusive submits), `isDirty` (a no-op
      // save would still enqueue an outbox row and bump `updated_at`), and a
      // valid name — the server requires `name` present + unique on create.
      canSave: (vm) => !vm.isSaving && vm.isDirty && vm.nameIsValid,
      onCreated: (context, saved) async {
        final landed = await repo.resolveId(saved.id);
        if (!context.mounted) return;
        context.go('$kGroupSettingsBasePath/$landed');
      },
      bodyBuilder: (context, vm) => [
        FormSection(
          title: context.tr('group'),
          children: [
            SettingsTextField(
              initialValue: vm.draft.name,
              labelKey: 'name',
              onChanged: vm.setName,
              // Server 422 on `name` wins; otherwise the client-side
              // duplicate check (create-only) renders inline. A blank name
              // shows no error — the disabled Save button is the cue.
              errorText:
                  vm.fieldErrorFor('name') ??
                  (vm.nameErrorKey == null
                      ? null
                      : context.tr(vm.nameErrorKey!)),
              externalSyncKey: vm.original?.id,
            ),
          ],
        ),
      ],
    );
  }
}
