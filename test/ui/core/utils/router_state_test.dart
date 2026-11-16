// `routerStateOf` under a route that is on its way out.
//
// The shape is the app's: a StatefulShellRoute branch holding a ShellRoute
// (the list beside its record pane), so the record's route lives in a nested
// navigator. Leaving the record drops its page from go_router's registry while
// the route plays its exit transition, and a widget inside it that is built
// for the first time during that transition is what froze the app: go_router's
// own `GoRouterState.of` never returns there (docs/upstream-workarounds.md
// entry 25). A client's embedded Invoices list did exactly that.
//
// The raw call can't be shown failing here, since it would hang the test run
// instead of failing it. `no_raw_go_router_state_of_test.dart` keeps it out of
// `lib/`; this proves the replacement answers, and with what.

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/ui/core/utils/router_state.dart';

/// Asks for the router state on every build, as a list scaffold does.
class _Asks extends StatelessWidget {
  const _Asks(this.seen);

  final List<String> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(routerStateOf(context).uri.path);
    return const SizedBox.shrink();
  }
}

GoRouter _router(ValueNotifier<bool> mountLate, List<String> seen) => GoRouter(
  initialLocation: '/clients',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => Scaffold(body: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            ShellRoute(
              builder: (context, state, child) => Row(
                children: [
                  const Expanded(child: Text('list')),
                  Expanded(child: child),
                ],
              ),
              routes: [
                GoRoute(
                  path: '/clients',
                  builder: (_, _) => const Text('no record'),
                ),
                GoRoute(
                  path: '/clients/:id',
                  // A record whose tab body is built late, as a client's
                  // embedded lists are.
                  builder: (_, _) => ValueListenableBuilder<bool>(
                    valueListenable: mountLate,
                    builder: (_, mount, _) => Column(
                      children: [const Text('record'), if (mount) _Asks(seen)],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('a widget first built under a departing record gets the '
      "router's current state, and the frame completes", (tester) async {
    final mountLate = ValueNotifier(false);
    addTearDown(mountLate.dispose);
    final seen = <String>[];
    final router = _router(mountLate, seen);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/clients/abc');
    await tester.pumpAndSettle();
    expect(find.text('record'), findsOneWidget);

    // Leave. One frame in, the record's page is gone from the router but its
    // route is still on screen, sliding out.
    router.go('/clients');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('record'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.text('record')))!;
    expect(route.isActive, isFalse);

    // Now something inside it is built for the first time.
    mountLate.value = true;
    await tester.pump();

    expect(seen, ['/clients']);
    await tester.pumpAndSettle();
    expect(find.text('record'), findsNothing);
  });

  testWidgets('under the current route it is go_router\'s own state', (
    tester,
  ) async {
    final mountLate = ValueNotifier(true);
    addTearDown(mountLate.dispose);
    final seen = <String>[];
    final router = _router(mountLate, seen);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/clients/abc');
    await tester.pumpAndSettle();

    expect(seen.last, '/clients/abc');
    final context = tester.element(find.byType(_Asks));
    expect(routerStateOf(context).pathParameters['id'], 'abc');
  });

  testWidgets('with no router above, it throws as GoRouterState.of does', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(() => routerStateOf(context), throwsA(isA<GoError>()));
  });
}
