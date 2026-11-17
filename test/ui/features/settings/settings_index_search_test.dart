// Regression tests for the Settings index search affordance (issue #42).
//
// The magnifying glass used to be the `trailing:` of the in-list "Basic
// Settings" group header — the first child of the section `ListView` — so on a
// phone it scrolled away and the only way back to it was to fling to the top,
// even though the AppBar above stayed pinned the whole time.
//
// The rule under test: the search lives in the pinned chrome, never in the
// scrolling body, and the field itself is always visible. On narrow that
// chrome is `SettingsScreen`'s AppBar (the field in a 56 px `bottom:`, close
// in `actions:` while searching); on the wide 280 px pane, which has no
// AppBar, it's a strip lifted out of the scroll area.
//
// Also: React's Basic / Advanced halves, the phone home's grouped cards (R)
// and its per-row values (R1).

import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/repositories/company_repository.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/search_focus_registry.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:admin/ui/features/settings/settings_search_catalog.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/view_models/settings_home_summary_view_model.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/design.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/features/settings/views/settings_screen.dart';
import 'package:admin/ui/features/settings/views/settings_shell.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_screen_scaffold.dart';
import 'package:admin/ui/features/settings/widgets/settings_tab_strip.dart';
import 'package:admin/ui/features/settings/widgets/settings_two_pane_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../_localization_helper.dart';

/// The section list and the results both watch the auth session for module /
/// plan gating. A null session is enough — 23 ungated sections still render,
/// which is more than a 900 px viewport holds, so the list really scrolls.
class _FakeAuth implements AuthRepository {
  @override
  final ValueNotifier<AuthSession?> session = ValueNotifier<AuthSession?>(null);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices(this.auth);

  @override
  final AuthRepository auth;

  // A search hit's `onTap` runs the dirty guard before navigating.
  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();

  // The index claims `/` for its search.
  @override
  final SearchFocusRegistry searchFocus = SearchFocusRegistry();

  // The search watches the active company for its PEPPOL gate.
  @override
  final CompanyRepository company = _FakeCompanyRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// No company record: the search's PEPPOL gate then fails open.
class _FakeCompanyRepo implements CompanyRepository {
  @override
  Stream<Company?> watchCompany(String companyId) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// The phone home's value sources: a fixed company and fixed counts, so the
/// home renders values without a Drift graph.
class _FakeHomeSources implements SettingsHomeSources {
  Company? companyValue = const Company(
    id: 'c1',
    settings: CompanySettings(currencyId: '1', languageId: '1'),
  );
  int gateways = 0;
  int users = 3;

  @override
  Stream<Company?> company(String companyId) => Stream.value(companyValue);
  @override
  Stream<int> gatewayCount(String companyId) => Stream.value(gateways);
  @override
  Stream<int> userCount(String companyId) => Stream.value(users);
  @override
  Stream<int> bankAccountCount(String companyId) => Stream.value(0);
  @override
  Stream<int> groupCount(String companyId) => Stream.value(0);
  @override
  Stream<int> paymentLinkCount(String companyId) => Stream.value(0);
  @override
  Stream<int> scheduleCount(String companyId) => Stream.value(0);
  @override
  Stream<List<Design>> designs(String companyId) => Stream.value(const []);
  @override
  Future<Formatter?> formatter(String companyId) async => null;
  @override
  Future<void> ensureStatics() async {}
  @override
  String? currencyCode(String currencyId) => currencyId == '1' ? 'USD' : null;
  @override
  String? languageName(String languageId) =>
      languageId == '1' ? 'English' : null;
  @override
  ThemeMode get themeMode => ThemeMode.dark;
  @override
  final Listenable themeChanges = ChangeNotifier();
}

/// Android's system back press, as the platform delivers it.
Future<void> simulateSystemBack(WidgetTester tester) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMessageCodec().encodeMessage(<String, dynamic>{
      'method': 'popRoute',
    }),
    (ByteData? _) {},
  );
}

