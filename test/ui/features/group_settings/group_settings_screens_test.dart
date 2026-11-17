// A group, end to end against a real `Services` graph and a real local
// database: a new group is saved straight onto its record screen with the
// Overview tab showing (online under its server id, offline under its `tmp_`
// id); the Overview lists exactly the settings the group overrides, by the
// label and value their settings page gives them, or says it overrides
// nothing; and Configure Settings enters group scope for that group.

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/design_api_model.dart';
import 'package:admin/data/models/api/group_setting_api_model.dart';
import 'package:admin/ui/core/detail/entity_detail_tabs.dart';
import 'package:admin/ui/core/detail/entity_quick_actions.dart';
import 'package:admin/ui/features/group_settings/group_setting_actions.dart';
import 'package:admin/ui/features/group_settings/group_settings_detail_screen.dart';
import 'package:admin/ui/features/group_settings/group_settings_overview.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/advanced/group_settings_edit_screen.dart';

import '../../../_localization_helper.dart';
import '../../../_support/record_screen_harness.dart';
import '../shell/_shell_test_helpers.dart';

const _base = '/settings/group_settings';

Future<void> _seedGroup(
  Services services, {
  String id = 'g1',
  Map<String, dynamic>? settings,
}) async {
  await services.designs.applyUpdateResponse(
    companyId: 'co1',
    serverResponse: const DesignApi(
      id: 'd1',
      name: 'Bold',
      entities: 'invoice',
      updatedAt: 1700000000,
    ),
  );
  await services.groupSettings.applyUpdateResponse(
    companyId: 'co1',
    serverResponse: GroupSettingApi(
      id: id,
      name: 'Europe',
      settings: settings,
      updatedAt: 1700000000,
      createdAt: 1700000000,
    ),
  );
}

Finder _inOverview(Finder f) =>
    find.descendant(of: find.byType(GroupSettingsOverview), matching: f);

/// The value drawn beside [label] in the Overview — the row's two texts.
void _expectRow(String label, String value) {
  expect(_inOverview(find.text(label)), findsWidgets, reason: label);
  expect(_inOverview(find.text(value)), findsOneWidget, reason: value);
}

/// Pumps a [GoRouter] over the fixture, as the settings shell would host it.
Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  ShellFixture fixture,
  String initialLocation,
) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/settings/localization',
        builder: (_, _) => const Scaffold(body: Text('localization page')),
      ),
      GoRoute(
        path: '/settings/invoice_design',
        builder: (_, _) => const Scaffold(body: Text('invoice design page')),
      ),
      GoRoute(
        path: _base,
        builder: (_, _) => const Scaffold(body: Text('groups list')),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, _) => const GroupSettingsEditScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (_, state) => GroupSettingsDetailScreen(
              key: ValueKey(state.pathParameters['id']),
              id: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    Provider<Services>.value(
      value: fixture.services,
      child: ChangeNotifierProvider<SettingsLevelController>.value(
        value: fixture.services.settingsLevel,
        child: MaterialApp.router(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          routerConfig: router,
        ),
      ),
    ),
  );
  return router;
}

/// Runs [body] against a router-hosted fixture, tearing down whatever
/// happens (see `recordScreenTest`).
void _routerTest(
  String description, {
  required String initialLocation,
  required Future<void> Function(
    WidgetTester tester,
    RecordScreen screen,
    GoRouter router,
  )
  body,
  Future<void> Function(Services services)? seed,
  http.Client? httpClient,
  bool online = false,
}) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(480, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late ShellFixture fixture;
    await tester.runAsync(() async {
      fixture = await buildFixture(
        companies: [const FakeCompany(id: 'co1', name: 'Co')],
        currentCompanyId: 'co1',
        closeStreamsSynchronously: true,
        httpClient: httpClient,
        online: online,
      );
      await seedUsd(fixture.services);
      await seed?.call(fixture.services);
    });
    final screen = RecordScreen(tester, fixture);
    try {
      final router = await _pumpRouter(tester, fixture, initialLocation);
      await body(tester, screen, router);
    } finally {
      await screen.dispose();
    }
  });
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

