import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/ui/core/widgets/link_text.dart';
import 'package:admin/ui/features/settings/settings_routes.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/basic/account_management/company_settings_gate.dart';
import 'package:admin/ui/features/settings/views/settings_screen.dart';
import 'package:admin/ui/features/settings/views/settings_shell.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/plan_gate_banner.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/features/settings/widgets/settings_page_intro.dart';

import '../shell/_shell_test_helpers.dart';

/// Every settings page opens the same way on a phone: at most ONE row above
/// its first card — the page's intro sentence at the start and its
/// page-level actions at the end (`SettingsPageIntro`). Templates &
/// Reminders used to put Preview in the Template card's header and had no
/// sentence; E-Invoicing spent a row of its own on its help link; Keyboard
/// Shortcuts drew its hint as a custom row with Reset all in a card header.
///
/// Walks the real `/settings/...` routes at 390 px and checks, per page:
///  (a) the intro sentence (`settings-page-subtitle`) is there exactly where
///      [_withIntro] says — the first tab of every content page; a pure list
///      (its empty state explains it) and a later tab have none;
///  (b) no button or link sits between the tab strip and the first card
///      except on the intro row;
///  (c) nothing adds a spacing row there: the first card starts right under
///      the intro row (or the shell's own padding when there is none).
///
/// `docs/settings-screens.md` § Every settings page opens with its intro row.
void main() {
  // The first tab of a content page — one sentence on what the page controls.
  const withIntro = <String>{
    'company_details',
    'user_details',
    'localization',
    'online_payments',
    'online_payments/payment_types',
    'tax_settings',
    'product_settings',
    'task_settings',
    'tags',
    'expense_settings',
    'workflow_settings',
    'account_management',
    'account_management/integrations/analytics',
    'backup_restore',
    'import_export',
    'device_settings',
    'keyboard_shortcuts',
    'invoice_design',
    'custom_fields',
    'generated_numbers',
    'client_portal',
    'e_invoice',
    'email_settings',
    'templates_and_reminders',
  };
  // A later tab (the page's sentence is on its first), or a pure list whose
  // empty state says what it is for.
  const withoutIntro = <String>{
    'company_details/address',
    'user_details/password',
    'localization/custom_labels',
    'online_payments/defaults',
    'workflow_settings/quotes',
    'account_management/overview',
    'account_management/enabled_modules',
    'account_management/integrations',
    'account_management/security_settings',
    'device_settings/security',
    'invoice_design/custom_designs',
    'invoice_design/client_details',
    'custom_fields/products',
    'generated_numbers/invoices',
    'client_portal/authorization',
    'company_gateways',
    'tax_rates',
    'task_statuses',
    'payment_terms',
    'account_management/integrations/api_tokens',
    'account_management/integrations/api_webhooks',
    'bank_accounts',
    'bank_accounts/transaction_rules',
    'group_settings',
    'payment_links',
    'schedules',
    'users',
    'system_logs',
  };

  for (final route in [...withIntro, ...withoutIntro]) {
    testWidgets('/settings/$route opens with its intro row', (tester) async {
      await _pumpRoute(tester, route);

      // (a)
      expect(
        find.byKey(const ValueKey('settings-page-subtitle')),
        withIntro.contains(route) ? findsOneWidget : findsNothing,
        reason: withIntro.contains(route)
            ? '$route is a content page: it needs an intro sentence'
            : '$route is a later tab or a pure list: no intro sentence',
      );

      final shell = find.byType(SettingsFormShell);
      if (shell.evaluate().isEmpty) {
        // A list with its own body (gateways, payment links): nothing above
        // its list to check.
        expect(withIntro.contains(route), isFalse);
        return;
      }
      final firstCard = _firstCardTop();
      if (firstCard == null) return;

      // (b)
      final stray = <String>[];
      for (final e
          in find
              .byWidgetPredicate(
                (w) =>
                    w is ButtonStyleButton || w is IconButton || w is LinkText,
              )
              .evaluate()) {
        final top = _onScreenTop(e);
        if (top == null || top >= firstCard) continue;
        if (_under(e, AppBar) || _under(e, SettingsPageIntro)) continue;
        if (_under(e, PlanGateBanner)) continue;
        if (!_under(e, SettingsFormShell)) continue;
        stray.add('${e.widget.runtimeType} at y=${top.round()}');
      }
      expect(
        stray,
        isEmpty,
        reason:
            '$route draws a button above its first card outside the intro '
            'row — a page action goes in SettingsFormShell(actions:), a '
            "card's own action in FormSection(trailing:)",
      );

      // (c)
      if (find.byType(PlanGateBanner).evaluate().isNotEmpty ||
          find.byType(CompanySettingsLockedBanner).evaluate().isNotEmpty) {
        return;
      }
      final intro = find.byType(SettingsPageIntro);
      final context = tester.element(shell.first);
      final expected = intro.evaluate().isNotEmpty
          ? tester.getBottomLeft(intro.first).dy + InSpacing.lg(context)
          : tester.getTopLeft(shell.first).dy + InSpacing.xl;
      expect(
        firstCard,
        moreOrLessEquals(expected, epsilon: 0.5),
        reason:
            '$route puts something between its intro row and its first card',
      );
    });
  }
}

