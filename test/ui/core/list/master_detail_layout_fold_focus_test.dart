// Leaving book posture with a record open hides the list behind the full-page
// record — and the list, kept alive by its key, kept keyboard focus: the
// keyboard stayed up over the record and typing filtered the hidden list.
// On a phone the opening record's autofocus took focus anyway; here the record
// is reparented, not opened, so nothing does. `ExcludeFocus` in `_keyedList`.
// docs/foldables.md.

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

void main() {
  testWidgets('a list field focused in book posture loses focus when the '
      'record covers the list', (tester) async {
    tester.view.physicalSize = const Size(887, 669);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final folded = ValueNotifier<bool>(true);
    addTearDown(folded.dispose);

    final router = GoRouter(
      initialLocation: '/products/p1',
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: const ValueKey('master_detail:/products'),
            child: MasterDetailLayout(
              basePath: '/products',
              list: const Scaffold(
                body: Center(child: TextField(key: ValueKey('list_search'))),
              ),
              rightPane: child,
              hasPane: state.matchedLocation != '/products',
            ),
          ),
          routes: [
            GoRoute(
              path: '/products',
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: '/products/:id',
              builder: (_, _) => const Scaffold(body: Text('DETAIL')),
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
          builder: (context, inner) => ValueListenableBuilder<bool>(
            valueListenable: folded,
            builder: (context, on, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                displayFeatures: on
                    ? const [
                        DisplayFeature(
                          bounds: Rect.fromLTWH(391, 0, 40, 669),
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
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Book posture: the list beside the record. Focus its search field.
    await tester.tap(find.byKey(const ValueKey('list_search')));
    await tester.pump();
    final search = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('list_search')),
        matching: find.byType(EditableText),
      ),
    );
    expect(search.focusNode.hasFocus, isTrue);

    // Flat: the record goes full page over the list.
    folded.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list_search')), findsNothing);
    expect(search.focusNode.hasFocus, isFalse);
  });
}
