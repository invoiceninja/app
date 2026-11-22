import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/desktop_app_promo.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/mobile_promo/desktop_app_promo_dialog.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';

/// Search keys for the settings sidebar search, colocated with the section
/// (see `search_catalog_consistency_test`).
const kDesktopAppSearchKeys = <String>[
  'desktop_app_promo_section',
  'desktop_app_promo_settings_body',
  'desktop_app_promo_entry',
];

/// Whether [DesktopAppSection] renders for [session] on this platform — and
/// so whether settings search offers its keys.
bool desktopAppSectionShown(AuthSession? session) =>
    currentDesktopPromoTargets().isNotEmpty && desktopPromoEligible(session);

/// Device Settings card for the desktop app — the desktop-app promo's
/// permanent home on a phone (docs/desktop-app-promo.md), the mirror of
/// `MobileAppSection`, which renders everywhere else.
class DesktopAppSection extends StatelessWidget {
  const DesktopAppSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!desktopAppSectionShown(context.read<Services>().auth.session.value)) {
      return const SizedBox.shrink();
    }
    return FormSection(
      title: context.tr('desktop_app_promo_section'),
      description: context.tr('desktop_app_promo_settings_body'),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () =>
                unawaited(showDesktopAppPromoDialog(context, isManual: true)),
            icon: const Icon(Icons.laptop_outlined, size: 18),
            label: Text(context.tr('desktop_app_promo_entry')),
          ),
        ),
      ],
    );
  }
}
