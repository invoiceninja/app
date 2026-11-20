// The signup consent line is built from keys every locale translates, so it
// reads in the user's language — an app-local sentence read English in every
// locale until Transifex caught up.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/auth/views/signup_screen.dart';

import '../../../../_localization_helper.dart';

Map<String, String> _bundle(String locale) =>
    (jsonDecode(File('assets/i18n/$locale.json').readAsStringSync())
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v.toString()));

class _GermanDelegate extends LocalizationsDelegate<Localization> {
  const _GermanDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<Localization> load(Locale locale) => SynchronousFuture(
    Localization.forTesting(
      strings: _bundle('de'),
      fallback: enStrings(),
      pending: pendingStrings(),
    ),
  );

  @override
  bool shouldReload(LocalizationsDelegate<Localization> old) => false;
}

void main() {
  testWidgets('the consent line reads in the active language', (tester) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [_GermanDelegate()],
        home: Builder(
          builder: (context) {
            label = signupTermsConsentLabel(context);
            return Text(label);
          },
        ),
      ),
    );

    final de = _bundle('de');
    for (final key in ['i_agree', 'terms_of_service', 'privacy_policy']) {
      expect(label, contains(de[key]), reason: key);
    }
    expect(label, isNot(contains('I agree')));
  });

  test('the untranslated app-local sentence is gone', () {
    expect(pendingStrings(), isNot(contains('i_agree_to_terms_and_privacy')));
  });
}