Future<void> _pumpRoute(WidgetTester tester, String route) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The test font is wider than the app's, so a few tight rows overflow by
  // a few pixels here and nowhere else; this test is about where things sit.
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    onError?.call(details);
  };
  addTearDown(() => FlutterError.onError = onError);
  final fixture = await buildFixture(
    companies: [const FakeCompany(id: 'co1', name: 'Co')],
    plan: 'enterprise',
    closeStreamsSynchronously: true,
    // Every refresh a page starts on open gets an empty page.
    httpClient: MockClient(
      (_) async => http.Response(
        '{"data":[],"meta":{"pagination":{"total":0,"count":0,'
        '"per_page":50,"current_page":1,"total_pages":1}}}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
  addTearDown(fixture.dispose);
  // A signed-in user, so User Details has a record to draft from.
  await fixture.db.userSettingsDao.upsert(
    UserSettingsCompanion.insert(companyId: 'co1', userId: 'u1', updatedAt: 0),
  );
  await fixture.db.userDao.upsert(
    UsersCompanion.insert(
      id: 'u1',
      companyId: 'co1',
      firstName: 'Ann',
      lastName: 'Lee',
      email: 'ann@example.com',
      phone: '',
      languageId: '',
      signature: '',
      payload: '{}',
      updatedAt: 0,
    ),
  );
  await fixture.services.auth.restore();
  fixture.services.refreshScheduler.stop();
  final router = GoRouter(
    initialLocation: '/settings/$route',
    routes: [
      ShellRoute(
        builder: (context, state, child) => SettingsShell(child: child),
        routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
            routes: settingsRoutes,
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsLevelController>(
      create: (_) => SettingsLevelController(),
      child: wrapWithShell(fixture.services, Router.withConfig(config: router)),
    ),
  );
  // Not pumpAndSettle: several pages hold a spinner or a live stream.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The top of the first on-screen `FormSection` (the visible tab's).
double? _firstCardTop() {
  double? top;
  for (final e in find.byType(FormSection).evaluate()) {
    final y = _onScreenTop(e);
    if (y != null && (top == null || y < top)) top = y;
  }
  return top;
}

double? _onScreenTop(Element e) {
  final box = e.renderObject;
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final o = box.localToGlobal(Offset.zero);
  // A neighbouring tab of a TabBarView sits off to the side.
  if (o.dx < 0 || o.dx >= 390) return null;
  return o.dy;
}

bool _under(Element e, Type type) {
  var found = false;
  e.visitAncestorElements((a) {
    if (a.widget.runtimeType == type) found = true;
    return !found;
  });
  return found;
}
