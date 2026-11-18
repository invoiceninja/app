// A foldable in book posture splits the master-detail layout at the fold
// (`lib/ui/core/list/master_detail_layout.dart`, `_buildFoldSplit`): the list
// in the half before the fold, the record (or an empty half) after it, nothing
// drawn on the fold, and no full-screen toggle — full width would put the form
// on the hinge. docs/foldables.md.

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/fold_geometry.dart';
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

class _PaneBody extends StatelessWidget {
  const _PaneBody();
  @override
  Widget build(BuildContext context) {
    final actions = MasterDetailPaneScope.paneActionsOf(context);
    final leading = MasterDetailPaneScope.paneLeadingOf(context);
    return Scaffold(
      body: Column(
        children: [
          ?leading,
          ?actions,
          const Text('DETAIL'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                anchorPoint: foldAnchorPoint(context),
                builder: (_) => const AlertDialog(content: Text('CONFIRM')),
              ),
              child: const Text('open dialog'),
            ),
          ),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const SizedBox(
                  height: 200,
                  child: Center(child: Text('SHEET')),
                ),
              ),
              child: const Text('open sheet'),
            ),
          ),
        ],
      ),
    );
  }
}

/// An open iPhone Duo with the rail collapsed: 951 − 64 = 887 of content, and
/// the 40 pt division at 455–495 in the window, 391–431 in the content.
const _content = Size(887, 669);
const _fold = Rect.fromLTWH(391, 0, 40, 669);

void main() {
  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
    bool withFold = true,
  }) async {
    tester.view.physicalSize = _content;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/products',
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: const ValueKey('master_detail:/products'),
            child: MasterDetailLayout(
              basePath: '/products',
              list: const Scaffold(body: Center(child: Text('LIST'))),
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
              builder: (_, _) => const _PaneBody(),
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
          builder: (context, inner) => Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                displayFeatures: withFold
                    ? const [
                        DisplayFeature(
                          bounds: _fold,
                          type: DisplayFeatureType.fold,
                          state: DisplayFeatureState.postureHalfOpened,
                        ),
                      ]
                    : const [],
              ),
              child: FoldPostureHost(child: inner!),
            ),
          ),
        ),
      ),
    );
    // Past the posture debounce.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    return router;
  }

  Rect rectOf(WidgetTester tester, String text) => tester.getRect(
    find.ancestor(of: find.text(text), matching: find.byType(Scaffold)).first,
  );

  testWidgets('no record: the list before the fold, an empty half after', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(rectOf(tester, 'LIST'), const Rect.fromLTRB(0, 0, 391, 669));
    final empty = find.text('No record selected');
    expect(empty, findsOneWidget);
    expect(tester.getCenter(empty).dx, greaterThan(431));
  });

  testWidgets('a record opens in the end half, with an X and no expand', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/products/p1');
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'LIST'), const Rect.fromLTRB(0, 0, 391, 669));
    final detail = tester.getRect(find.text('DETAIL'));
    expect(detail.left, greaterThanOrEqualTo(431));
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  // Without an anchor every dialog opens in the start half — over the list,
  // for an action on the record beside it.
  testWidgets('a dialog from the record opens in the record\'s half', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/products/p1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.left, greaterThanOrEqualTo(431));
  });

  testWidgets('a sheet from the record fills the record\'s half', (
    tester,
  ) async {
    final router = await pumpApp(tester);
    router.go('/products/p1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.left, greaterThanOrEqualTo(431));
    expect(sheet.right, lessThanOrEqualTo(887));
  });

  testWidgets('?view=full still renders in the end half', (tester) async {
    final router = await pumpApp(tester);
    router.go('/products/p1?view=full');
    await tester.pumpAndSettle();
    expect(find.text('LIST'), findsOneWidget);
    expect(tester.getRect(find.text('DETAIL')).left, greaterThanOrEqualTo(431));
  });

  testWidgets('right-to-left puts the list in the right-hand half', (
    tester,
  ) async {
    final router = await pumpApp(tester, direction: TextDirection.rtl);
    router.go('/products/p1');
    await tester.pumpAndSettle();
    expect(rectOf(tester, 'LIST'), const Rect.fromLTRB(431, 0, 887, 669));
    expect(tester.getRect(find.text('DETAIL')).right, lessThanOrEqualTo(391));
  });

  testWidgets('no fold: the usual full-page pane', (tester) async {
    final router = await pumpApp(tester, withFold: false);
    router.go('/products/p1');
    await tester.pumpAndSettle();
    expect(find.text('LIST'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });
}
