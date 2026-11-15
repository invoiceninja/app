import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';

/// The app's own words before iOS asks for location (never a prompt out of
/// nowhere): Continue lets iOS ask, Cancel doesn't. Shared by the collect
/// screen's button and the enable screen, and drawn in their language: the
/// tinted tile, the headline, a supporting line.
class LocationPreAlertDialog extends StatelessWidget {
  const LocationPreAlertDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Center(
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(InRadii.r3),
          ),
          child: Icon(
            Icons.location_on_outlined,
            size: 28,
            color: tokens.accentInk,
          ),
        ),
      ),
      title: Text(
        context.tr('terminal_location_prealert_title'),
        textAlign: TextAlign.center,
        style: text.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        context.tr('terminal_location_prealert', {
          'name': tapToPayNameFor(context, 'terminal_location_prealert'),
        }),
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(
          fontSize: 15,
          color: tokens.ink2,
          height: 1.45,
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
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
}