Future<void> _createGroup(
  WidgetTester tester,
  RecordScreen screen,
  String name,
) async {
  await screen.untilFound(find.byType(TextField), 'the name field');
  await tester.enterText(find.byType(TextField).first, name);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('settings_entity_save')));
}

void main() {
  group('a new group lands on its record screen, on the Overview tab', () {
    _routerTest(
      'offline: under its tmp_ id',
      initialLocation: '$_base/new',
      body: (tester, screen, router) async {
        await _createGroup(tester, screen, 'Wholesale');
        await screen.until(
          () => _location(router).startsWith('$_base/tmp_'),
          'the record route',
        );
        await screen.untilFound(
          find.byType(GroupSettingsOverview),
          'the Overview',
        );
        expect(find.byType(EntityDetailTabs), findsOneWidget);
        // The Overview is the landing tab, and the group overrides nothing yet.
        expect(
          find.byKey(const ValueKey('group-overrides-none')),
          findsOneWidget,
        );
        expect(find.text('Wholesale'), findsWidgets);
        // Not synced: Configure is offered, but cannot run yet.
        final configure = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Configure Settings'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(configure.onPressed, isNull);
        await screen.quiet();
      },
    );

    _routerTest(
      'online: under the id the server gave it',
      initialLocation: '$_base/new',
      online: true,
      httpClient: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/group_settings') {
          return jsonOk({
            'data': {
              'id': 'srv1',
              'name': 'Wholesale',
              'created_at': 1700000000,
              'updated_at': 1700000000,
            },
          });
        }
        if (request.method == 'GET' &&
            request.url.path.startsWith('/api/v1/group_settings')) {
          return jsonOk({'data': <Object>[]});
        }
        throw http.ClientException('offline (test fixture)');
      }),
      body: (tester, screen, router) async {
        await _createGroup(tester, screen, 'Wholesale');
        await screen.until(
          () => _location(router) == '$_base/srv1',
          'the record route under the server id',
        );
        await screen.untilFound(
          find.byType(GroupSettingsOverview),
          'the Overview',
        );
        expect(find.text('Wholesale'), findsWidgets);
        await screen.quiet();
      },
    );
  });

  group('the Overview', () {
    recordScreenTest(
      'lists each overridden setting with its page\'s label and value',
      seed: (services) => _seedGroup(
        services,
        settings: const {
          'currency_id': '1',
          'military_time': false,
          'payment_terms': '30',
          'invoice_design_id': 'd1',
          'mailgun_secret': 'key-123',
          'email_subject_reminder1': 'Reminder for \$number',
          'email_template_reminder1': '<p>Hello <b>there</b></p>',
          // A blank override (the group sets nothing on purpose) still lists.
          'reply_to_email': '',
          // Not a field any page can tick.
          'not_a_setting': 'x',
        },
      ),
      screen: () => const GroupSettingsDetailScreen(id: 'g1'),
      ready: () => find.byType(GroupSettingsOverview),
      body: (tester, screen) async {
        await screen.untilFound(
          _inOverview(find.text('Bold')),
          'the design name',
        );
        // Sections are the settings pages, in the settings list's order.
        for (final section in const [
          'Localization',
          'Payment Settings',
          'Invoice Design',
          'Email Settings',
          'Templates & Reminders',
        ]) {
          expect(_inOverview(find.text(section)), findsWidgets);
        }
        _expectRow('Currency', 'USD — US Dollar');
        _expectRow('24 Hour Time', 'Disabled');
        _expectRow('Invoice Payment Terms', '30 Days');
        _expectRow('Invoice Design', 'Bold');
        _expectRow('First Reminder · Subject', 'Reminder for \$number');
        _expectRow('First Reminder · Body', 'Hello there');
        _expectRow('Reply-To Email', '—');
        // A credential is never shown; a raw key or id never is either.
        expect(find.text('key-123'), findsNothing);
        expect(_inOverview(find.text('••••••••')), findsOneWidget);
        for (final raw in const [
          'currency_id',
          'invoice_design_id',
          'd1',
          'not_a_setting',
          'x',
        ]) {
          expect(_inOverview(find.text(raw)), findsNothing, reason: raw);
        }
        // The standing card counts them: eight settings.
        expect(find.text('8'), findsOneWidget);
        // Configure Settings is the record's quick action.
        expect(
          find.descendant(
            of: find.byType(EntityQuickActions<GroupSettingAction>),
            matching: find.text('Settings'),
          ),
          findsOneWidget,
        );
      },
    );

    recordScreenTest(
      'offers no Configure for a section whose page edits only the company',
      seed: (services) => _seedGroup(
        services,
        settings: const {'invoice_terms': 'x', 'enable_e_invoice': true},
      ),
      screen: () => const GroupSettingsDetailScreen(id: 'g1'),
      ready: () => find.byType(GroupSettingsOverview),
      body: (tester, screen) async {
        // Company Details always saves the company: its Configure would
        // write company-wide terms under the group's banner.
        final companyOnly = find.byKey(
          const ValueKey('group-overview-company-only-company_details'),
        );
        await screen.untilFound(companyOnly, 'the Company Details card');
        expect(tester.widget<TextButton>(companyOnly).onPressed, isNull);
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey('group-overview-section-company_details'),
            ),
            matching: find.byWidgetPredicate(
              (w) => w is TextButton && w.onPressed != null,
            ),
          ),
          findsNothing,
        );
        // E-Invoicing's page is cascade-aware and saves to the group.
        final eInvoice = find.descendant(
          of: find.byKey(const ValueKey('group-overview-section-e_invoicing')),
          matching: find.byType(TextButton),
        );
        expect(tester.widget<TextButton>(eInvoice).onPressed, isNotNull);
      },
    );

    recordScreenTest(
      'says plainly when the group overrides nothing',
      seed: (services) => _seedGroup(services),
      screen: () => const GroupSettingsDetailScreen(id: 'g1'),
      ready: () => find.byType(GroupSettingsOverview),
      body: (tester, screen) async {
        await screen.untilFound(
          find.byKey(const ValueKey('group-overrides-none')),
          'the empty state',
        );
        expect(
          find.text('This group uses the company settings.'),
          findsOneWidget,
        );
        final configure = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Configure Settings'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(configure.onPressed, isNotNull);
      },
    );
  });

  group('Configure Settings', () {
    _routerTest(
      'enters group scope for this group and opens its first page',
      initialLocation: '$_base/g1',
      seed: (services) =>
          _seedGroup(services, settings: const {'currency_id': '1'}),
      body: (tester, screen, router) async {
        await screen.untilFound(
          find.byType(EntityQuickActions<GroupSettingAction>),
          'the quick actions',
        );
        final level = screen.services.settingsLevel;
        expect(level.isCompany, isTrue);
        await tester.tap(
          find.descendant(
            of: find.byType(EntityQuickActions<GroupSettingAction>),
            matching: find.text('Settings'),
          ),
        );
        await screen.until(
          () => _location(router) == kGroupSettingsLandingRoute,
          'the settings page',
        );
        expect(level.level, SettingsLevel.group);
        expect(level.targetId, 'g1');
        expect(level.targetName, 'Europe');
        await screen.untilFound(find.text('localization page'), 'the page');
        level.reset();
      },
    );

    _routerTest(
      'a section\'s Configure opens that section at group scope',
      initialLocation: '$_base/g1',
      seed: (services) =>
          _seedGroup(services, settings: const {'invoice_design_id': 'd1'}),
      body: (tester, screen, router) async {
        final configure = find.descendant(
          of: find.byKey(
            const ValueKey('group-overview-section-invoice_design'),
          ),
          matching: find.text('Configure'),
        );
        await screen.untilFound(configure, 'the section');
        await tester.tap(configure);
        await screen.until(
          () => _location(router) == '/settings/invoice_design',
          'the Invoice Design page',
        );
        expect(screen.services.settingsLevel.targetId, 'g1');
        screen.services.settingsLevel.reset();
      },
    );
  });
}
