// A store build that may not ask anyone to buy (App Store 3.1.3(f), Play
// Payments policy) never shows the hosted server's own "please upgrade"
// sentences: they are said in the app's words. Off the store they stand.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/ui/core/utils/store_safe_server_text.dart';

import '../../../_localization_helper.dart';

const _login = 'Pro / Free accounts only the owner can log in. Please upgrade';
const _loginDot =
    'Pro / Free accounts only the owner can log in. Please upgrade.';
const _feature = 'Upgrade to a paid plan for this feature.';

void main() {
  tearDown(() => debugStoreBillingOverride = null);

  test('each sentence maps to its key, inside a longer text too', () {
    String tr(String key) => '<$key>';
    expect(replacePlanSentences(_login, tr), '<owner_only_sign_in_plan>');
    expect(replacePlanSentences(_loginDot, tr), '<owner_only_sign_in_plan>');
    expect(
      replacePlanSentences(_feature, tr),
      '<feature_needs_pro_or_enterprise>',
    );
    expect(
      replacePlanSentences('Could not save · $_feature', tr),
      'Could not save · <feature_needs_pro_or_enterprise>',
    );
    expect(replacePlanSentences('Something else', tr), 'Something else');
  });

  Future<String> render(WidgetTester tester, String text) async {
    late String out;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Builder(
          builder: (context) {
            out = storeSafeServerText(context, text);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return out;
  }

  testWidgets('a store build says them in its own words', (tester) async {
    debugStoreBillingOverride = true;
    expect(
      await render(tester, _login),
      'Only the account owner can sign in on this plan.',
    );
    expect(
      await render(tester, _feature),
      'This feature needs the Pro or Enterprise plan.',
    );
  });

  testWidgets('desktop, the web and F-Droid keep the server\'s', (
    tester,
  ) async {
    debugStoreBillingOverride = false;
    expect(await render(tester, _login), _login);
    expect(await render(tester, _feature), _feature);
  });
}
