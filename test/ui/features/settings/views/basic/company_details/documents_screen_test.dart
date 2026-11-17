// Company Details → Documents: the "public by default" toggle is offered only
// where the server applies `documents_public_by_default` — hosted, or a
// self-hosted server at `ServerFeatures.documentsPublicByDefault` or later. An
// older one stores the key and ignores it.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/app/version.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/company_repository.dart';
import 'package:admin/data/services/companies_api.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/view_models/company_details_view_model.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/views/basic/company_details/documents_screen.dart';

import '../../../../../../_localization_helper.dart';

class _FakeCompaniesApi implements CompaniesApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubCompanyRepo extends CompanyRepository {
  _StubCompanyRepo({required super.db}) : super(api: _FakeCompaniesApi());

  final _rows = StreamController<Company?>.broadcast();

  @override
  Stream<Company?> watchCompany(String companyId) {
    Future.microtask(() {
      if (!_rows.isClosed) _rows.add(const Company(id: 'co1'));
    });
    return _rows.stream;
  }

  @override
  Future<void> refresh(String companyId) async {}
}

class _FakeAuth implements AuthRepository {
  @override
  final ValueNotifier<AuthSession?> session = ValueNotifier<AuthSession?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  @override
  final ValueNotifier<String?> serverVersion = ValueNotifier<String?>(null);

  @override
  final AuthRepository auth = _FakeAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<_FakeServices> pump(
    WidgetTester tester, {
    String? serverVersion,
    bool isHosted = false,
  }) async {
    final services = _FakeServices()..serverVersion.value = serverVersion;
    (services.auth as _FakeAuth).session.value = AuthSession(
      baseUrl: 'https://example.test',
      isHosted: isHosted,
      accountId: 'acct',
      companies: const [],
      currentCompanyId: 'co1',
    );
    final vm = CompanyDetailsViewModel(
      repo: _StubCompanyRepo(db: db),
      companyId: 'co1',
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      Provider<Services>.value(
        value: services,
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider<SettingsLevelController>.value(
                  value: SettingsLevelController(),
                ),
                ChangeNotifierProvider<SettingsDraftHost>.value(value: vm),
                ChangeNotifierProvider<CompanyDetailsViewModel>.value(
                  value: vm,
                ),
              ],
              child: const CompanyDetailsDocumentsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(vm.load);
    await tester.pumpAndSettle();
    return services;
  }

  final toggle = find.text('Documents public by default');

  testWidgets('an older self-hosted server gets no toggle', (tester) async {
    await pump(tester, serverVersion: '5.13.31');
    expect(toggle, findsNothing);
  });

  testWidgets('a self-hosted server that applies it shows the toggle', (
    tester,
  ) async {
    await pump(tester, serverVersion: ServerFeatures.documentsPublicByDefault);
    expect(toggle, findsOneWidget);
  });

  testWidgets('an unknown version hides it until the server says who it is', (
    tester,
  ) async {
    final services = await pump(tester);
    expect(toggle, findsNothing);
    services.serverVersion.value = '5.13.60';
    await tester.pumpAndSettle();
    expect(toggle, findsOneWidget);
  });

  testWidgets('hosted shows it whatever version it reports', (tester) async {
    await pump(tester, serverVersion: '5.13.20', isHosted: true);
    expect(toggle, findsOneWidget);
  });
}
