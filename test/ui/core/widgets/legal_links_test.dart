// The privacy policy and terms of service have to be reachable inside the app
// (App Review 5.1.1(i), and 3.1.2 wherever a subscription is sold). Before
// LegalLinks the app named them only as plain text at signup.

import 'package:admin/app/theme.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/legal_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../_localization_helper.dart';

void main() {
  testWidgets('offers the privacy policy and the terms as buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: const Scaffold(body: LegalLinks()),
      ),
    );
    await tester.pumpAndSettle();

    final privacy = find.byKey(const ValueKey('legal_privacy_policy'));
    final terms = find.byKey(const ValueKey('legal_terms_of_service'));
    expect(privacy, findsOneWidget);
    expect(terms, findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    // Each is its own tap target, not a span inside a sentence.
    expect(tester.widget<TextButton>(privacy).onPressed, isNotNull);
    expect(tester.widget<TextButton>(terms).onPressed, isNotNull);
  });

  test('the links are the pages the hosted landing page uses', () {
    expect(kPrivacyPolicyUrl, 'https://invoiceninja.com/privacy-policy/');
    expect(kTermsOfServiceUrl, 'https://invoiceninja.com/terms/');
  });
}
