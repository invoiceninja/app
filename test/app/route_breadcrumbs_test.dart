import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/route_breadcrumbs.dart';

void main() {
  testWidgets('records each change of route pattern, never a location', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/quotes',
      routes: [
        GoRoute(
          path: '/quotes',
          builder: (_, _) => const SizedBox(),
          routes: [
            GoRoute(path: ':id/edit', builder: (_, _) => const SizedBox()),
          ],
        ),
        GoRoute(path: '/clients', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final crumbs = <String>[];
    final breadcrumbs = RouteBreadcrumbs.fromRouter(
      router: router,
      record: ({required from, required to}) => crumbs.add('$from -> $to'),
    );
    addTearDown(breadcrumbs.dispose);

    router.go('/quotes/Wpmbk5ezJn/edit?tab=items');
    await tester.pumpAndSettle();
    // Another record on the same screen is the same pattern: no crumb.
    router.go('/quotes/Xrtq1oa8Aq/edit');
    await tester.pumpAndSettle();
    router.go('/clients?status=active');
    await tester.pumpAndSettle();

    expect(crumbs, [
      ' -> /quotes',
      '/quotes -> /quotes/:id/edit',
      '/quotes/:id/edit -> /clients',
    ]);
    expect(
      crumbs.join(),
      isNot(anyOf(contains('Wpmbk5ezJn'), contains('?'))),
      reason: 'record ids and queries never leave the device',
    );
  });

  test('a pattern that throws is recorded as ?, and dispose stops it', () {
    final changes = ChangeNotifier();
    var pattern = '/a';
    var fail = false;
    final crumbs = <String>[];
    final breadcrumbs = RouteBreadcrumbs(
      changes: changes,
      currentPattern: () => fail ? throw StateError('no route') : pattern,
      record: ({required from, required to}) => crumbs.add('$from -> $to'),
    );

    fail = true;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    changes.notifyListeners();
    breadcrumbs.dispose();
    fail = false;
    pattern = '/b';
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    changes.notifyListeners();

    expect(crumbs, [' -> /a', '/a -> ?']);
    expect(routePattern(''), '/');
  });
}
