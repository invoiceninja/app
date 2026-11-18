import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/core/fold_geometry.dart';

/// Builds the one picker a [showBulkPickDialog] holds: render [selectedId]
/// and report each pick through [onPicked] (an empty id = nothing picked).
typedef BulkPickerBuilder =
    Widget Function(
      BuildContext context,
      String selectedId,
      ValueChanged<String> onPicked,
    );

/// The prep dialog of a "set one related record on every selected row" bulk
/// action — Change Category on expenses, Assign Group on clients: one
/// searchable picker and a Save that stays disabled until something is
/// picked. Returns the picked id, or null on cancel.
///
/// A blank pick is never returned: each of these server actions requires a
/// real id (`categorize(int)`, `group_settings_id required_if`), so clearing
/// the relation stays a job for the record's edit screen, as in React.
Future<String?> showBulkPickDialog(
  BuildContext context, {
  required String titleKey,
  required BulkPickerBuilder pickerBuilder,
}) => showDialog<String>(
  context: context,
  anchorPoint: foldAnchorPoint(context),
  builder: (_) =>
      BulkPickDialog(titleKey: titleKey, pickerBuilder: pickerBuilder),
);

class BulkPickDialog extends StatefulWidget {
  const BulkPickDialog({
    super.key,
    required this.titleKey,
    required this.pickerBuilder,
  });

  final String titleKey;
  final BulkPickerBuilder pickerBuilder;

  @override
  State<BulkPickDialog> createState() => _BulkPickDialogState();
}

class _BulkPickDialogState extends State<BulkPickDialog> {
  String _selectedId = '';

  bool get _canSubmit => _selectedId.isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_selectedId);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(widget.titleKey)),
      content: SizedBox(
        width: 380,
        child: widget.pickerBuilder(
          context,
          _selectedId,
          (id) => setState(() => _selectedId = id),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('cancel')),
            ),
            SizedBox(width: InSpacing.md(context)),
            PrimaryDialogAction(
              label: context.tr('save'),
              enabled: _canSubmit,
              // The one input is a picker and the primary starts disabled —
              // Enter can reach neither (docs/buttons-and-spacing.md).
              autofocus: false,
              showEnterHint: false,
              onPressed: _submit,
            ),
          ],
        ),
      ],
    );
  }
}
