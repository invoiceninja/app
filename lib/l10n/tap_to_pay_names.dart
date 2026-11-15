import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/l10n/localization.dart';

/// Apple's official name for Tap to Pay on iPhone, in its long form, per
/// language — copied from the "Localization strings for Tap to Pay on
/// iPhone" table of Apple's Tap to Pay on iPhone App & Marketing Requirements
/// and Review Guide (pp. 20–21). App Review requires this exact name, never
/// shortened ("Tap to Pay" alone is the short form), wherever the feature is
/// named on iOS (docs/in-person-payments.md).
///
/// Keyed on the language code; a regional form Apple lists separately is in
/// [_kRegionalNames]. A language Apple doesn't list uses English.
const Map<String, String> kTapToPayOnIPhoneNames = {
  'ar': 'مرر للدفع على iPhone',
  'bg': 'Tap to Pay на iPhone',
  'uk': 'Tap to Pay на iPhone',
  'ca': 'Tap to Pay a l’iPhone',
  'hr': 'Tap to Pay na iPhoneu',
  'cs': 'Tap to Pay na iPhonu',
  'sl': 'Tap to Pay na iPhonu',
  'da': 'Tap to Pay på iPhone',
  'nb': 'Tap to Pay på iPhone',
  'nn': 'Tap to Pay på iPhone',
  'no': 'Tap to Pay på iPhone',
  'sv': 'Tap to Pay på iPhone',
  'nl': 'Tap to Pay op iPhone',
  'en': 'Tap to Pay on iPhone',
  'et': "Tap to Pay iPhone'is",
  'fi': 'iPhonen Tap to Pay',
  'fr': 'Tap to Pay sur iPhone',
  'de': 'Tap to Pay auf dem iPhone',
  'el': 'Tap to Pay στο iPhone',
  'hu': 'Tap to Pay az iPhone-on',
  'it': 'Tap to Pay su iPhone',
  'ja': 'iPhoneのタッチ決済',
  'lv': 'Tap to Pay ar iPhone',
  'lt': '„Tap to Pay“ su „iPhone“',
  'pl': 'Tap to Pay na iPhonie',
  'pt': 'Tap to Pay no iPhone',
  'ro': 'Tap to Pay pe iPhone',
  'sk': 'Tap to Pay na iPhone',
  'es': 'Tap to Pay en iPhone',
};

/// The forms Apple lists for one region of a language: French Canadian, and
/// Chinese for Hong Kong and Taiwan. Simplified Chinese (mainland China,
/// where there is no Tap to Pay on iPhone) has none, so it uses English.
const Map<String, String> _kRegionalNames = {
  'fr_CA': 'Paiement rapide sur iPhone',
  'zh_HK': 'iPhone 拍易收',
  'zh_TW': 'iPhone卡緊收',
};

/// The translation key that reads [tapToPayOnIPhoneName] in every locale:
/// `Localization` lays the name in when it loads, and `_app_pending.json`
/// has the English. For a label that must match a settings search hit.
const kTapToPayOnIPhoneKey = 'tap_to_pay_on_iphone';

/// Apple's long name for [locale].
String tapToPayOnIPhoneName(Locale locale) {
  final region = locale.countryCode;
  if (region != null && region.isNotEmpty) {
    final regional = _kRegionalNames['${locale.languageCode}_$region'];
    if (regional != null) return regional;
  }
  return kTapToPayOnIPhoneNames[locale.languageCode] ??
      kTapToPayOnIPhoneNames['en']!;
}

/// What the feature is called here, for a `:name` placeholder: Apple's long
/// name in the app's language on iOS — and on macOS, where only the iPhone
/// can take it — else "Tap to Pay" (the Android name, translated as
/// `tap_to_pay`).
String tapToPayName(BuildContext context) {
  if (isIPhonePlatform() ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)) {
    return tapToPayOnIPhoneName(
      Localizations.maybeLocaleOf(context) ?? const Locale('en'),
    );
  }
  return context.tr('tap_to_pay');
}

/// [tapToPayName] for a sentence: the name is in the sentence's language.
/// While [key] has no translation in the app's language yet — it renders in
/// English — Apple's English name goes into it, never "Tap to Pay auf dem
/// iPhone" inside an English sentence (or a right-to-left name inside a
/// left-to-right one). A label that is only the name uses [tapToPayName].
String tapToPayNameFor(BuildContext context, String key) {
  if (isIPhonePlatform() ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)) {
    if (!context.isTranslated(key)) return kTapToPayOnIPhoneNames['en']!;
  }
  return tapToPayName(context);
}
