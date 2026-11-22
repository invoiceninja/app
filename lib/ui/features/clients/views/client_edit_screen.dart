import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/edit/after_save_create_action.dart';
import 'package:admin/ui/core/edit/edit_action_filter.dart';
import 'package:admin/ui/core/edit/carry_edit_entities.dart';
import 'package:admin/ui/core/edit/entity_edit_screen_scaffold.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';
import 'package:admin/ui/features/clients/widgets/client_actions.dart';
import 'package:admin/ui/features/clients/widgets/client_limit.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_layout.dart';

/// Edit + Create form for a Client. The outer scaffold owns VM lifecycle,
/// the loading-state Scaffold, dead-outbox-row 422 recovery, and post-save
/// cleanup. This widget only contributes the per-entity wiring: how to
/// fetch the existing row, how to build the VM, the title, and the form
/// body.
class ClientEditScreen extends StatelessWidget {
  const ClientEditScreen({
    this.existingId,
    this.cloneFrom,
    this.addContact = false,
    super.key,
  });

  final String? existingId;

  /// Edit-mode override draft. Null for a normal edit and for create (which
  /// reads the staged draft via `Services.takeCreateDraft`). A group's Clients
  /// tab → "New client" stages a draft pre-assigned to that group.
  final Client? cloneFrom;

  /// Open an existing client on a new blank contact, scrolled into view — the
  /// record screen's Contacts card "+ Add" (`AddContactRequest`).
  final bool addContact;

  ClientEditViewModel _buildVm(
    BuildContext ctx,
    Services services,
    String companyId,
    Client? existing,
  ) => ClientEditViewModel(
    repo: services.clients,
    companyId: companyId,
    existing: existing,
    cloneFrom:
        cloneFrom ??
        (existing == null
            ? services.takeCreateDraft<Client>('/clients')
            : null),
    useCommaAsDecimalPlace:
        services.formatterIfReady(companyId)?.settings.useCommaAsDecimalPlace ??
        false,
    sync: services.sync,
    connectivity: services.connectivity,
  );

  @override
  Widget build(BuildContext context) {
    return EntityEditScreenScaffold<Client, ClientEditViewModel>(
      existingId: existingId,
      entityTypeName: 'client',
      fetchExisting: (ctx, services, companyId, id) =>
          services.clients.watch(companyId: companyId, id: id).first,
      buildVm: (ctx, services, companyId, existing) => _withRequestedContact(
        _buildVm(ctx, services, companyId, existing),
        existing,
      ),
      // A stay-in-editor Save reloads without the requested blank contact,
      // which the saved record already settled (docs/after-saving.md).
      reloadVm: _buildVm,
      titleWhileLoading: (ctx) =>
          existingId == null ? ctx.tr('new_client') : ctx.tr('edit'),
      titleBuilder: (ctx, vm) {
        if (vm.isCreate) return ctx.tr('new_client');
        final displayName = vm.draft.displayName.isNotEmpty
            ? vm.draft.displayName
            : vm.draft.name;
        return displayName.isNotEmpty
            ? '${ctx.tr('edit')} · $displayName'
            : ctx.tr('edit');
      },
      bodyBuilder: (ctx, vm) => ClientEditLayout(vm: vm),
      // The hosted Free plan's client cap: at it on a create, or a save the
      // server refused for it (docs/free-plan-limits.md).
      bannerBuilder: (ctx, vm) => ClientLimitFormBanner(vm: vm),
      // A way onto a blank form that skipped the gate (a deep link, the
      // command palette, a draft restored offline) must not queue a create
      // the server will refuse: Save opens the Upgrade dialog instead, and
      // the form keeps what was typed.
      confirmSave: confirmNewClientSave,
      resetToEmpty: (vm) => vm.resetToEmpty(),
      entityIdOf: (c) => c.id,
      actionsBuilder: (ctx, vm, onTap, saveButton) =>
          EntityOverflowActionBar<ClientAction>(
            leading: saveButton,
            items: filterForEditScreen(
              ClientActions.itemsFor(ctx, vm.draft, (a) => onTap(a)),
              isCreate: vm.isCreate,
              isLifecycle: ClientActions.isLifecycle,
            ),
          ),
      onAfterSaveAction: (ctx, saved, a) {
        final services = ctx.read<Services>();
        return ClientActions.dispatch(
          ctx,
          services,
          services.auth.session.value!.currentCompanyId,
          saved,
          a as ClientAction,
        );
      },
      // Create-mode: resolve the tmp id to the real one so View Statement keeps
      // its navigation instead of the detail redirect.
      onAfterSaveActionOnCreate: (ctx, saved, a) {
        final services = ctx.read<Services>();
        final companyId = services.auth.session.value!.currentCompanyId;
        return dispatchAfterSaveOnCreate<Client, ClientAction>(
          ctx,
          saved: saved,
          idOf: (client) => client.id,
          withId: (client, id) => client.copyWith(id: id),
          resolveId: services.clients.resolveId,
          action: a as ClientAction,
          navigatesOnCreate: ClientActions.navigatesOnCreate,
          dispatch: (c, resolved, act) =>
              ClientActions.dispatch(c, services, companyId, resolved, act),
        );
      },
      basePath: '/clients',
      // An edit typed while a new record's create was out rides to the
      // record's editor, over the server's copy (docs/after-saving.md).
      carryEdit: carryClientEdit,
    );
  }

  /// [vm], with the blank contact [addContact] asked for — once: a
  /// stay-in-editor Save reloads through `reloadVm`, which skips it.
  ClientEditViewModel _withRequestedContact(
    ClientEditViewModel vm,
    Client? existing,
  ) {
    if (addContact && existing != null) vm.addContact();
    return vm;
  }
}
