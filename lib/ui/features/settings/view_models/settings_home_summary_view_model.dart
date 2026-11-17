import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/design.dart';
import 'package:admin/data/models/domain/enabled_modules.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/data/static/built_in_designs_catalog.dart';
import 'package:admin/domain/client_portal_urls.dart';
import 'package:admin/ui/features/settings/views/basic/account_management/plan_screen.dart'
    show planHeadlineKey;
import 'package:admin/utils/bidi.dart';
import 'package:admin/utils/formatting.dart';

/// What the phone settings home says beside one section row (R1 of the
/// settings pass): a one-line [text] under the title, a trailing [count], or
/// a trailing [warning] icon whose sentence is the screen reader's. At most
/// one is set. → docs/settings-screens.md § The phone settings home shows each
/// section's current value.
@immutable
class SettingsHomeValue {
  const SettingsHomeValue.text(String this.text) : count = null, warning = null;
  const SettingsHomeValue.count(int this.count) : text = null, warning = null;
  const SettingsHomeValue.warning(String this.warning)
    : text = null,
      count = null;

  final String? text;
  final int? count;
  final String? warning;

  @override
  bool operator ==(Object other) =>
      other is SettingsHomeValue &&
      other.text == text &&
      other.count == count &&
      other.warning == warning;

  @override
  int get hashCode => Object.hash(text, count, warning);

  @override
  String toString() => text != null
      ? 'text($text)'
      : count != null
      ? 'count($count)'
      : 'warning($warning)';
}

/// Where [SettingsHomeSummaryViewModel] reads from — every source local
/// (Drift, the statics cache, a device preference), never the network. A seam
/// so a widget test can drive the home without a whole [Services] graph.
abstract class SettingsHomeSources {
  /// The production sources.
  factory SettingsHomeSources.of(Services services) = _ServicesSources;

  Stream<Company?> company(String companyId);

  /// Active (not archived, not deleted) rows of each bundled table.
  Stream<int> gatewayCount(String companyId);
  Stream<int> userCount(String companyId);
  Stream<int> bankAccountCount(String companyId);
  Stream<int> groupCount(String companyId);
  Stream<int> paymentLinkCount(String companyId);
  Stream<int> scheduleCount(String companyId);
  Stream<List<Design>> designs(String companyId);

  /// The company's [Formatter]; null when it can't be built.
  Future<Formatter?> formatter(String companyId);

  /// Warms the statics cache the two lookups below read.
  Future<void> ensureStatics();
  String? currencyCode(String currencyId);
  String? languageName(String languageId);

  /// The device theme preference, and what notifies when it changes.
  ThemeMode get themeMode;
  Listenable get themeChanges;
}

class _ServicesSources implements SettingsHomeSources {
  _ServicesSources(this._s);
  final Services _s;

  @override
  Stream<Company?> company(String companyId) =>
      _s.company.watchCompany(companyId);
  @override
  Stream<int> gatewayCount(String companyId) =>
      _s.companyGateways.watchCount(companyId: companyId);
  @override
  Stream<int> userCount(String companyId) => _s.user
      .watchAllForPicker(companyId: companyId)
      .map((u) => u.where((x) => !x.isDeleted && x.archivedAt == 0).length);
  @override
  Stream<int> bankAccountCount(String companyId) =>
      _s.bankAccounts.watchCount(companyId: companyId);
  @override
  Stream<int> groupCount(String companyId) => _s.groupSettings
      .watchAll(companyId: companyId)
      .map((rows) => rows.length);
  @override
  Stream<int> paymentLinkCount(String companyId) =>
      _s.db.paymentLinkDao.watchCount(companyId: companyId);
  @override
  Stream<int> scheduleCount(String companyId) =>
      _s.schedules.watchAll(companyId: companyId).map((rows) => rows.length);
  @override
  Stream<List<Design>> designs(String companyId) =>
      _s.designs.watchAll(companyId: companyId);
  @override
  Future<Formatter?> formatter(String companyId) =>
      _s.formatterFor(companyId).then<Formatter?>((f) => f);
  @override
  Future<void> ensureStatics() => _s.statics.ensureLoaded();
  @override
  String? currencyCode(String currencyId) =>
      _s.statics.currencies[currencyId]?.code;
  @override
  String? languageName(String languageId) =>
      _s.statics.languages[languageId]?.name;
  @override
  ThemeMode get themeMode => _s.theme.themeMode;
  @override
  Listenable get themeChanges => _s.theme;
}

