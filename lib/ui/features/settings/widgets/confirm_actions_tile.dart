import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';

/// Settings → Device Settings → Security → Confirm actions toggle.
///
/// Device-local, on by default. When on, actions tagged
/// `EntityActionItem.confirm` (Approve, Mark Sent, Cancel, Send Now, Archive,
/// Delete, …) open an "Are you sure?" dialog first — see
/// invoiceninja/flutter#49, where users reported fat-fingering Approve and
/// Archive while working from a phone in the field.
class ConfirmActionsTile extends StatelessWidget {
  const ConfirmActionsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<Services>().confirmActions;
    return ValueListenableBuilder<bool>(
      valueListenable: controller,
      builder: (context, enabled, _) => SettingRow.toggle(
        icon: const Icon(Icons.help_outline),
        title: context.tr('confirm_actions'),
        subtitle: context.tr('confirm_actions_help'),
        value: enabled,
        onChanged: controller.set,
      ),
    );
  }
}
