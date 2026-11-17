// A company-only settings host (Company Details, Product Settings, …) never
// builds its company view model while the settings scope is a group or a
// client: the page under the "Group Settings: X" banner would otherwise save
// company-wide fields. A cascade-aware host (no title key) is unaffected.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/widgets/settings_company_scoped_host.dart';
import 'package:admin/ui/features/settings/widgets/settings_two_pane_scope.dart';

import '../../../../_localization_helper.dart';

class _FakeAuth implements AuthRepository {
  @override
  final ValueNotifier<AuthSession?> session = ValueNotifier<AuthSession?>(null);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  @override
  final AuthRepository auth = _FakeAuth();
  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CompanyVm extends ChangeNotifier {}

void main() {
  Future<int> pump(
    WidgetTester tester,
    SettingsLevelController level, {
    String? companyOnlyTitleKey = 'company_details',
  }) async {
    var created = 0;
    await tester.pumpWidget(
      Provider<Services>.value(
        value: _FakeServices(),
        child: ChangeNotifierProvider<SettingsLevelController>.value(
          value: level,
          child: MaterialApp(
            theme: buildInTheme(InTheme.light),
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: kTestSupportedLocales,
            home: SettingsTwoPaneScope(
              isTwoPane: true,
              child: SettingsCompanyScopedHost<_CompanyVm>(
                companyOnlyTitleKey: companyOnlyTitleKey,
                create: (_) {
                  created++;
                  return _CompanyVm();
                },
                builder: (_, _) => const Text('company page'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return created;
  }

  testWidgets('a company-only host refuses at group scope', (tester) async {
    final level = SettingsLevelController()
      ..setLevel(SettingsLevel.group, targetId: 'g1', targetName: 'Europe');
    final created = await pump(tester, level);
    expect(created, 0, reason: 'no company view model, so nothing to save');
    expect(find.text('company page'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-company-only-at-scope')),
      findsOneWidget,
    );
    expect(find.text('Configured at the company level only.'), findsOneWidget);
    // The scope banner is there, and its close is the way out.
    expect(find.text('Group Settings: Europe'), findsOneWidget);
  });

  testWidgets('and at client scope', (tester) async {
    final level = SettingsLevelController()
      ..setLevel(SettingsLevel.client, targetId: 'c1', targetName: 'Acme');
    expect(await pump(tester, level), 0);
    expect(find.text('company page'), findsNothing);
  });

  testWidgets('renders the page at company scope', (tester) async {
    expect(await pump(tester, SettingsLevelController()), 1);
    expect(find.text('company page'), findsOneWidget);
  });

  testWidgets('a cascade-aware host renders at group scope', (tester) async {
    final level = SettingsLevelController()
      ..setLevel(SettingsLevel.group, targetId: 'g1', targetName: 'Europe');
    expect(await pump(tester, level, companyOnlyTitleKey: null), 1);
    expect(find.text('company page'), findsOneWidget);
  });
}
