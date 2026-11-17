// The phone settings home's per-row values (R1): what each section says
// beside its title, from local sources only, and when it says nothing.

import 'dart:async';

import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/design.dart';
import 'package:admin/data/models/domain/enabled_modules.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/ui/features/settings/view_models/settings_home_summary_view_model.dart';
import 'package:admin/utils/formatting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Sources implements SettingsHomeSources {
  final companyCtl = StreamController<Company?>.broadcast();
  final gatewaysCtl = StreamController<int>.broadcast();
  final usersCtl = StreamController<int>.broadcast();
  final designsCtl = StreamController<List<Design>>.broadcast();
  final theme = ValueNotifier<ThemeMode>(ThemeMode.system);

  void close() {
    companyCtl.close();
    gatewaysCtl.close();
    usersCtl.close();
    designsCtl.close();
    theme.dispose();
  }

  @override
  Stream<Company?> company(String companyId) => companyCtl.stream;
  @override
  Stream<int> gatewayCount(String companyId) => gatewaysCtl.stream;
  @override
  Stream<int> userCount(String companyId) => usersCtl.stream;
  @override
  Stream<int> bankAccountCount(String companyId) => Stream.value(2);
  @override
  Stream<int> groupCount(String companyId) => Stream.value(0);
  @override
  Stream<int> paymentLinkCount(String companyId) => Stream.value(1);
  @override
  Stream<int> scheduleCount(String companyId) => const Stream.empty();
  @override
  Stream<List<Design>> designs(String companyId) => designsCtl.stream;
  @override
  Future<Formatter?> formatter(String companyId) async => Formatter(
    settings: CompanyFormatSettings.fallback,
    currencies: const {},
    countries: const {},
    dateFormats: const {},
  );
  @override
  Future<void> ensureStatics() async {}
  @override
  String? currencyCode(String currencyId) =>
      const {'1': 'USD', '3': 'EUR'}[currencyId];
  @override
  String? languageName(String languageId) =>
      const {'1': 'English', '3': 'Deutsch'}[languageId];
  @override
  ThemeMode get themeMode => theme.value;
  @override
  Listenable get themeChanges => theme;
}

Design _design(String id, String name) => Design(
  id: id,
  name: name,
  isCustom: true,
  isActive: true,
  isTemplate: false,
  isFree: true,
  entities: const ['invoice'],
  template: const DesignTemplate(),
  updatedAt: DateTime.utc(2026),
  createdAt: DateTime.utc(2026),
  archivedAt: null,
  isDeleted: false,
);

const _allModules = 4096 | 4 | 2 | 16384;

AuthSession _session({
  bool hosted = true,
  String plan = 'pro',
  int trialDaysLeft = -1,
}) => AuthSession(
  baseUrl: 'https://invoicing.co',
  isHosted: hosted,
  accountId: 'a',
  companies: const [],
  currentCompanyId: 'c1',
  plan: plan,
  trialDaysLeft: trialDaysLeft,
);

