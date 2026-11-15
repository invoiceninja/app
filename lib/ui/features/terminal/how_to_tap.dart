import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';

/// Apple's "How to Tap" merchant education for Tap to Pay on iPhone, which
/// App Review requires after the terms are accepted and wants reachable
/// after (docs/in-person-payments.md): Apple's own sheet on iOS 18+, and
/// these instructions where it can't be shown. True when either was shown.
Future<bool> showHowToTap(BuildContext context) async {
  if (await StripeTerminal.showHowToTap()) return true;
  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        context.tr('terminal_how_to_tap', {
          'name': tapToPayNameFor(context, 'terminal_how_to_tap'),
        }),
      ),
      content: Text(context.tr('terminal_how_to_tap_steps')),
      actions: [
        PrimaryDialogAction(
          label: context.tr('close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
  return true;
}
