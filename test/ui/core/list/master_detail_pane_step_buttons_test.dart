// The record pane's previous / next buttons (`_PaneStepButtons` in
// `lib/ui/core/list/master_detail_layout.dart`): `K` / `J` for a pointer.
//
// They call the exact path the keys take, so the rules pinned here are the
// keys' rules: disabled at the ends, an edit form steps to the next edit form,
// and a page the list loads while the user sits on its last row re-enables
// Next (the list writes the controller from inside its own build, which is
// why the buttons rebuild after the frame rather than on the notification).

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/list/master_detail_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../_localization_helper.dart';

class _FakeServices implements Services {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Stands in for `EntityListScreenScaffold`: pushes its rows and the URL's
/// selection into the layout's controller on every build, as the real list
/// does.
class _List extends StatelessWidget {
  const _List({required this.ids, required this.selectedId});
  final ValueListenable<List<String>> ids;
  final String? selectedId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: ids,
    builder: (context, rows, _) {
      MasterDetailNavScope.maybeOf(
        context,
      )?.update(selectedId: selectedId, itemIds: rows);
      return const Scaffold(body: Center(child: Text('LIST')));
    },
  );
}

class _PaneBody extends StatelessWidget {
  const _PaneBody();
  @override
  Widget build(BuildContext context) {
    final actions = MasterDetailPaneScope.paneActionsOf(context);
    return Scaffold(body: Column(children: [?actions, const Text('PANE')]));
  }
}

void main() {
  String currentUri(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  Finder stepButton(IconData icon) => find.widgetWithIcon(IconButton, icon);
  bool enabled(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(stepButton(icon)).onPressed != null;
  const up = Icons.keyboard_arrow_up;
  const down = Icons.keyboard_arrow_down;

  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    required ValueNotifier<List<String>> ids,
    required String initialLocation,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) {
            final segments = state.uri.pathSegments;
            final selected = segments.length > 1 && segments[1] != 'new'
                ? segments[1]
                : null;
            return NoTransitionPage<void>(
              key: const ValueKey('master_detail:/products'),
              child: MasterDetailLayout(
                basePath: '/products',
                list: _List(ids: ids, selectedId: selected),
                rightPane: child,
                hasPane: state.matchedLocation != '/products',
                viewMode: state.uri.queryParameters['view'],
              ),
            );
          },
          routes: [
            GoRoute(
              path: '/products',
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/products/new',
              builder: (_, _) => const _PaneBody(),
            ),
            GoRoute(
              path: '/products/:id',
              builder: (_, _) => const _PaneBody(),
            ),
            GoRoute(
              path: '/products/:id/edit',
              builder: (_, _) => const _PaneBody(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      Provider<Services>.value(
        value: _FakeServices(),
        child: MaterialApp.router(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  group('with a pointer', () {
    final pointer = TargetPlatformVariant.only(TargetPlatform.macOS);

    testWidgets('step through the rows and stop at each end', (tester) async {
      final ids = ValueNotifier(['a', 'b', 'c']);
      final router = await pumpApp(
        tester,
        ids: ids,
        initialLocation: '/products/b',
      );

      expect(enabled(tester, up), isTrue);
      expect(enabled(tester, down), isTrue);

      await tester.tap(stepButton(down));
      await tester.pumpAndSettle();
      expect(currentUri(router), '/products/c');
      expect(enabled(tester, down), isFalse, reason: 'c is the last row');
      expect(enabled(tester, up), isTrue);

      await tester.tap(stepButton(up));
      await tester.pumpAndSettle();
      await tester.tap(stepButton(up));
      await tester.pumpAndSettle();
      expect(currentUri(router), '/products/a');
      expect(enabled(tester, up), isFalse, reason: 'a is the first row');
    }, variant: pointer);

    testWidgets('a page that arrives while on the last row re-enables Next', (
      tester,
    ) async {
      final ids = ValueNotifier(['a', 'b']);
      final router = await pumpApp(
        tester,
        ids: ids,
        initialLocation: '/products/b',
      );
      expect(enabled(tester, down), isFalse);

      ids.value = ['a', 'b', 'c', 'd'];
      await tester.pumpAndSettle();
      expect(enabled(tester, down), isTrue);

      await tester.tap(stepButton(down));
      await tester.pumpAndSettle();
      expect(currentUri(router), '/products/c');
    }, variant: pointer);

    testWidgets('an edit form steps to the next row\'s edit form', (
      tester,
    ) async {
      final ids = ValueNotifier(['a', 'b']);
      final router = await pumpApp(
        tester,
        ids: ids,
        initialLocation: '/products/a/edit',
      );
      await tester.tap(stepButton(down));
      await tester.pumpAndSettle();
      expect(currentUri(router), '/products/b/edit');
    }, variant: pointer);

    testWidgets('a record that is not in the list has nowhere to step', (
      tester,
    ) async {
      final ids = ValueNotifier(['a', 'b']);
      await pumpApp(tester, ids: ids, initialLocation: '/products/zz');
      expect(enabled(tester, up), isFalse);
      expect(enabled(tester, down), isFalse);
    }, variant: pointer);

    testWidgets('a create form has no step buttons', (tester) async {
      final ids = ValueNotifier(['a', 'b']);
      await pumpApp(tester, ids: ids, initialLocation: '/products/new');
      expect(find.text('PANE'), findsOneWidget);
      expect(stepButton(up), findsNothing);
      expect(stepButton(down), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
    }, variant: pointer);
  });

  testWidgets('touch: no step buttons — a row is a tap away', (tester) async {
    // `flutter test` reports android, which is touch-primary.
    final ids = ValueNotifier(['a', 'b', 'c']);
    await pumpApp(tester, ids: ids, initialLocation: '/products/b');
    expect(find.text('PANE'), findsOneWidget);
    expect(stepButton(up), findsNothing);
    expect(stepButton(down), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}