void main() {
  late _FakeServices services;
  late _FakeHomeSources homeSources;

  Widget wrap(WidgetTester tester, Widget child) {
    final auth = _FakeAuth();
    addTearDown(auth.session.dispose);
    final level = SettingsLevelController();
    addTearDown(level.dispose);
    services = _FakeServices(auth);
    homeSources = _FakeHomeSources();
    return MultiProvider(
      providers: [
        Provider<Services>.value(value: services),
        Provider<SettingsHomeSources?>.value(value: homeSources),
        ChangeNotifierProvider<SettingsLevelController>.value(value: level),
      ],
      child: child,
    );
  }

  void sizeTo(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The real `/settings` index inside the shell that publishes the two-pane
  /// decision — production's exact shape on a phone.
  Future<GoRouter> pumpIndex(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    sizeTo(tester, size);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        ShellRoute(
          builder: (context, state, child) => LayoutBuilder(
            builder: (context, constraints) => SettingsTwoPaneScope(
              isTwoPane: constraints.maxWidth >= Breakpoints.settingsTwoPane,
              child: child,
            ),
          ),
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'company_details',
                  builder: (_, _) => const Scaffold(body: Text('COMPANY')),
                ),
                // Any other section or tab a hit can open.
                GoRoute(
                  path: ':section',
                  builder: (_, state) =>
                      Scaffold(body: Text('PAGE ${state.uri.path}')),
                  routes: [
                    GoRoute(
                      path: ':tab',
                      builder: (_, state) =>
                          Scaffold(body: Text('PAGE ${state.uri.path}')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      wrap(
        tester,
        MaterialApp.router(
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

  /// The bare section list with no host controller — how `SettingsShell`
  /// mounts it in the wide 280 px pane.
  Future<void> pumpBarePane(WidgetTester tester) async {
    sizeTo(tester, const Size(280, 900));
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) =>
              const Scaffold(body: Material(child: SettingsListSidebar())),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      wrap(
        tester,
        MaterialApp.router(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The phone home's search field, pinned in the AppBar.
  Finder appBarField() => find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(TextField),
  );

  /// Focusing the always-visible field is what opens the search.
  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(appBarField());
    await tester.pumpAndSettle();
  }

  String currentUri(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('the search field is always in the pinned AppBar, so scrolling '
      'the section list cannot take it away (issue #42)', (tester) async {
    await pumpIndex(tester);

    expect(
      appBarField(),
      findsOneWidget,
      reason: 'a search box people can see is one they use — no magnifier',
    );
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(TextField),
      ),
      findsNothing,
      reason: 'a scroll-away search is exactly the reported bug',
    );
    expect(find.widgetWithIcon(IconButton, Icons.search), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
    // `AppBar` derives this from `bottom` — nothing to hand-maintain.
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).preferredSize.height,
      kToolbarHeight + 56,
    );

    // Scroll well past the first group header — the exact gesture in the
    // reporter's second screenshot.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('Advanced Settings'), findsOneWidget);
    expect(appBarField(), findsOneWidget);
  });

  test('the sections are React\'s Basic and Advanced lists, in React\'s '
      'order, plus the two pages only this app has', () {
    // React: `basic` / `advanced` in src/components/layouts/common/hooks.ts.
    List<String> slugs(SettingsGroup g) => [
      for (final s in kSettingsSections)
        if (s.group == g) s.slug,
    ];
    expect(slugs(SettingsGroup.basic), [
      'company_details',
      'user_details',
      'localization',
      'online_payments',
      'tax_settings',
      'product_settings',
      'task_settings',
      'tags',
      'expense_settings',
      'workflow_settings',
      'account_management',
      'backup_restore',
      'import_export',
      // Not in React.
      'device_settings',
      'keyboard_shortcuts',
    ]);
    expect(slugs(SettingsGroup.advanced), [
      'invoice_design',
      'custom_fields',
      'generated_numbers',
      'client_portal',
      'e_invoice',
      'email_settings',
      'templates_and_reminders',
      'bank_accounts',
      'group_settings',
      'payment_links',
      'schedules',
      'users',
      'system_logs',
    ]);
    // Grouped in the catalog itself, so the nav and the catalog agree.
    expect(
      kSettingsSections.map((s) => s.group).toList(),
      [...kSettingsSections.map((s) => s.group)]
        ..sort((a, b) => a.index.compareTo(b.index)),
    );
  });

  testWidgets('the phone home lists Basic then Advanced Settings, each as one '
      'card under a muted heading', (tester) async {
    await pumpIndex(tester);
    expect(find.text('Basic Settings'), findsOneWidget);
    // Account Management is Basic, as in React; Invoice Design is Advanced.
    await tester.scrollUntilVisible(
      find.text('Advanced Settings'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      tester.getTopLeft(find.text('Account Management')).dy,
      lessThan(tester.getTopLeft(find.text('Advanced Settings')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Advanced Settings')).dy,
      lessThan(tester.getTopLeft(find.text('Invoice Design')).dy),
    );
    // The group labels are level-2 headings; each row is one button.
    final heading = tester.getSemantics(find.text('Advanced Settings'));
    expect(heading.flagsCollection.isHeader, isTrue);
    expect(heading.headingLevel, 2);
    final row = tester.getSemantics(
      find.byKey(const ValueKey('settings-home-row-invoice_design')),
    );
    expect(row.flagsCollection.isButton, isTrue);
    expect(row.label, contains('Invoice Design'));
    // Compact: 48 px without a value (signed out, so no values here).
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('settings-home-row-invoice_design')),
          )
          .height,
      48,
    );
    // The flat list is gone: no ListTile rows on the phone home.
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('focusing the field opens the search and adds close', (
    tester,
  ) async {
    await pumpIndex(tester);

    await openSearch(tester);

    expect(appBarField(), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).preferredSize.height,
      kToolbarHeight + 56,
    );
  });

  testWidgets('typing filters the catalog down to matching fields', (
    tester,
  ) async {
    await pumpIndex(tester);
    await openSearch(tester);

    await tester.enterText(find.byType(TextField), 'postal');
    await tester.pumpAndSettle();

    // 'postal' matches exactly one field label in the whole catalog. The
    // title is a rich text now (the match is bold), so find it by its text.
    expect(find.text('Postal Code', findRichText: true), findsOneWidget);
    // The subtitle names the tab the hit opens.
    expect(find.text('Company Details › Address'), findsOneWidget);
    expect(
      find.text('Basic Settings'),
      findsNothing,
      reason: 'the section list is replaced by results while searching',
    );
  });

  testWidgets('closing restores the section list and clears the query', (
    tester,
  ) async {
    await pumpIndex(tester);
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'postal');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();

    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
    expect(find.text('Basic Settings'), findsOneWidget);
    expect(appBarField(), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isFalse,
      reason: 'closing puts the keyboard away',
    );
  });

  testWidgets(
    'Android back closes an open search instead of leaving Settings',
    (tester) async {
      final router = await pumpIndex(tester);
      await openSearch(tester);
      expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);

      await simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(currentUri(router), '/settings');
      expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
      expect(appBarField(), findsOneWidget);
      expect(find.text('Basic Settings'), findsOneWidget);
    },
  );

  testWidgets('the wide pane owns its own title + an always-visible search '
      'field, pinned above the scroll area — it has no AppBar to host them', (
    tester,
  ) async {
    await pumpBarePane(tester);

    // The field is on screen at rest — no magnifier to find first — and
    // outside the ListView: same invariant, different chrome.
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(find.widgetWithIcon(IconButton, Icons.search), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
    // The screen title the narrow layout gets from its AppBar. Exactly one, so
    // the pane can't grow a second copy inside the list.
    expect(find.text('Settings'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('Advanced Settings'), findsOneWidget);
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'the pinned field stays reachable at any scroll position',
    );
    expect(
      find.text('Settings'),
      findsOneWidget,
      reason: 'the screen title is pinned, so it survives any scroll position',
    );
    expect(
      find.text('Basic Settings'),
      findsNothing,
      reason:
          'the pinned strip carries the SCREEN title, never a group label — '
          'hoisting "Basic Settings" would leave it claiming that half down '
          'here in Advanced',
    );

    // Focusing the field opens the search; typing swaps in results; ✕ closes.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzqqxx');
    await tester.pumpAndSettle();
    expect(find.text('No results found.'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('No results found.'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the phone home opens on a company card that names the scope '
      'when settings are scoped to a client', (tester) async {
    await pumpIndex(tester);
    final card = find.byKey(const ValueKey('settings-company-card'));
    // Signed out: no company, no card.
    expect(card, findsNothing);

    (services.auth as _FakeAuth).session.value = const AuthSession(
      baseUrl: 'https://example.test',
      isHosted: false,
      accountId: 'acct',
      companies: [
        AuthCompany(
          id: 'c1',
          name: 'Hamill Ltd',
          displayName: 'Hamill Ltd',
          permissions: '',
          isAdmin: true,
          isOwner: true,
        ),
      ],
      currentCompanyId: 'c1',
    );
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Hamill Ltd')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Switch Company')),
      findsOneWidget,
    );
    // It leads the list, above the first group header.
    expect(
      tester.getTopLeft(card).dy,
      lessThan(tester.getTopLeft(find.text('Basic Settings')).dy),
    );

    tester
        .element(find.byType(SettingsScreen))
        .read<SettingsLevelController>()
        .setLevel(SettingsLevel.client, targetId: 'x', targetName: 'Acme');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.text('Client Settings: Acme')),
      findsOneWidget,
    );

    // Not while searching: the results own the list.
    await openSearch(tester);
    expect(card, findsNothing);
  });

  testWidgets('the phone home shows each section\'s current value at company '
      'scope, and none at client scope (R1)', (tester) async {
    await pumpIndex(tester);
    (services.auth as _FakeAuth).session.value = const AuthSession(
      baseUrl: 'https://example.test',
      isHosted: false,
      accountId: 'acct',
      companies: [
        AuthCompany(
          id: 'c1',
          name: 'Hamill Ltd',
          displayName: 'Hamill Ltd',
          permissions: '',
          isAdmin: true,
          isOwner: true,
        ),
      ],
      currentCompanyId: 'c1',
    );
    await tester.pumpAndSettle();

    Finder row(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('settings-home-row-'),
      ),
    );

    // A text value: a one-line subtitle.
    expect(
      find.descendant(
        of: row('Localization'),
        matching: find.text('USD · English'),
      ),
      findsOneWidget,
    );
    // A count: a trailing number. A zero draws nothing.
    expect(
      find.descendant(of: row('User Management'), matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('Bank Accounts'), matching: find.text('0')),
      findsNothing,
    );
    // A problem: a warning icon whose sentence is the screen reader's.
    final warning = find.descendant(
      of: row('Payment Settings'),
      matching: find.byIcon(Icons.warning_amber_rounded),
    );
    expect(warning, findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('No payment gateway is connected')),
      findsOneWidget,
    );
    // Further down: the device's own theme preference.
    await tester.scrollUntilVisible(
      find.text('Device Settings'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(of: row('Device Settings'), matching: find.text('Dark')),
      findsOneWidget,
    );
    // A row with a value is 56 px; one without stays 48.
    expect(tester.getSize(row('Device Settings')).height, 56);
    expect(tester.getSize(row('Keyboard Shortcuts')).height, 48);

    // At client scope a value would be the company's, not the page's.
    tester
        .element(find.byType(SettingsScreen))
        .read<SettingsLevelController>()
        .setLevel(SettingsLevel.client, targetId: 'x', targetName: 'Acme');
    await tester.pumpAndSettle();
    expect(find.text('USD · English'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  group('keyboard and empty query', () {
    /// What the list shows for [query] with this test's signed-out session:
    /// every module off, not an admin, hosted (the not-loaded fail-open).
    List<SettingsSearchHit> expectedHits(String query) => searchSettings(
      query,
      bundledLocalization(),
      scope: const SettingsSearchScope(
        enabledModules: 0,
        isAdminOrOwner: false,
        isCascade: false,
        isHosted: true,
      ),
    );

    testWidgets('an open search with nothing typed still lists the sections', (
      tester,
    ) async {
      // It used to list every field in the catalog — hundreds of rows.
      await pumpIndex(tester);
      await openSearch(tester);

      expect(find.text('Basic Settings'), findsOneWidget);
      expect(find.text('Company Details'), findsOneWidget);
    });

    testWidgets('a section name leads with the section itself', (tester) async {
      await pumpIndex(tester);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'tax settings');
      await tester.pumpAndSettle();

      final first = tester.widget<ListTile>(find.byType(ListTile).first);
      expect(((first.title! as Text).textSpan!).toPlainText(), 'Tax Settings');
    });

    testWidgets('Enter opens the field\'s tab', (tester) async {
      final router = await pumpIndex(tester);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'postal');
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(currentUri(router), '/settings/company_details/address');
    });

    testWidgets('↓ then Enter opens the second row, and Esc closes', (
      tester,
    ) async {
      final router = await pumpIndex(tester);
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'number');
      await tester.pumpAndSettle();

      final hits = expectedHits('number');
      expect(hits.length, greaterThan(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .elementAt(1)
            .selected,
        isTrue,
      );
      // The selected row's title takes the tile's selected colour — a styled
      // span with its own colour used to keep it in body ink.
      final hit1 = hits[1];
      final title = tester.widget<RichText>(
        find.descendant(
          of: find.byType(ListTile).at(1),
          matching: find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText() ==
                    bundledLocalization().lookup(hit1.fieldKey),
          ),
        ),
      );
      expect(_leafColor(title.text), InTheme.light.accentInk);

      // Up wraps from the top to the last row and back down again.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(currentUri(router), hits[1].route);

      // Back on the index, reopen and close with Esc.
      router.go('/settings');
      await tester.pumpAndSettle();
      await openSearch(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
      expect(find.text('Basic Settings'), findsOneWidget);
    });

    testWidgets('`/` opens the search on the settings index', (tester) async {
      await pumpIndex(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isFalse,
      );

      services.searchFocus.activate();
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
      expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);
    });
  });

  group('the wide header rule', () {
    /// The real two-pane shell at a desktop width, the nav beside a tabbed
    /// page (Invoice Design's shape) or an untabbed one.
    Future<void> pumpWide(WidgetTester tester, String location) async {
      sizeTo(tester, const Size(1440, 900));
      final router = GoRouter(
        initialLocation: location,
        routes: [
          ShellRoute(
            builder: (context, state, child) => SettingsShell(child: child),
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'invoice_design',
                    builder: (_, _) => DefaultTabController(
                      length: 3,
                      child: SettingsScreenScaffold(
                        titleKey: 'invoice_design',
                        bottom: SettingsTabStrip(
                          tabBar: TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            padding: settingsTabBarPadding(),
                            indicatorWeight: 2,
                            tabs: const [
                              Tab(text: 'General Settings'),
                              Tab(text: 'Invoice Options'),
                              Tab(text: 'Custom Designs'),
                            ],
                          ),
                        ),
                        body: const SettingsFormShell(
                          sections: [
                            FormSection(title: 'Design', children: [Text('x')]),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'product_settings',
                    builder: (_, _) => const SettingsScreenScaffold(
                      titleKey: 'product_settings',
                      body: SettingsFormShell(
                        sections: [
                          FormSection(title: 'Stock', children: [Text('x')]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrap(
          tester,
          MaterialApp.router(
            theme: buildInTheme(InTheme.light),
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: kTestSupportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double navRule(WidgetTester tester) =>
        tester.getRect(find.byKey(kSettingsNavRuleKey)).bottom;

    testWidgets('the line under Search Settings and the line under a page\'s '
        'tabs are one line', (tester) async {
      await pumpWide(tester, '/settings/invoice_design');
      // A TabBar paints its divider as its own last pixel row, as the nav's
      // 1 px Divider is.
      final tabRule = tester.getRect(find.byType(TabBar)).bottom;
      expect(navRule(tester), tabRule);
      expect(navRule(tester), kSettingsHeaderHeight);
      // And the two titles share a centre line.
      expect(
        tester.getCenter(find.text('Settings')).dy,
        tester
            .getCenter(
              find.descendant(
                of: find.byType(AppBar),
                matching: find.text('Invoice Design'),
              ),
            )
            .dy,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('an untabbed page draws no rule of its own, and nothing near '
        'the nav\'s — no near-miss', (tester) async {
      await pumpWide(tester, '/settings/product_settings');
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom, isNull);
      expect(appBar.shape, isNull);
      expect(
        tester.getRect(find.byType(AppBar)).bottom,
        kSettingsTitleBarHeight,
      );
      // The first card's top edge, the nearest horizontal line on the page,
      // sits well clear of the nav's rule rather than a few pixels off it.
      final cardTop = tester.getRect(find.byType(FormSection)).top;
      expect((cardTop - navRule(tester)).abs(), greaterThanOrEqualTo(12));
      expect(
        tester.getCenter(find.text('Settings')).dy,
        tester
            .getCenter(
              find.descendant(
                of: find.byType(AppBar),
                matching: find.text('Product Settings'),
              ),
            )
            .dy,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}

/// The colour the first non-empty run of [span] is painted in, with every
/// ancestor span's style merged in — what the user sees, not just the root.
Color? _leafColor(InlineSpan span, [TextStyle? inherited]) {
  final style = inherited == null
      ? span.style
      : (span.style == null ? inherited : inherited.merge(span.style));
  if (span is TextSpan) {
    if (span.text?.isNotEmpty ?? false) return style?.color;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final c = _leafColor(child, style);
      if (c != null) return c;
    }
  }
  return null;
}
