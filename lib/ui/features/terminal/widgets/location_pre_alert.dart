import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';

/// The app's own words before iOS asks for location (never a prompt out of
/// nowhere): Continue lets iOS ask, Cancel doesn't. Shared by the collect
/// screen's button and the enable screen.
class LocationPreAlertDialog extends StatelessWidget {
  const LocationPreAlertDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('terminal_location_prealert_title')),
    content: Text(
      context.tr('terminal_location_prealert', {
        'name': tapToPayNameFor(context, 'terminal_location_prealert'),
      }),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(context.tr('cancel')),
      ),
      PrimaryDialogAction(
        label: context.tr('continue'),
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
}
