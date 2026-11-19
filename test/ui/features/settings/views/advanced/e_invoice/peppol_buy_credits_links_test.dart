// The PEPPOL credit packs are sold on Invoice Ninja's web billing portal, so a
// store build never links to them (App Store 3.1.1(a), Play Payments 4).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/ui/features/settings/views/advanced/e_invoice/peppol_buy_credits_links.dart';

import '../../../../../../_localization_helper.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(AuthSession s) : _session = ValueNotifier(s);
  final ValueNotifier<AuthSession?> _session;
  @override
  ValueListenable<AuthSession?> get session => _session;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices(this.auth);
  @override
  final AuthRepository auth;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

AuthSession _session({bool isHosted = true}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: isHosted,
  accountId: 'acct',
  companies: const [],
  currentCompanyId: '',
);

Future<void> _pump(WidgetTester tester, {required bool storeBuild}) async {
  debugStoreBillingOverride = storeBuild;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Provider<Services>.value(
        value: _FakeServices(_FakeAuth(_session())),
        child: const Scaffold(body: PeppolBuyCreditsLinks()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => debugStoreBillingOverride = null);

  test('shown only on a hosted session of a non-store build', () {
    expect(
      PeppolBuyCreditsLinks.shownFor(_session(), storeBilling: false),
      isTrue,
    );
    expect(
      PeppolBuyCreditsLinks.shownFor(_session(), storeBilling: true),
      isFalse,
    );
    expect(
      PeppolBuyCreditsLinks.shownFor(
        _session(isHosted: false),
        storeBilling: false,
      ),
      isFalse,
    );
    expect(PeppolBuyCreditsLinks.shownFor(null, storeBilling: false), isFalse);
  });

  testWidgets('a store build renders no buy links', (tester) async {
    await _pump(tester, storeBuild: true);
    expect(find.textContaining('PEPPOL 500'), findsNothing);
    expect(find.textContaining('PEPPOL 1000'), findsNothing);
  });

  testWidgets('desktop, web and F-Droid keep both buy links', (tester) async {
    await _pump(tester, storeBuild: false);
    expect(find.textContaining('PEPPOL 500'), findsOneWidget);
    expect(find.textContaining('PEPPOL 1000'), findsOneWidget);
  });

  test('both cards gate the links at the call site, so no gap is paid', () {
    // A card's spacing still pays for a child that renders nothing
    // (CLAUDE.md: a card that hides itself still costs a gap).
    const dir = 'lib/ui/features/settings/views/advanced/e_invoice';
    for (final card in [
      '$dir/peppol_onboarding_card.dart',
      '$dir/peppol_preferences_card.dart',
    ]) {
      final src = File(card).readAsStringSync();
      expect(
        RegExp(
          r'if \(PeppolBuyCreditsLinks\.shownFor\([^;]*?\)\)\s*const PeppolBuyCreditsLinks\(\)',
        ).hasMatch(src),
        isTrue,
        reason: card,
      );
    }
  });
}
