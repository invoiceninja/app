import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/views/basic/tax_settings_body.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../../_localization_helper.dart';

/// A host at company scope ([draft] set) or cascade scope ([draft] null,
/// the company only as [companyContext]).
class _FakeHost extends SettingsDraftHost {
  _FakeHost({required this.company, required this.atCompany});

  final Company company;
  final bool atCompany;

  @override
  Company? get draft => atCompany ? company : null;
  @override
  Company? get companyContext => company;
  @override
  Map<String, List<String>> get fieldErrors => const {};
  @override
  bool get isLoaded => true;
  @override
  bool get isDirty => false;
  @override
  bool get isSaving => false;
  @override
  String? get loadError => null;
  @override
  String? get submitError => null;
  @override
  void reset() {}
  @override
  Future<Object?> save() async => null;
  @override
  Future<void> load() async {}
}

class _FakeAuth implements AuthRepository {
  final ValueNotifier<AuthSession?> _session = ValueNotifier(
    const AuthSession(
      baseUrl: 'https://example.test',
      isHosted: true,
      accountId: 'acct',
      companies: [],
      currentCompanyId: 'co-A',
    ),
  );
  @override
  ValueListenable<AuthSession?> get session => _session;
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  @override
  final AuthRepository auth = _FakeAuth();
  @override
  Formatter? formatterIfReady(String companyId) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _pump(
  WidgetTester tester, {
  required SettingsLevel level,
  required bool calculateTaxes,
}) async {
  // No tax-rate slots, so no rate picker (and its repository) mounts.
  final company = Company(id: 'co-A', calculateTaxes: calculateTaxes);
  final scope = SettingsLevelController();
  if (level != SettingsLevel.company) {
    scope.setLevel(level, targetId: 'target', targetName: 'Target');
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            Provider<Services>.value(value: _FakeServices()),
            ChangeNotifierProvider<SettingsLevelController>.value(value: scope),
            ChangeNotifierProvider<SettingsDraftHost>.value(
              value: _FakeHost(
                company: company,
                atCompany: level == SettingsLevel.company,
              ),
            ),
          ],
          child: const TaxSettingsBody(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // invoiceninja/app#214: a group's Tax Settings, for a company with
  // Calculate Taxes on, drew an empty bordered card above Default Tax Rate.
  for (final level in [SettingsLevel.group, SettingsLevel.client]) {
    testWidgets('${level.name} scope with Calculate Taxes on draws no empty '
        'card', (tester) async {
      await _pump(tester, level: level, calculateTaxes: true);

      // Only the Tax Rates link card is left.
      expect(find.byType(FormSection), findsOneWidget);
      expect(find.text('Tax Rates'), findsOneWidget);
      expect(find.text('Inclusive Taxes'), findsNothing);
    });

    testWidgets('${level.name} scope with Calculate Taxes off still offers '
        'Inclusive Taxes', (tester) async {
      await _pump(tester, level: level, calculateTaxes: false);

      expect(find.byType(FormSection), findsNWidgets(2));
      expect(find.text('Inclusive Taxes'), findsOneWidget);
    });
  }

  testWidgets('company scope keeps the basic card with Calculate Taxes on', (
    tester,
  ) async {
    await _pump(tester, level: SettingsLevel.company, calculateTaxes: true);

    expect(find.text('Invoice Item Tax Rates'), findsOneWidget);
    expect(find.text('Inclusive Taxes'), findsNothing);
  });
}