/// The phone settings home's current values, for one company, merged from
/// local streams. Lives in the home's `State`, keyed on the company id, and
/// opens every stream once — never in a `build`.
///
/// [valueFor] answers per section slug; null means the row is plain. It never
/// claims a value it hasn't read: a count or a warning appears only once its
/// stream has answered.
class SettingsHomeSummaryViewModel extends ChangeNotifier {
  SettingsHomeSummaryViewModel({
    required this.companyId,
    required SettingsHomeSources sources,
  }) : _sources = sources {
    _subs = [
      sources.company(companyId).listen(_onCompany),
      sources.gatewayCount(companyId).listen((n) => _set(() => _gateways = n)),
      sources.userCount(companyId).listen((n) => _set(() => _users = n)),
      sources
          .bankAccountCount(companyId)
          .listen((n) => _set(() => _bankAccounts = n)),
      sources.groupCount(companyId).listen((n) => _set(() => _groups = n)),
      sources
          .paymentLinkCount(companyId)
          .listen((n) => _set(() => _paymentLinks = n)),
      sources
          .scheduleCount(companyId)
          .listen((n) => _set(() => _schedules = n)),
      sources.designs(companyId).listen((d) => _set(() => _designs = d)),
    ];
    sources.themeChanges.addListener(_onTheme);
    _themeMode = sources.themeMode;
    unawaited(
      sources.ensureStatics().then(
        (_) => _set(() => _staticsReady = true),
        onError: (Object _) {},
      ),
    );
  }

  final String companyId;
  final SettingsHomeSources _sources;
  late final List<StreamSubscription<Object?>> _subs;
  bool _disposed = false;

  Company? _company;
  Formatter? _formatter;
  int? _gateways;
  int? _users;
  int? _bankAccounts;
  int? _groups;
  int? _paymentLinks;
  int? _schedules;
  List<Design>? _designs;
  bool _staticsReady = false;
  late ThemeMode _themeMode;

  void _onCompany(Company? company) {
    _set(() => _company = company);
    // Re-read on every change: a settings save invalidates the cached
    // formatter (`Services.invalidateFormatter`), and the tax line is
    // formatted with the company's separators.
    unawaited(
      _sources
          .formatter(companyId)
          .then((f) => _set(() => _formatter = f), onError: (Object _) {}),
    );
  }