void main() {
  late _Sources sources;
  late SettingsHomeSummaryViewModel vm;

  setUp(() {
    sources = _Sources();
    vm = SettingsHomeSummaryViewModel(companyId: 'c1', sources: sources);
  });

  tearDown(() {
    vm.dispose();
    sources.close();
  });

  String tr(String key) => switch (key) {
    'no_gateway_connected' => 'No gateway',
    'disabled' => 'Disabled',
    'match_system' => 'Match system',
    'dark' => 'Dark',
    'free_trial' => 'Free trial',
    'pro' => 'Pro',
    'free' => 'Free',
    _ => key,
  };

  SettingsHomeValue? value(
    String slug, {
    AuthSession? session,
    bool rtl = false,
  }) => vm.valueFor(slug, tr: tr, session: session, rtl: rtl);

  Future<void> emitCompany(Company c) async {
    sources.companyCtl.add(c);
    // The stream event, then the formatter future it starts.
    await pumpEventQueue();
  }

  test('nothing is claimed before a source answers', () {
    expect(value('localization'), isNull);
    expect(value('online_payments'), isNull);
    expect(value('users'), isNull);
    expect(value('invoice_design'), isNull);
  });

  test('Localization reads the currency code and the language name', () async {
    await emitCompany(
      const Company(
        id: 'c1',
        settings: CompanySettings(currencyId: '3', languageId: '3'),
      ),
    );
    expect(
      value('localization'),
      const SettingsHomeValue.text('EUR · Deutsch'),
    );
    // Right to left, the code is isolated so it reads EUR, not RUE.
    expect(value('localization', rtl: true)!.text, '\u2066EUR\u2069 · Deutsch');
  });

  test(
    'Online Payments counts gateways, or warns when there are none',
    () async {
      sources.gatewaysCtl.add(0);
      await pumpEventQueue();
      expect(
        value('online_payments'),
        const SettingsHomeValue.warning('No gateway'),
      );
      sources.gatewaysCtl.add(2);
      await pumpEventQueue();
      expect(value('online_payments'), const SettingsHomeValue.count(2));
    },
  );

  test(
    'a count of zero draws nothing; a stream that never answers neither',
    () async {
      sources.usersCtl.add(0);
      await pumpEventQueue();
      expect(value('users'), isNull);
      sources.usersCtl.add(4);
      await pumpEventQueue();
      expect(value('users'), const SettingsHomeValue.count(4));
      expect(value('bank_accounts'), const SettingsHomeValue.count(2));
      expect(value('payment_links'), const SettingsHomeValue.count(1));
      expect(value('group_settings'), isNull);
      expect(value('schedules'), isNull);
    },
  );

  test(
    'Tax lists the named default rates in the slots the company shows',
    () async {
      await emitCompany(
        const Company(
          id: 'c1',
          enabledTaxRates: 2,
          settings: CompanySettings(
            taxName1: 'VAT',
            taxRate1: 20,
            taxName2: 'GST',
            taxRate2: 5.5,
            taxName3: 'Hidden',
            taxRate3: 1,
          ),
        ),
      );
      expect(
        value('tax_settings'),
        const SettingsHomeValue.text('VAT 20% · GST 5.5%'),
      );

      await emitCompany(const Company(id: 'c1', enabledTaxRates: 1));
      expect(value('tax_settings'), isNull, reason: 'no named default');
    },
  );

  test('Invoice Design names up to two distinct designs, then +n', () async {
    await emitCompany(
      const Company(
        id: 'c1',
        enabledModules: _allModules,
        settings: CompanySettings(
          invoiceDesignId: 'Wpmbk5ezJn', // Plain
          quoteDesignId: 'Wpmbk5ezJn',
          creditDesignId: 'VolejRejNm', // Clean
          purchaseOrderDesignId: 'custom1',
        ),
      ),
    );
    sources.designsCtl.add([_design('custom1', 'Ours')]);
    await pumpEventQueue();
    expect(
      value('invoice_design'),
      const SettingsHomeValue.text('Plain · Clean +1'),
    );

    // A module that is off doesn't count its design.
    await emitCompany(
      const Company(
        id: 'c1',
        enabledModules: 4096,
        settings: CompanySettings(
          invoiceDesignId: 'Wpmbk5ezJn',
          purchaseOrderDesignId: 'custom1',
        ),
      ),
    );
    expect(value('invoice_design'), const SettingsHomeValue.text('Plain'));
  });

  test('Client Portal shows the portal host, or Disabled', () async {
    await emitCompany(const Company(id: 'c1', subdomain: 'acme'));
    expect(
      value('client_portal', session: _session()),
      const SettingsHomeValue.text('acme.invoicing.co'),
    );
    await emitCompany(
      const Company(
        id: 'c1',
        subdomain: 'acme',
        settings: CompanySettings(enableClientPortal: false),
      ),
    );
    expect(
      value('client_portal', session: _session()),
      const SettingsHomeValue.text('Disabled'),
    );
  });

  test('E-Invoice shows its format only while enabled', () async {
    await emitCompany(
      const Company(
        id: 'c1',
        settings: CompanySettings(eInvoiceType: 'PEPPOL'),
      ),
    );
    expect(value('e_invoice'), isNull);
    await emitCompany(
      const Company(
        id: 'c1',
        settings: CompanySettings(enableEInvoice: true, eInvoiceType: 'PEPPOL'),
      ),
    );
    expect(value('e_invoice'), const SettingsHomeValue.text('PEPPOL'));
  });

  test('Custom Fields counts the slots that have a label', () async {
    await emitCompany(
      const Company(
        id: 'c1',
        customFields: {
          'client1': 'Region|single_line_text',
          'client2': '',
          'invoice1': '|date',
          'task1': 'Billable code',
        },
      ),
    );
    expect(value('custom_fields'), const SettingsHomeValue.count(2));
  });

  test('Account Management names the hosted plan only', () {
    expect(
      value('account_management', session: _session()),
      const SettingsHomeValue.text('Pro'),
    );
    expect(
      value(
        'account_management',
        session: _session(plan: 'free', trialDaysLeft: 5),
      ),
      const SettingsHomeValue.text('Free · Free trial'),
    );
    expect(
      value('account_management', session: _session(hosted: false)),
      isNull,
    );
  });

  test('Device Settings follows the theme preference live', () {
    expect(
      value('device_settings'),
      const SettingsHomeValue.text('Match system'),
    );
    var notified = 0;
    vm.addListener(() => notified++);
    sources.theme.value = ThemeMode.dark;
    expect(notified, 1);
    expect(value('device_settings'), const SettingsHomeValue.text('Dark'));
  });

  test('a section with nothing to say is plain', () {
    expect(value('company_details'), isNull);
    expect(value('tags'), isNull);
    expect(isModuleEnabled(_allModules, EnabledModule.quotes), isTrue);
  });
}
