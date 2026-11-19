import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/external_url.dart';

/// Invoice Ninja's privacy policy and terms of service, the pages the hosted
/// landing page links (`tools/web_deploy/landing/apps.json`).
const String kPrivacyPolicyUrl = 'https://invoiceninja.com/privacy-policy/';
const String kTermsOfServiceUrl = 'https://invoiceninja.com/terms/';

/// The privacy policy and terms of service as two buttons that open in the
/// browser. The App Store wants both reachable inside the app (App Review
/// 5.1.1(i), and 3.1.2 wherever a subscription is sold), and a link inside a
/// sentence is too small to hit with a finger, so each is a button of its own.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.alignment = WrapAlignment.start});

  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      children: [
        TextButton(
          key: const ValueKey('legal_privacy_policy'),
          onPressed: () => launchExternalUri(Uri.parse(kPrivacyPolicyUrl)),
          child: Text(context.tr('privacy_policy')),
        ),
        TextButton(
          key: const ValueKey('legal_terms_of_service'),
          onPressed: () => launchExternalUri(Uri.parse(kTermsOfServiceUrl)),
          child: Text(context.tr('terms_of_service')),
        ),
      ],
    );
  }
}
