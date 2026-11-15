import 'package:admin/l10n/supported_locales.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Apple's own name for Tap to Pay on iPhone, in its long form, in the app's
/// language (App Review 5.4; the guide's localization table, pp. 20–21).
void main() {
  String name(String language, [String? region]) =>
      tapToPayOnIPhoneName(Locale(language, region));

  test('the long form Apple lists for each language', () {
    expect(name('en'), 'Tap to Pay on iPhone');
    expect(name('en', 'GB'), 'Tap to Pay on iPhone');
    expect(name('de'), 'Tap to Pay auf dem iPhone');
    expect(name('fr'), 'Tap to Pay sur iPhone');
    expect(name('fr', 'CH'), 'Tap to Pay sur iPhone');
    expect(name('es', 'ES'), 'Tap to Pay en iPhone');
    expect(name('pt', 'BR'), 'Tap to Pay no iPhone');
    expect(name('nb', 'NO'), 'Tap to Pay på iPhone');
    expect(name('sv'), 'Tap to Pay på iPhone');
    expect(name('fi'), 'iPhonen Tap to Pay');
    expect(name('et'), "Tap to Pay iPhone'is");
    expect(name('lt'), '„Tap to Pay“ su „iPhone“');
    expect(name('lv', 'LV'), 'Tap to Pay ar iPhone');
    expect(name('ja'), 'iPhoneのタッチ決済');
    expect(name('ca'), 'Tap to Pay a l’iPhone');
  });

  test('regional forms win over their language', () {
    expect(name('fr', 'CA'), 'Paiement rapide sur iPhone');
    expect(name('zh', 'TW'), 'iPhone卡緊收');
    expect(name('zh', 'HK'), 'iPhone 拍易收');
  });

  test('a language Apple does not list uses English', () {
    expect(name('zh', 'CN'), 'Tap to Pay on iPhone');
    expect(name('he'), 'Tap to Pay on iPhone');
    expect(name('sr'), 'Tap to Pay on iPhone');
  });

  test('every app language names it in full, never just "Tap to Pay"', () {
    for (final locale in kSupportedLocales) {
      final full = tapToPayOnIPhoneName(locale);
      // Inflected in some languages: iPhonu, iPhonie, iPhoneu.
      expect(full, contains('iPhon'), reason: '$locale');
      expect(full, isNot('Tap to Pay'), reason: '$locale');
    }
  });
}
