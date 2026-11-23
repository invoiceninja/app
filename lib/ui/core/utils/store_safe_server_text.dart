import 'package:flutter/widgets.dart';

import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/l10n/localization.dart';

/// Server sentences that ask the user to buy a plan, and the app's own
/// words for each. The hosted server sends them in English, whatever the
/// language: `LoginController`'s refusal of a member on a Free or Pro account
/// (401 / 403), and `BaseController::featureFailure()` (403).
final _kPlanSentences = <RegExp, String>{
  RegExp(
    r'Pro / Free accounts only the owner can log in\.?\s*Please upgrade\.?',
  ): 'owner_only_sign_in_plan',
  RegExp(r'Upgrade to a paid plan for this feature\.?'):
      'feature_needs_pro_or_enterprise',
};

/// [text] with every server sentence that asks the user to buy a plan
/// replaced by the app's own words, translated by [tr]. Pure, for tests.
String replacePlanSentences(String text, String Function(String key) tr) {
  var out = text;
  for (final MapEntry(key: pattern, value: key) in _kPlanSentences.entries) {
    if (pattern.hasMatch(out)) out = out.replaceAll(pattern, tr(key));
  }
  return out;
}

/// A server message as a screen may show it. On a store-billing build
/// (`isStoreBillingBuild`) the server's own "please upgrade" sentences are
/// said in the app's words, which name the plan and ask nothing of the user
/// (App Store 3.1.3(f), Play Payments policy; docs/in-app-purchases.md).
/// Desktop, the web and F-Droid keep the server's text.
String storeSafeServerText(BuildContext context, String text) {
  if (!isStoreBillingBuild || text.isEmpty) return text;
  // Above the app's localizations there are no words of our own to say.
  final l10n = Localization.of(context);
  if (l10n == null) return text;
  return replacePlanSentences(text, (key) => l10n.lookup(key));
}
