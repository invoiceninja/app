// A drawer left "open" by an unfold must come back closed on the next fold
// (`lib/ui/core/widgets/stale_drawer_guard.dart`, wrapped by `AppDrawer`).
// docs/foldables.md.

import 'package:admin/ui/core/widgets/stale_drawer_guard.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<GlobalKey<ScaffoldState>> pump(
    WidgetTester tester, {
    required bool guarded,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey<ScaffoldState>();
    const drawer = Drawer(child: Text('DRAWER'));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            // The shape every top-level screen uses.
            final globalNav = MediaQuery.sizeOf(context).width >= 600;
            return Scaffold(
              key: key,
              drawer: globalNav
                  ? null
                  : guarded
                  ? const StaleDrawerGuard(child: drawer)
                  : drawer,
              body: const Text('BODY'),
            );
          },
        ),
      ),
    );
    return key;
  }

  Future<void> unfoldAndFold(
    WidgetTester tester,
    GlobalKey<ScaffoldState> key,
  ) async {
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(951, 669);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
  }

  testWidgets('without the guard the drawer comes back open (the bug)', (
    tester,
  ) async {
    final key = await pump(tester, guarded: false);
    await unfoldAndFold(tester, key);
    expect(key.currentState!.isDrawerOpen, isTrue);
  });

  testWidgets('with the guard it comes back closed', (tester) async {
    final key = await pump(tester, guarded: true);
    await unfoldAndFold(tester, key);
    expect(key.currentState!.isDrawerOpen, isFalse);
    // A closed DrawerController does not build its drawer at all.
    expect(find.text('DRAWER'), findsNothing);
  });

  testWidgets('a drawer the user opens normally stays open', (tester) async {
    final key = await pump(tester, guarded: true);
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(key.currentState!.isDrawerOpen, isTrue);
  });
}
