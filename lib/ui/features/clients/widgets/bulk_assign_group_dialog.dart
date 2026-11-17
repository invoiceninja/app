import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/dialogs/bulk_pick_dialog.dart';
import 'package:admin/ui/core/widgets/entity_picker_field.dart';

/// Prep dialog for the client list's Assign Group bulk action (React's and
/// v1's, `POST /clients/bulk action:assign_group`): a searchable group
/// picker. Returns the picked group id, or null on cancel. The server
/// requires a group (`required_if:action,assign_group`), so there is no
/// "(none)" here — the single-client dialog keeps that.
Future<String?> showBulkAssignGroupDialog(BuildContext context) {
  final services = context.read<Services>();
  final companyId = services.auth.currentCompanyId ?? '';
  return showBulkPickDialog(
    context,
    titleKey: 'assign_group',
    pickerBuilder: (context, selectedId, onPicked) =>
        EntityPickerField<GroupSetting>(
          label: context.tr('group'),
          cacheKey: companyId,
          selectedId: selectedId,
          itemsStream: () =>
              services.groupSettings.watchAll(companyId: companyId),
          watchById: (id) =>
              services.groupSettings.watch(companyId: companyId, id: id),
          displayString: (g) =>
              g.name.isEmpty ? context.tr('untitled') : g.name,
          idOf: (g) => g.id,
          emptyHintKey: 'no_groups_yet',
          onChanged: (g) => onPicked(g?.id ?? ''),
        ),
  );
}
