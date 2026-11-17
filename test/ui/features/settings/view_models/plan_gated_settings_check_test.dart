// A free hosted plan keeps only `CompanySettings::$free_plan_casts`
// (`UpdateCompanyRequest::filterSaveableSettings`), so the server answers a
// save of `hidden_payment_types`, `translations` or
// `documents_public_by_default` with 200 and the key gone from its echo.
// `PlanGatedSettingsCheck` reads the server's copy back before "Saved": a
// dropped edit fails the save with `submitNeedsPaidPlan`, keeping the draft.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/repositories/company_repository.dart';
import 'package:admin/data/services/companies_api.dart';
import 'package:admin/ui/features/settings/view_models/company_details_view_model.dart';
import 'package:admin/ui/features/settings/view_models/payment_types_settings_view_model.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';

class _FakeCompaniesApi implements CompaniesApi {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A company row, an outbox of one, and a server whose echo is [echo] of
/// what was sent.
class _EchoRepo extends CompanyRepository {
  _EchoRepo({required super.db, required this.stored, required this.echo})
    : super(api: _FakeCompaniesApi());

  Company stored;
  CompanySettings Function(CompanySettings sent) echo;
  bool queued = false;
  int saves = 0;
  final _rows = StreamController<Company?>.broadcast();

  @override
  Stream<Company?> watchCompany(String companyId) {
    Future.microtask(() {
      if (!_rows.isClosed) _rows.add(stored);
    });
    return _rows.stream;
  }

  @override
  Future<void> refresh(String companyId) async {}

  @override
  Future<void> updateCompany({
    required Company draft,
    Map<String, dynamic>? extraOutboxPayload,
  }) async {
    saves++;
    stored = draft;
    queued = true;
    _rows.add(stored);
  }

  @override
  Future<bool> hasUnacceptedEdit(String companyId) async => queued;

  @override
  Future<Company?> get(String companyId) async => stored;

  /// The outbox drained: the server's echo replaces the optimistic copy.
  Future<void> drain() async {
    if (!queued) return;
    queued = false;
    stored = stored.copyWith(settings: echo(stored.settings));
    _rows.add(stored);
  }
}

CompanySettings _free(CompanySettings sent) =>
    // What a free hosted plan keeps: none of the three keys.
    CompanySettings(name: sent.name);

CompanySettings _keep(CompanySettings sent) => sent;

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const base = Company(
    id: 'co1',
    settings: CompanySettings(name: 'Acme', hiddenPaymentTypes: ''),
  );

  Future<(PaymentTypesSettingsViewModel, _EchoRepo)> paymentTypes(
    CompanySettings Function(CompanySettings) echo, {
    bool online = true,
  }) async {
    final repo = _EchoRepo(db: db, stored: base, echo: echo);
    final vm = PaymentTypesSettingsViewModel(
      repo: repo,
      companyId: 'co1',
      sendNow: online ? repo.drain : () async {},
    );
    addTearDown(vm.dispose);
    await vm.load();
    await pumpEventQueue();
    return (vm, repo);
  }

  void hideAndRename(SettingsDraftHost vm) => vm.updateSettings(
    (s) => s.copyWith(
      hiddenPaymentTypes: '1,25',
      translations: {'payment_type_Instant Bank Pay': 'Echtzeit'},
    ),
  );

  test('an echo that kept the hide and the rename saves', () async {
    final (vm, repo) = await paymentTypes(_keep);
    hideAndRename(vm);
    final saved = await vm.save();
    await pumpEventQueue();
    expect(saved, isNotNull);
    expect(vm.submitNeedsPaidPlan, isFalse);
    expect(vm.isDirty, isFalse);
    expect(repo.queued, isFalse);
  });

  test('an echo that dropped them fails the save with the plan flag and '
      'keeps the draft', () async {
    final (vm, repo) = await paymentTypes(_free);
    hideAndRename(vm);
    final saved = await vm.save();
    await pumpEventQueue();
    expect(saved, isNull);
    expect(vm.submitNeedsPaidPlan, isTrue);
    expect(repo.stored.settings.hiddenPaymentTypes, isNull);
    // Not silently reverted: the page still shows, dirty, what was chosen.
    expect(vm.settings.hiddenPaymentTypes, '1,25');
    expect(
      vm.settings.translations?['payment_type_Instant Bank Pay'],
      'Echtzeit',
    );
    expect(vm.isDirty, isTrue);
  });

  test('a rename alone that the echo dropped is caught too', () async {
    final (vm, _) = await paymentTypes(
      (sent) => sent.copyWith(translations: const {}),
    );
    vm.updateSettings(
      (s) => s.copyWith(translations: {'payment_type_Cash': 'Bargeld'}),
    );
    expect(await vm.save(), isNull);
    expect(vm.submitNeedsPaidPlan, isTrue);
  });

  test('offline the save stays queued and reads as saved', () async {
    final (vm, repo) = await paymentTypes(_free, online: false);
    hideAndRename(vm);
    expect(await vm.save(), isNotNull);
    expect(vm.submitNeedsPaidPlan, isFalse);
    expect(repo.queued, isTrue);
  });

  test('a save that left these settings alone sends nothing early', () async {
    var sent = 0;
    final repo = _EchoRepo(db: db, stored: base, echo: _free);
    final vm = PaymentTypesSettingsViewModel(
      repo: repo,
      companyId: 'co1',
      sendNow: () async => sent++,
    );
    addTearDown(vm.dispose);
    await vm.load();
    await pumpEventQueue();
    vm.updateSettings((s) => s.copyWith(name: 'Acme Ltd'));
    expect(await vm.save(), isNotNull);
    expect(sent, 0);
  });

  group('Company Details — documents public by default', () {
    Future<CompanyDetailsViewModel> details(
      CompanySettings Function(CompanySettings) echo,
    ) async {
      final repo = _EchoRepo(db: db, stored: base, echo: echo);
      final vm = CompanyDetailsViewModel(
        repo: repo,
        companyId: 'co1',
        sendNow: repo.drain,
      );
      addTearDown(vm.dispose);
      await vm.load();
      await pumpEventQueue();
      return vm;
    }

    test(
      'dropped by the echo: the plan flag, and the switch stays off',
      () async {
        final vm = await details(_free);
        vm.updateSettings((s) => s.copyWith(documentsPublicByDefault: false));
        expect(await vm.save(), isNull);
        expect(vm.submitNeedsPaidPlan, isTrue);
        expect(vm.settings.documentsPublicByDefault, isFalse);
        expect(vm.isDirty, isTrue);
      },
    );

    test('kept by the echo: saved', () async {
      final vm = await details(_keep);
      vm.updateSettings((s) => s.copyWith(documentsPublicByDefault: false));
      expect(await vm.save(), isNotNull);
      expect(vm.submitNeedsPaidPlan, isFalse);
    });
  });
}
