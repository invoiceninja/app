import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/domain/tasks/tasks_view_mode.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/list/master_detail_layout.dart';
import 'package:admin/ui/features/tasks/views/kanban_screen.dart';
import 'package:admin/ui/features/tasks/views/task_list_screen.dart';

import '../../../_localization_helper.dart';
import '../shell/_shell_test_helpers.dart';

/// The board stays behind an open task — with a real `GoRouter`, a real
/// `MasterDetailLayout` and the real `TaskListScreen` wired the way
/// `entity_modules.dart` wires it.
///
/// Opening a card used to swap the board for the plain list (the pane locked
/// every view to it), so reading one task cost the user their place. The
/// resolver's unit test proves the rule; this proves the screen obeys it, and
/// — the half that fails silently — that the SAME board survives the trip
/// rather than being torn down and rebuilt under the pane.
void main() {
  Future<GoRouter> pumpTasks(WidgetTester tester, Services services) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/tasks',
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: const ValueKey('master_detail:/tasks'),
            child: MasterDetailLayout(
              basePath: '/tasks',
              list: TaskListScreen(
                view: tasksViewModeFromQuery(state.uri.queryParameters['view']),
                hasPane: state.matchedLocation != '/tasks',
              ),
              rightPane: child,
              hasPane: state.matchedLocation != '/tasks',
              viewMode: state.uri.queryParameters['view'],
            ),
          ),
          routes: [
            GoRoute(path: '/tasks', builder: (_, _) => const SizedBox.shrink()),
            GoRoute(
              path: '/tasks/:id',
              builder: (_, state) =>
                  Material(child: Text('pane:${state.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      Provider<Services>.value(
        value: services,
        child: MaterialApp.router(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return router;
  }

  testWidgets('a remembered board is still the board behind an open task', (
    tester,
  ) async {
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
      closeStreamsSynchronously: true,
    );
    addTearDown(fixture.dispose);
    await fixture.services.tasksView.set(TasksViewMode.kanban);

    final router = await pumpTasks(tester, fixture.services);
    expect(find.byType(KanbanScreen), findsOneWidget);
    final board = tester.state(find.byType(KanbanScreen));

    router.go('/tasks/t1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('pane:t1'), findsOneWidget);
    expect(find.byType(KanbanScreen, skipOffstage: false), findsOneWidget);
    expect(
      find.byType(
        EntityListScreenScaffold<dynamic, dynamic>,
        skipOffstage: false,
      ),
      findsNothing,
    );
    // The same State: its scroll position, its view model and its opening
    // sync all outlive the pane.
    expect(
      tester.state(find.byType(KanbanScreen, skipOffstage: false)),
      same(board),
    );

    router.go('/tasks');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.state(find.byType(KanbanScreen)), same(board));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