  void _onTheme() {
    final mode = _sources.themeMode;
    if (mode != _themeMode) _set(() => _themeMode = mode);
  }

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sources.themeChanges.removeListener(_onTheme);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  /// The value beside section [slug], or null for a plain row. [tr] is the
  /// active localization's lookup; [rtl] isolates the codes and domains that
  /// must read left to right inside a right-to-left line.
  SettingsHomeValue? valueFor(
    String slug, {
    required String Function(String key) tr,
    required AuthSession? session,
    bool rtl = false,
  }) {
    String ltr(String s) => rtl ? ltrIsolate(s) : s;
    SettingsHomeValue? count(int? n) =>
        n == null || n <= 0 ? null : SettingsHomeValue.count(n);
    SettingsHomeValue? text(Iterable<String> parts) {
      final s = parts.where((p) => p.isNotEmpty).join(' · ');
      return s.isEmpty ? null : SettingsHomeValue.text(s);
    }

    final company = _company;
    final settings = company?.settings;
    switch (slug) {
      case 'localization':
        if (settings == null || !_staticsReady) return null;
        return text([
          ltr(_sources.currencyCode(settings.currencyId ?? '') ?? ''),
          _sources.languageName(settings.languageId ?? '') ?? '',
        ]);
      case 'online_payments':
        final n = _gateways;
        if (n == null) return null;
        return n > 0
            ? SettingsHomeValue.count(n)
            : SettingsHomeValue.warning(tr('no_gateway_connected'));
      case 'tax_settings':
        final f = _formatter;
        if (company == null || settings == null || f == null) return null;
        // The slots the Tax Settings page shows: the invoice-level rates, or
        // the item-level ones when the company taxes per line only.
        final slots = company.enabledTaxRates > 0
            ? company.enabledTaxRates
            : company.enabledItemTaxRates;
        final rates = [
          (settings.taxName1, settings.taxRate1),
          (settings.taxName2, settings.taxRate2),
          (settings.taxName3, settings.taxRate3),
        ].take(slots.clamp(0, 3));
        return text([
          for (final (name, rate) in rates)
            if ((name ?? '').trim().isNotEmpty)
              '${name!.trim()} ${ltr(f.percent(rate ?? 0))}',
        ]);
      case 'account_management':
        if (session == null || !session.isHosted) return null;
        final plan = tr(planHeadlineKey(session));
        return text([plan, if (session.isTrial) tr('free_trial')]);
      case 'invoice_design':
        if (company == null || settings == null || _designs == null) {
          return null;
        }
        return _designValue(company, settings);
      case 'client_portal':
        if (company == null || settings == null) return null;
        if (!(settings.enableClientPortal ?? true)) {
          return SettingsHomeValue.text(tr('disabled'));
        }
        final url = clientPortalUrl(
          page: ClientPortalPage.login,
          isHosted: session?.isHosted ?? false,
          portalMode: company.portalMode,
          subdomain: company.subdomain,
          portalDomain: company.portalDomain,
          companyKey: company.companyKey,
        );
        final host = Uri.tryParse(url)?.host ?? '';
        return host.isEmpty ? null : SettingsHomeValue.text(ltr(host));
      case 'e_invoice':
        if (settings == null || !(settings.enableEInvoice ?? false)) {
          return null;
        }
        final type = settings.eInvoiceType ?? '';
        return text([ltr(type.isEmpty ? 'EN16931' : type)]);
      case 'device_settings':
        return SettingsHomeValue.text(switch (_themeMode) {
          ThemeMode.system => tr('match_system'),
          ThemeMode.light => tr('light'),
          ThemeMode.dark => tr('dark'),
        });
      case 'custom_fields':
        if (company == null) return null;
        return count(
          company.customFields.values
              .where((v) => v.split('|').first.trim().isNotEmpty)
              .length,
        );
      case 'users':
        return count(_users);
      case 'bank_accounts':
        return count(_bankAccounts);
      case 'group_settings':
        return count(_groups);
      case 'payment_links':
        return count(_paymentLinks);
      case 'schedules':
        return count(_schedules);
    }
    return null;
  }

  /// The designs the Invoice Design page's pickers name, for the documents
  /// the company uses: up to two names, then "+n".
  SettingsHomeValue? _designValue(Company company, CompanySettings settings) {
    final modules = company.enabledModules;
    bool on(EnabledModule m) => isModuleEnabled(modules, m);
    final ids = [
      if (on(EnabledModule.invoices)) settings.invoiceDesignId,
      if (on(EnabledModule.quotes)) settings.quoteDesignId,
      if (on(EnabledModule.credits)) settings.creditDesignId,
      if (on(EnabledModule.purchaseOrders)) settings.purchaseOrderDesignId,
    ];
    final bundled = {for (final d in _designs!) d.id: d.name};
    final names = <String>[];
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      final name = bundled[id] ?? kBuiltInDesignNamesById[id];
      if (name == null || name.trim().isEmpty) continue;
      if (!names.contains(name.trim())) names.add(name.trim());
    }
    if (names.isEmpty) return null;
    final shown = names.take(2).join(' · ');
    final more = names.length - 2;
    return SettingsHomeValue.text(more > 0 ? '$shown +$more' : shown);
  }
}
