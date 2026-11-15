import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';

/// Apple's "How to Tap" merchant education for Tap to Pay on iPhone, which
/// App Review requires before the first payment and wants reachable after
/// (docs/in-person-payments.md): Apple's own sheet on iOS 18+, and these
/// instructions where it can't be shown.
Future<void> showHowToTap(BuildContext context) async {
  if (await StripeTerminal.showHowToTap()) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('terminal_how_to_tap')),
      content: Text(context.tr('terminal_how_to_tap_steps')),
      actions: [
        PrimaryDialogAction(
          label: context.tr('close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
