// ⌘F / Ctrl+F on a record opened in the master-detail pane by a click on its
// row, with no click into the record first (docs/find-in-line-items.md § The
// chord reaches a record opened from its list). The list holds the focus when
// its row is clicked, and the list is *beside* the pane, so the record's focus
// keeper would never take it back — what moves it is the pane's navigator
// focusing the page it pushes. Pinned here because nothing at the call site
// shows that, and a change to how the pane's routes are pushed would leave the
// chord answering nothing.

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/detail/detail_find_navigator.dart';
import 'package:admin/ui/core/detail/entity_detail_scaffold.dart';
import 'package:admin/ui/core/detail/generic_detail_view_model.dart';
import 'package:admin/ui/core/list/master_detail_layout.dart';
import 'package:admin/ui/core/widgets/focus_owner_keeper.dart';
import 'package:flutter/services.dart';
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

class _List extends StatefulWidget {
  const _List({required this.router});
  final GoRouter Function() router;
  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  final node = FocusNode(debugLabel: 'list');
  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusOwnerKeeper(
    node: node,
    canClaim: () =>
        widget.router().routerDelegate.currentConfiguration.uri.path ==
        '/invoices',
    child: Focus(
      focusNode: node,
      child: Scaffold(
        body: Column(
          children: [
            const TextField(key: ValueKey('list_search')),
            for (final id in ['1', '2'])
              InkWell(
                onTap: () => context.go('/invoices/$id'),
                child: SizedBox(height: 40, child: Text('ROW $id')),
              ),
          ],
        ),
      ),
    ),
  );
}

class _FindBinder extends StatefulWidget {
  const _FindBinder({required this.onFind});
  final VoidCallback onFind;
  @override
  State<_FindBinder> createState() => _FindBinderState();
}

class _FindBinderState extends State<_FindBinder> {
  DetailFindNavigator? _navigator;
  void _find() => widget.onFind();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = DetailFindNavigatorScope.maybeOf(context)?..bind(_find);
  }

  @override
  void dispose() {
    _navigator?.unbind(_find);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('body');
}

class _Detail extends StatefulWidget {
  const _Detail({required this.id, required this.onFind});
  final String id;
  final VoidCallback onFind;
  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  late final GenericDetailViewModel<String> vm =
      GenericDetailViewModel<String>.bound(Stream.value('record ${widget.id}'));
  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EntityDetailScaffold<String>(
    id: widget.id,
    vm: vm,
    emptyTitle: 'Not found',
    bodyBuilder: (context, item) => _FindBinder(onFind: widget.onFind),
  );
}

void main() {
  late int calls;

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    calls = 0;
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/invoices',
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: const ValueKey('md'),
            child: MasterDetailLayout(
              basePath: '/invoices',
              list: _List(router: () => router),
              rightPane: child,
              hasPane: state.matchedLocation != '/invoices',
            ),
          ),
          routes: [
            GoRoute(
              path: '/invoices',
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/invoices/:id',
              builder: (_, s) => KeyedSubtree(
                key: ValueKey(s.pathParameters['id']),
                child: _Detail(
                  id: s.pathParameters['id']!,
                  onFind: () => calls++,
                ),
              ),
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

  Future<bool> ctrlF(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    return handled;
  }

  bool focusInList(WidgetTester tester) => FocusManager
      .instance
      .primaryFocus!
      .ancestors
      .any((n) => n.debugLabel == 'list');

  testWidgets('a record opened by clicking its row answers the chord at once', (
    tester,
  ) async {
    await pumpApp(tester);
    // The list's own focus owner holds the focus, as on a real list.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'list');

    await tester.tap(find.text('ROW 1'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
    expect(await ctrlF(tester), isTrue);
    expect(calls, 1);

    // The next row, from the open pane.
    await tester.tap(find.text('ROW 2'));
    await tester.pumpAndSettle();
    expect(await ctrlF(tester), isTrue);
    expect(calls, 2);
  });

  testWidgets('…and so does one opened while the list\'s search field had '
      'the focus', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('list_search')));
    await tester.pump();
    expect(focusInList(tester), isTrue);

    await tester.tap(find.text('ROW 1'));
    await tester.pumpAndSettle();
    expect(focusInList(tester), isFalse);
    expect(await ctrlF(tester), isTrue);
    expect(calls, 1);
  });
}
