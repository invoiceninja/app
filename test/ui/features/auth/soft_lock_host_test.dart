import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/ui/features/auth/views/soft_lock_host.dart';

import '../../../_localization_helper.dart';
import '../../../_support/fake_biometric_service.dart';
import '../shell/_shell_test_helpers.dart';

/// The soft lock (docs/soft-lock.md): the app locked in place, under an
/// overlay, with nothing beneath it disposed and nothing beneath it reachable.
void main() {
  late ShellFixture fixture;
  late FakeBiometricService biometric;

  Services services() => fixture.services;

  // Built inside each test body, in the test's own zone: a Drift database
  // opened in `setUp` and then written from the fake-async test body hangs.
  Future<void> setUpFixture() async {
    biometric = FakeBiometricService();
    fixture = await buildFixture(
      companies: const [FakeCompany(id: 'c1', name: 'Acme Co', token: 'tok')],
      currentCompanyId: 'c1',
      biometricService: biometric,
    );
    addTearDown(fixture.dispose);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    BackButtonDispatcher? back,
  }) async {
    await setUpFixture();
    await tester.pumpWidget(
      Provider<Services>.value(
        value: services(),
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          // Where `main.dart` puts it: around the routed app, above its
          // Navigator.
          builder: (context, child) => SoftLockHost(
            locked: services().auth.softLocked,
            backButtonDispatcher: back,
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  /// Lock, with the auto-prompt declined so the panel stays up.
  Future<void> lock(WidgetTester tester) async {
    biometric.outcomes.add(false);
    services().auth.engageSoftLock();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> unlock(WidgetTester tester) async {
    biometric.outcomes.add(true);
    await tester.tap(find.byKey(const ValueKey('lock_unlock')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> tearDownTree(WidgetTester tester) async {
    services().recentlyViewed.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  final panel = find.byKey(const ValueKey('soft_lock_panel'));

  testWidgets('locks in place: an editor keeps its unsaved text and its '
      'State, lets the keyboard go, and gets its focus back on unlock', (
    tester,
  ) async {
    final text = TextEditingController();
    addTearDown(text.dispose);
    await pump(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(width: 320, child: TextField(controller: text)),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.enterText('an unsaved draft');
    await tester.pump();
    final state = tester.state(find.byType(EditableText));
    final fieldFocus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(fieldFocus.hasPrimaryFocus, isTrue);

    await lock(tester);
    expect(panel, findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(biometric.ownerPrompts, 1, reason: 'prompts as it appears');
    expect(services().auth.session.value, isNotNull, reason: 'not signed out');
    expect(fieldFocus.hasFocus, isFalse);
    expect(
      tester.testTextInput.hasAnyClients,
      isFalse,
      reason: 'the soft keyboard must not type into the app beneath',
    );
    expect(text.text, 'an unsaved draft');

    await unlock(tester);
    expect(services().auth.softLocked.value, isFalse);
    expect(panel, findsNothing);
    expect(
      tester.state(find.byType(EditableText)),
      same(state),
      reason: 'never remounted',
    );
    expect(text.text, 'an unsaved draft');
    expect(fieldFocus.hasPrimaryFocus, isTrue, reason: 'focus given back');
    await tearDownTree(tester);
  });

  testWidgets('no key reaches the app while locked', (tester) async {
    var hits = 0;
    final appFocus = FocusNode(debugLabel: 'app');
    addTearDown(appFocus.dispose);
    await pump(
      tester,
      Scaffold(
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyN): () => hits++,
            const SingleActivator(LogicalKeyboardKey.escape): () => hits++,
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => hits++,
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                hits++,
          },
          child: Focus(
            focusNode: appFocus,
            autofocus: true,
            child: const Text('app'),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(hits, 1, reason: 'the shortcut works unlocked');

    await lock(tester);
    expect(appFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(hits, 1);
    expect(appFocus.hasFocus, isFalse, reason: 'Tab stays in the panel');

    await unlock(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    expect(hits, 2, reason: 'and works again after the unlock');
    await tearDownTree(tester);
  });

  testWidgets('a dialog open in the app stays under the lock — not over it, '
      'not closed — and no tap reaches it', (tester) async {
    var actions = 0;
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: const Text('App dialog'),
                  actions: [
                    TextButton(
                      onPressed: () => actions++,
                      child: const Text('Dialog action'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await lock(tester);
    await tester.tap(find.text('Dialog action'), warnIfMissed: false);
    await tester.pump();
    expect(actions, 0);
    // What a tap at the dialog's action hits is the panel.
    final hit = tester.hitTestOnBinding(
      tester.getCenter(find.text('Dialog action')),
    );
    final panelBox = tester.renderObject(panel);
    expect(hit.path.any((e) => identical(e.target, panelBox)), isTrue);

    await unlock(tester);
    expect(find.text('App dialog'), findsOneWidget, reason: 'still open');
    await tester.tap(find.text('Dialog action'));
    expect(actions, 1);
    await tearDownTree(tester);
  });

  testWidgets('Android back is swallowed while locked — the router beneath '
      'never pops', (tester) async {
    final back = RootBackButtonDispatcher();
    var routerPops = 0;
    // What `Router` registers: the pop of the app's own routes.
    Future<bool> routerPop() async {
      routerPops++;
      return true;
    }

    back.addCallback(routerPop);
    addTearDown(() => back.removeCallback(routerPop));
    await pump(tester, const Scaffold(body: Text('app')), back: back);

    await lock(tester);
    expect(await back.invokeCallback(Future.value(false)), isTrue);
    expect(routerPops, 0);

    await unlock(tester);
    await back.invokeCallback(Future.value(false));
    expect(routerPops, 1, reason: 'the app has its back again');
    await tearDownTree(tester);
  });

  group('Sign out', () {
    testWidgets('confirms first, over the lock; Cancel keeps the session and '
        'the lock', (tester) async {
      await pump(tester, const Scaffold(body: Text('app')));
      await lock(tester);
      await tester.tap(find.byKey(const ValueKey('lock_sign_out')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Sign out?').hitTestable(),
        findsOneWidget,
        reason: 'the confirmation opens above the panel, not under it',
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sign out?'), findsNothing);
      expect(services().auth.session.value?.currentCompanyId, 'c1');
      expect(services().auth.softLocked.value, isTrue);
      await tearDownTree(tester);
    });

    testWidgets('unsynced changes get the sign-out prompt every sign-out gets '
        '— never silently wiped', (tester) async {
      await pump(tester, const Scaffold(body: Text('app')));
      await fixture.db.outboxDao.enqueue(
        OutboxCompanion.insert(
          companyId: 'c1',
          entityType: 'client',
          entityId: 'x',
          mutationKind: 'update',
          payload: '{}',
          idempotencyKey: 'k',
          createdAt: 0,
          nextAttemptAt: 0,
          requiresPassword: const Value(false),
        ),
      );
      await lock(tester);
      await tester.tap(find.byKey(const ValueKey('lock_sign_out')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign out'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unsynced changes'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(services().auth.session.value?.currentCompanyId, 'c1');
      expect(services().auth.softLocked.value, isTrue);
      expect(await services().sync.pendingCountFor('c1'), 1);
      await tearDownTree(tester);
    });

    testWidgets('confirmed with nothing unsynced, it signs out and the lock '
        'goes with the session', (tester) async {
      await pump(tester, const Scaffold(body: Text('app')));
      await lock(tester);
      await tester.tap(find.byKey(const ValueKey('lock_sign_out')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign out'),
        ),
      );
      // The wipe is real I/O, and the Unlock spinner turns meanwhile, so no
      // pumpAndSettle: let the I/O run, a frame at a time.
      for (var i = 0; i < 40 && services().auth.session.value != null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump();
      expect(services().auth.session.value, isNull);
      expect(services().auth.softLocked.value, isFalse);
      expect(panel, findsNothing);
      await tearDownTree(tester);
    });
  });
}
