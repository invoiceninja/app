// A plan is bought for the whole account, so only the owner of the active
// company's account is offered the in-app purchase sheet; anyone else lands on
// the Plan screen.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(AuthSession s) : sess = ValueNotifier(s);

  final ValueNotifier<AuthSession?> sess;

  @override
  ValueListenable<AuthSession?> get session => sess;

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Only `auth` is real: the purchase sheet reaching for anything else (its
/// `apiClient`) throws, which is what a non-owner must never get to.
class _FakeServices implements Services {
  _FakeServices(this.auth);

  @override
  final AuthRepository auth;

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

AuthSession _session({required bool isOwner}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: true,
  accountId: 'acct_other',
  currentCompanyId: 'co_other',
  userId: 'u1',
  userFirstName: 'Ada',
  userLastName: 'Lovelace',
  companies: [
    AuthCompany(
      id: 'co_other',
      name: 'Other',
      displayName: 'Other',
      permissions: '',
      isAdmin: isOwner,
      isOwner: isOwner,
    ),
  ],
);

void main() {
  testWidgets('a member of a free account gets the Plan screen, not the '
      'purchase sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => launchUpgrade(context),
              child: const Text('upgrade'),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/account_management',
          builder: (_, _) => const Scaffold(body: Text('plan screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      Provider<Services>.value(
        value: _FakeServices(_FakeAuth(_session(isOwner: false))),
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('upgrade'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('plan screen'), findsOneWidget);
  });
}
