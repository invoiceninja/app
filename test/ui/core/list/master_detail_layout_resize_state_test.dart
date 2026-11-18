// A breakpoint flip must never cost the list or the pane its State
// (`lib/ui/core/list/master_detail_layout.dart`, `_listKey` / `_paneKey`).
//
// A foldable opening or closing resizes the app in place, so the layout can
// cross `Breakpoints.slideOver` (1024) with a record open, and a phone opening
// a record moves the list from a bare slot to an `Offstage` one. Each of those
// changed the tree's shape, and without a stable key the list remounted —
// scroll offset, search text and selection gone — and the pane lost its focus.
// docs/foldables.md.

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/list/master_detail_layout.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../_localization_helper.dart';

class _FakeServices implements Services {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A list stand-in that remembers every State it has created, so a test can
/// tell a reparent (same State) from a remount (a new one).
class _ProbeList extends StatefulWidget {
  const _ProbeList();
  static final List<State> states = [];
  @override
  State<_ProbeList> createState() => _ProbeListState();
}

class _ProbeListState extends State<_ProbeList> {
  final ScrollController scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _ProbeList.states.add(this);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: const Drawer(child: Text('DRAWER')),
    appBar: AppBar(title: const TextField(key: ValueKey('list_search'))),
    body: ListView.builder(
      key: const ValueKey('probe_list'),
      controller: scroll,
      itemCount: 200,
      itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
    ),
  );
}

/// A pane body with a text field, so a test can check that the field keeps
/// its text, its focus and its State across a flip.
class _ProbePane extends StatefulWidget {
  const _ProbePane();
  static final List<State> states = [];
  @override
  State<_ProbePane> createState() => _ProbePaneState();
}

class _ProbePaneState extends State<_ProbePane> {
  final TextEditingController text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ProbePane.states.add(this);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextField(key: const ValueKey('pane_field'), controller: text),
    ),
  );
}

void main() {
  setUp(() {
    _ProbeList.states.clear();
    _ProbePane.states.clear();
  });

  Future<GoRouter> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/products',
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: const ValueKey('master_detail:/products'),
            child: MasterDetailLayout(
              basePath: '/products',
              list: const _ProbeList(),
              rightPane: child,
              hasPane: state.matchedLocation != '/products',
              viewMode: state.uri.queryParameters['view'],
            ),
          ),
          routes: [
            GoRoute(
              path: '/products',
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/products/:id',
              builder: (_, _) => const _ProbePane(),
            ),
          ],
        ),
      ],
    );

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

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  _ProbeListState listState() => _ProbeList.states.last as _ProbeListState;

  testWidgets('opening a record on a narrow viewport keeps the list State', (
    tester,
  ) async {
    final router = await pumpApp(tester, const Size(400, 800));
    listState().scroll.jumpTo(1200);
    await tester.pump();

    router.go('/products/p1');
    await tester.pumpAndSettle();
    router.go('/products');
    await tester.pumpAndSettle();

    expect(_ProbeList.states, hasLength(1), reason: 'list remounted');
    expect(listState().scroll.offset, 1200);
    expect(find.text('row 30'), findsOneWidget);
  });

  // Keeping the list's State under the pane also kept an open drawer: it sat
  // invisible behind the record, and the first back press closed it instead.
  testWidgets('a record opened over an open drawer closes the drawer', (
    tester,
  ) async {
    final router = await pumpApp(tester, const Size(400, 800));
    final scaffold = tester.state<ScaffoldState>(
      find.byType(Scaffold, skipOffstage: false).first,
    );
    scaffold.openDrawer();
    await tester.pumpAndSettle();

    router.go('/products/p1'); // a deep link, not a drawer tap
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isFalse);

    router.go('/products');
    await tester.pumpAndSettle();
    expect(find.text('DRAWER'), findsNothing);
    expect(_ProbeList.states, hasLength(1));
  });

  // Kept alive under the record, the list also kept keyboard focus: the
  // keyboard stayed up over the record and typing filtered the hidden list.
  testWidgets('a record covering the list takes focus away from it', (
    tester,
  ) async {
    final router = await pumpApp(tester, const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('list_search')));
    await tester.pump();
    final search = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('list_search')),
        matching: find.byType(EditableText),
      ),
    );
    expect(search.focusNode.hasFocus, isTrue);

    router.go('/products/p1');
    await tester.pumpAndSettle();
    expect(search.focusNode.hasFocus, isFalse);
    expect(_ProbeList.states, hasLength(1));
  });

  testWidgets('crossing slideOver both ways keeps the list and the pane', (
    tester,
  ) async {
    final router = await pumpApp(tester, const Size(1200, 800));
    listState().scroll.jumpTo(800);
    await tester.pump();

    router.go('/products/p1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pane_field')));
    await tester.enterText(find.byKey(const ValueKey('pane_field')), 'draft');
    await tester.pump();

    // A foldable folding closed: wide → narrow, record still open.
    await resize(tester, const Size(700, 800));
    // …and unfolding again.
    await resize(tester, const Size(1200, 800));

    expect(_ProbeList.states, hasLength(1), reason: 'list remounted');
    expect(listState().scroll.offset, 800);
    expect(_ProbePane.states, hasLength(1), reason: 'pane remounted');
    final pane = _ProbePane.states.single as _ProbePaneState;
    expect(pane.text.text, 'draft');
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('pane_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue, reason: 'field lost focus');
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });
}
