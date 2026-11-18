import 'package:material_ui/material_ui.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/core/fold_geometry.dart';

/// Regions where Tap to Pay on iPhone has no PIN entry, so the education
/// leaves it out (the guide's Regional Requirements: "PIN Entry in
/// Education — all regions except JP, TW").
const Set<String> kNoPinEducationCountries = {'JP', 'TW'};

/// Apple's "How to Tap" merchant education for Tap to Pay on iPhone, which
/// App Review requires after the terms are accepted and wants reachable
/// after (docs/in-person-payments.md): Apple's own sheet on iOS 18+
/// (`ProximityReaderDiscovery`, which covers 4.4–4.8 itself), and below that
/// these instructions — contactless cards and digital wallets (4.5, 4.6),
/// PIN entry and the PIN screen's accessibility options except in Japan and
/// Taiwan (4.7, [accountCountry]: the Stripe account's country), and Apple's
/// own fallback copy, in every region. True when either was shown.
Future<bool> showHowToTap(
  BuildContext context, {
  String accountCountry = '',
}) async {
  if (await StripeTerminal.showHowToTap()) return true;
  if (!context.mounted) return false;
  final pin = !kNoPinEducationCountries.contains(accountCountry.toUpperCase());
  await showDialog<void>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    builder: (context) {
      String sentence(String key) =>
          context.tr(key, {'name': tapToPayNameFor(context, key)});
      return AlertDialog(
        title: Text(sentence('terminal_how_to_tap')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sentence('terminal_how_to_tap_steps')),
              if (pin) ...[
                const SizedBox(height: InSpacing.sm),
                Text(sentence('terminal_how_to_tap_pin')),
              ],
              const SizedBox(height: InSpacing.sm),
              Text(sentence('terminal_how_to_tap_fallback')),
            ],
          ),
        ),
        actions: [
          PrimaryDialogAction(
            label: context.tr('close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
  return true;
}
