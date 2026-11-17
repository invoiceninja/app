import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/invoice_status.dart';
import 'package:admin/data/models/domain/quote.dart';
import 'package:admin/data/models/domain/quote_status.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/client_repository.dart';
import 'package:admin/data/repositories/ensure_loaded_outcome.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/data/repositories/payment_repository.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/data/repositories/quote_repository.dart';
import 'package:admin/domain/entity_registry.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/domain/sync/sync_dispatcher.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/core/list/entity_list_status_tabs.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/payments/view_models/payment_edit_view_model.dart';
import 'package:admin/ui/features/quotes/view_models/quote_edit_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/billing_pipeline_card.dart';
import 'package:admin/ui/features/quotes/widgets/quote_status_pill.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../_localization_helper.dart';

/// The stateful half of the Invoices & Quotes panel. What is asserted here is
/// everything that is silent if it breaks: that it keeps itself alive when
/// scrolled out of the dashboard's `ListView`, that the company rebind and the
/// refresh hook fire, that a tab tap re-subscribes the right halves, and — the
/// one no other test in this repo could catch — that a quote-only tab never
/// asks the invoice side for a mode its DAO would ignore.

/// A one-value stream that survives re-subscription: the card's view model
/// listens once, but a tab switch or a rebuild listens again, and a
/// single-subscription stream would throw the second time.
Stream<T> _multi<T>(T value) => Stream<T>.multi((c) {
  c.add(value);
  c.close();
});

Invoice _invoice(String id, {InvoiceStatus? status}) => emptyInvoice().copyWith(
  id: id,
  number: id,
  clientId: 'c1',
  statusId: status ?? InvoiceStatus.sent,
  date: Date(2026, 9, 14),
  amount: Decimal.fromInt(100),
  balance: Decimal.fromInt(100),
  createdAt: DateTime.utc(2026, 9, 14),
);

Quote _quote(String id, {QuoteStatus? status}) => emptyQuote().copyWith(
  id: id,
  number: id,
  clientId: 'c1',
  statusId: status ?? QuoteStatus.draft,
  date: Date(2026, 9, 13),
  amount: Decimal.fromInt(50),
  balance: Decimal.fromInt(50),
  createdAt: DateTime.utc(2026, 9, 13),
);

class _FakeInvoiceRepo implements InvoiceRepository {
  _FakeInvoiceRepo({this.rows = const []});
  List<Invoice> rows;

  /// Throws *before* any `await`, the one shape that can outrun the caller's
  /// in-flight bookkeeping.
  bool throwSynchronously = false;
  int fetchAttempts = 0;
  final List<String?> watchedModes = [];
  final List<Map<String, Set<String>>> fetches = [];
  final List<bool> fetchIgnoredCursor = [];

  @override
  Stream<List<Invoice>> watchRecent({
    required String companyId,
    required int limit,
    String? badgeModeId,
    Set<EntityState> states = const {EntityState.active},
  }) {
    watchedModes.add(badgeModeId);
    return _multi(rows);
  }

  @override
  Future<bool> ensurePageLoaded({
    required String companyId,
    required int page,
    String? search,
    Set<EntityState> states = const {EntityState.active},
    Map<String, Set<String>> extraFilters = const {},
    bool ignoreCursor = false,
  }) {
    fetchAttempts++;
    if (throwSynchronously) throw StateError('boom');
    fetches.add(extraFilters);
    fetchIgnoredCursor.add(ignoreCursor);
    return Future<bool>.value(false);
  }

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeQuoteRepo implements QuoteRepository {
  _FakeQuoteRepo({this.rows = const []});
  List<Quote> rows;

  /// Makes `ensurePageLoaded` report another page, so a bounded walk walks.
  bool hasMore = false;
  final List<String?> watchedModes = [];
  final List<Map<String, Set<String>>> fetches = [];

  @override
  Stream<List<Quote>> watchRecent({
    required String companyId,
    required int limit,
    String? badgeModeId,
    Set<EntityState> states = const {EntityState.active},
  }) {
    watchedModes.add(badgeModeId);
    return _multi(rows);
  }

  @override
  Future<bool> ensurePageLoaded({
    required String companyId,
    required int page,
    String? search,
    Set<EntityState> states = const {EntityState.active},
    Map<String, Set<String>> extraFilters = const {},
    bool ignoreCursor = false,
  }) async {
    fetches.add(extraFilters);
    return hasMore;
  }

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeClientRepo implements ClientRepository {
  @override
  Future<EnsureLoadedOutcome> ensureLoaded({
    required String companyId,
    required String id,
  }) async => EnsureLoadedOutcome.cached;

  @override
  Client? peek({required String companyId, required String id}) => null;

  @override
  Stream<Client?> watch({required String companyId, required String id}) =>
      _multi<Client?>(null);

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

EntityHandlers _handlers(
  EntityType type,
  String wire,
  String route,
  List<SidebarBadgeMode> modes,
) => EntityHandlers(
  type: type,
  wireName: wire,
  apiPath: route,
  routePath: route,
  icon: Icons.receipt_long,
  dispatcher: _NoopDispatcher(),
  badgeModes: modes,
  // Non-null so `entityRecordPath` resolves to `/<route>/<id>` rather than
  // appending `/edit` — the panel opens the detail screen.
  detailBuilder: (_, _) => const SizedBox.shrink(),
);

class _NoopDispatcher implements SyncDispatcher {
  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// `ClientNameLabel` reads the active company off the session to scope its
/// lookup, so a card that renders a single row needs this seam too.
class _FakeAuth implements AuthRepository {
  @override
  final ValueNotifier<AuthSession?> session = ValueNotifier<AuthSession?>(null);
  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Each invoice's payments, for a paid row's "Paid Nov 16".
class _FakePaymentRepo implements PaymentRepository {
  _FakePaymentRepo(this.byInvoice);
  final Map<String, List<Payment>> byInvoice;

  @override
  Stream<List<Payment>> watchForInvoice({
    required String companyId,
    required String invoiceId,
  }) => _multi(byInvoice[invoiceId] ?? const <Payment>[]);

  @override
  Object? noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeServices implements Services {
  _FakeServices({
    required this.invoices,
    required this.quotes,
    required this.clients,
    this.counts = const {},
    PaymentRepository? payments,
  }) : _payments = payments;

  final PaymentRepository? _payments;

  /// Unset in most suites: the card then never learns a paid date, and a lookup
  /// that throws must leave the row on its invoice date.
  @override
  PaymentRepository get payments =>
      _payments ?? (throw UnimplementedError('payments'));

  /// Each tab's count by mode id; a mode not named here counts 1, so the
  /// occasional tabs (`kOccasionalBillingTabs`) are on the strip.
  final Map<String, int> counts;
  @override
  final InvoiceRepository invoices;
  @override
  final QuoteRepository quotes;
  @override
  final ClientRepository clients;
  @override
  final AuthRepository auth = _FakeAuth();

  final List<(EntityType, String)> counted = [];

  // The card builds its tab set from the two entities' own `badgeModes` and
  // resolves a row tap through `routePath`, so both have to be real — the
  // catalogs especially: with the default two-mode fallback the strip would
  // collapse to `All` and every tab assertion here would pass vacuously.
  @override
  final EntityRegistry entityRegistry = EntityRegistry({
    EntityType.invoice: _handlers(
      EntityType.invoice,
      'invoice',
      '/invoices',
      kInvoiceBadgeModes,
    ),
    EntityType.quote: _handlers(
      EntityType.quote,
      'quote',
      '/quotes',
      kQuoteBadgeModes,
    ),
  });

  @override
  Stream<int> watchEntityCount(
    EntityType type,
    String companyId, {
    String modeId = 'total',
  }) {
    counted.add((type, modeId));
    return _multi(counts[modeId] ?? 1);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError(i.memberName.toString());
}

final _formatter = Formatter(
  settings: const CompanyFormatSettings(
    currencyId: '1',
    countryId: '840',
    dateFormatId: '5',
    useCommaAsDecimalPlace: false,
    showCurrencyCode: false,
    enableMilitaryTime: false,
    locale: 'en',
  ),
  currencies: const {},
  countries: const {},
  dateFormats: const {},
);

class _Nav {
  String? location;
}

/// Props swappable **without** remounting, so `didUpdateWidget`'s branches are
/// genuinely exercised rather than satisfied by a fresh element.
class _Props {
  const _Props({this.companyId = 'co', this.refreshNonce, this.initialTabId});
  final String companyId;
  final DateTime? refreshNonce;

  /// Swappable so a test can deliver the restored tab AFTER mount, which is
  /// the only ordering production ever produces.
  final String? initialTabId;
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeServices services,
  required _Nav nav,
  ValueNotifier<_Props>? props,
  bool narrow = true,
  bool tall = false,
  EntityType entity = EntityType.quote,
  String? initialTabId,
  void Function(String?)? onTabChanged,
  ScrollController? controller,
}) async {
  final p = props ?? ValueNotifier(const _Props());
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: ListView(
            controller: controller,
            children: [
              if (tall) const SizedBox(height: 2000),
              ValueListenableBuilder<_Props>(
                valueListenable: p,
                builder: (context, v, _) => DashboardBillingPipelineCard(
                  companyId: v.companyId,
                  formatter: _formatter,
                  refreshNonce: v.refreshNonce,
                  narrow: narrow,
                  entity: entity,
                  initialTabId: v.initialTabId ?? initialTabId,
                  onTabChanged: onTabChanged ?? (_) {},
                ),
              ),
              if (tall) const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
      for (final path in ['/invoices', '/quotes'])
        GoRoute(
          path: path,
          builder: (context, state) {
            nav.location = state.uri.toString();
            return Scaffold(body: Text('list $path'));
          },
        ),
      GoRoute(
        path: '/invoices/:id',
        builder: (context, state) {
          nav.location = state.uri.toString();
          return const Scaffold(body: Text('invoice'));
        },
      ),
      GoRoute(
        path: '/quotes/:id',
        builder: (context, state) {
          nav.location = state.uri.toString();
          return const Scaffold(body: Text('quote'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    Provider<Services>.value(
      value: services,
      child: MaterialApp.router(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

_FakeServices _services({
  List<Invoice> invoices = const [],
  List<Quote> quotes = const [],
  Map<String, int> counts = const {},
  PaymentRepository? payments,
}) => _FakeServices(
  invoices: _FakeInvoiceRepo(rows: invoices),
  quotes: _FakeQuoteRepo(rows: quotes),
  clients: _FakeClientRepo(),
  counts: counts,
  payments: payments,
);

/// intl ships only `en_US` initialised; the app loads the rest through
/// `GlobalMaterialLocalizations`, and a row that formats a date needs them.
Future<void> _loadDateSymbols() =>
    GlobalMaterialLocalizations.delegate.load(const Locale('en'));

int _selectedIndex(WidgetTester tester) => tester
    .widget<EntityListStatusTabs>(find.byType(EntityListStatusTabs))
    .selectedIndex;

/// Position of a tab in the live strip. Derived rather than written as a
/// literal: these assertions are about *which* tab is selected, and a literal
/// index silently becomes an assertion about the strip's length too — adding
/// `cancelled` broke four of them at once.
int _indexOfTab(WidgetTester tester, String labelKey) {
  final i = tester
      .widget<EntityListStatusTabs>(find.byType(EntityListStatusTabs))
      .tabs
      .indexWhere((t) => t.labelKey == labelKey);
  // Both this and the card's own `selectedIndex` are `indexWhere`, so both
  // return -1 for a tab that left the strip — and `-1 == -1` would pass while
  // asserting nothing. Fail here instead.
  expect(i, isNonNegative, reason: 'no "$labelKey" tab in the strip');
  return i;
}

void main() {
  setUpAll(_loadDateSymbols);

  testWidgets('renders the strip with All selected', (tester) async {
    await _pump(tester, services: _services(), nav: _Nav());
    expect(find.byType(EntityListStatusTabs), findsOneWidget);
    final strip = tester.widget<EntityListStatusTabs>(
      find.byType(EntityListStatusTabs),
    );
    expect(strip.selectedIndex, 0);
    // Wrapped, not scrolled: the whole point is that no count is off-screen.
    expect(strip.wrap, isTrue);
    expect(strip.tabs.map((t) => t.labelKey), [
      'all',
      'draft',
      'sent',
      'approved',
      'rejected',
      'cancelled',
      'expired',
    ]);
  });

  testWidgets(
    'Rejected, Cancelled and Expired show only with something in them',
    (tester) async {
      await _pump(
        tester,
        services: _services(
          counts: const {'rejected': 0, 'cancelled': 0, 'expired': 2},
        ),
        nav: _Nav(),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EntityListStatusTabs>(find.byType(EntityListStatusTabs))
            .tabs
            .map((t) => t.labelKey),
        ['all', 'draft', 'sent', 'approved', 'expired'],
      );
    },
  );

  testWidgets('an empty occasional tab stays while it is the selected one', (
    tester,
  ) async {
    // A restored tab must not vanish from under the user, nor leave the strip
    // with nothing selected.
    await _pump(
      tester,
      services: _services(
        counts: const {'rejected': 0, 'cancelled': 0, 'expired': 0},
      ),
      nav: _Nav(),
      initialTabId: 'rejected',
    );
    await tester.pumpAndSettle();
    final strip = tester.widget<EntityListStatusTabs>(
      find.byType(EntityListStatusTabs),
    );
    expect(strip.tabs.map((t) => t.labelKey), [
      'all',
      'draft',
      'sent',
      'approved',
      'rejected',
    ]);
    expect(strip.selectedIndex, 4);
  });

  testWidgets(
    'the Invoices card has the Invoices list\'s tabs, Overdue included',
    (tester) async {
      await _pump(
        tester,
        services: _services(),
        nav: _Nav(),
        entity: EntityType.invoice,
      );
      expect(
        tester
            .widget<EntityListStatusTabs>(find.byType(EntityListStatusTabs))
            .tabs
            .map((t) => t.labelKey),
        ['all', 'draft', 'unpaid', 'overdue', 'paid'],
      );
    },
  );

  testWidgets('the Quotes card never asks invoices for anything', (
    tester,
  ) async {
    // `InvoiceDao.badgeModePredicate` returns null for 'approved', and both
    // DAO seams treat null as "no narrowing" — so a quote mode reaching the
    // invoice side would list and count EVERY invoice in the company, and it
    // would type-check.
    final services = _services();
    await _pump(tester, services: services, nav: _Nav());

    await tester.tap(find.text('Approved'));
    await tester.pumpAndSettle();

    final invoiceRepo = services.invoices as _FakeInvoiceRepo;
    final quoteRepo = services.quotes as _FakeQuoteRepo;
    expect(invoiceRepo.watchedModes, isEmpty);
    expect(invoiceRepo.fetches, isEmpty);
    expect(quoteRepo.watchedModes, contains('approved'));
    expect(
      services.counted.where((c) => c.$1 == EntityType.invoice),
      isEmpty,
      reason: 'the count seam fails open the same way the row seam does',
    );
    expect(services.counted, contains((EntityType.quote, 'approved')));
  });

  testWidgets('the Invoices card never asks quotes for anything', (
    tester,
  ) async {
    final services = _services();
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      entity: EntityType.invoice,
    );
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    expect(
      (services.invoices as _FakeInvoiceRepo).watchedModes,
      contains('draft'),
    );
    expect((services.quotes as _FakeQuoteRepo).watchedModes, isEmpty);
    expect(services.counted.where((c) => c.$1 == EntityType.quote), isEmpty);
  });

  testWidgets('the top-up ignores the cursor, or it fetches only a delta', (
    tester,
  ) async {
    // An unnarrowed fetch is not a "narrowed fetch", so without `ignoreCursor`
    // `shouldReadCursor` sends the `updated_at >=` watermark and returns the
    // delta rather than a true first page — which would make the local-only
    // Rejected tab's top-up do nothing at all.
    final services = _services();
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();
    final repo = services.invoices as _FakeInvoiceRepo;
    expect(repo.fetchIgnoredCursor, isNotEmpty);
    expect(repo.fetchIgnoredCursor.every((v) => v), isTrue);
  });

  testWidgets('the All tab costs one request, not five', (tester) async {
    // `All` is the tab each panel opens on, so this runs on the app's LANDING
    // route. A five-page walk would add requests to the cold-start fan-out to
    // fill rows that page 1 — sorted newest-first — already contains.
    final services = _services();
    await _pump(tester, services: services, nav: _Nav());
    await tester.pumpAndSettle();
    expect((services.quotes as _FakeQuoteRepo).fetches, hasLength(1));
  });

  testWidgets('a local-only tab walks pages; a server-narrowed one does not', (
    tester,
  ) async {
    // Rejected sends nothing (the server has no `client_status=rejected`), so
    // its rows can sit arbitrarily deep and the walk is the only mechanism it
    // has to reach the cache. Draft narrows server-side, so page 1 is enough.
    final deep = _FakeQuoteRepo()..hasMore = true;
    final services = _FakeServices(
      invoices: _FakeInvoiceRepo(),
      quotes: deep,
      clients: _FakeClientRepo(),
    );
    await _pump(tester, services: services, nav: _Nav());
    await tester.pumpAndSettle();
    deep.fetches.clear();

    await tester.tap(find.text('Rejected'));
    await tester.pumpAndSettle();
    expect(deep.fetches.length, greaterThan(1));
    expect(deep.fetches.every((f) => f.isEmpty), isTrue, reason: 'unnarrowed');

    deep.fetches.clear();
    await tester.tap(find.text('Approved'));
    await tester.pumpAndSettle();
    expect(deep.fetches, hasLength(1));
    expect(deep.fetches.single, {
      'client_status': {'approved'},
    });
  });

  testWidgets('a synchronously-throwing fetch does not latch the tab off', (
    tester,
  ) async {
    // `_sweep` is `async`, so a throw before its first suspension runs the
    // body — `catch` and `finally` included — SYNCHRONOUSLY, i.e. before the
    // caller can store the in-flight future. A `finally` that released the key
    // there would leave an already-completed future parked in the map forever:
    // every later attempt returns it instantly, the tab is never marked
    // loaded, and `invalidateLoadedTabs` (which clears only `_loadedTabs`)
    // cannot recover it. Production repos suspend first, so only a
    // sync-throwing double reaches this — which is exactly what the widget
    // suites use.
    final throwing = _FakeInvoiceRepo()..throwSynchronously = true;
    final services = _FakeServices(
      invoices: throwing,
      quotes: _FakeQuoteRepo(),
      clients: _FakeClientRepo(),
    );
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();

    // The SAME bucket, twice — a different tab would take a different key and
    // pass either way, which is what makes this the only shape that catches it.
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    final afterFirst = throwing.fetchAttempts;
    expect(afterFirst, greaterThan(0), reason: 'it tried once');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    expect(
      throwing.fetchAttempts,
      greaterThan(afterFirst),
      reason:
          'a failed sweep must release its key — otherwise the completed '
          'future stays parked and this bucket can never be retried',
    );
  });

  // An empty tab whose fetch failed is *unknown*. It used to print "No records
  // found", as if the server had answered.
  testWidgets('a failed fetch with nothing cached says so and retries', (
    tester,
  ) async {
    final throwing = _FakeInvoiceRepo()..throwSynchronously = true;
    final services = _FakeServices(
      invoices: throwing,
      quotes: _FakeQuoteRepo(),
      clients: _FakeClientRepo(),
    );
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text('No records found'), findsNothing);

    // The connection is back: Retry fetches again and the claim goes.
    throwing.throwSynchronously = false;
    final before = throwing.fetchAttempts;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(throwing.fetchAttempts, greaterThan(before));
    expect(find.text("Couldn't load"), findsNothing);
    expect(find.text('No records found'), findsOneWidget);
  });

  // With rows on screen the cache is doing its job; a failed top-up behind
  // them is not worth replacing them with an error.
  testWidgets('a failed fetch over cached rows keeps the rows', (tester) async {
    final throwing = _FakeInvoiceRepo(rows: [_invoice('i1')])
      ..throwSynchronously = true;
    final services = _FakeServices(
      invoices: throwing,
      quotes: _FakeQuoteRepo(),
      clients: _FakeClientRepo(),
    );
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load"), findsNothing);
    expect(find.text('No records found'), findsNothing);
    expect(find.textContaining('i1', findRichText: true), findsWidgets);
  });

  testWidgets("All names each row's status; a status tab does not repeat it", (
    tester,
  ) async {
    await _pump(
      tester,
      services: _services(quotes: [_quote('q1')]),
      nav: _Nav(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuoteStatusPill), findsOneWidget);

    // The pill says "Draft" too.
    await tester.tap(
      find.descendant(
        of: find.byType(EntityListStatusTabs),
        matching: find.text('Draft'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('q1', findRichText: true), findsWidgets);
    expect(find.byType(QuoteStatusPill), findsNothing);
  });

  testWidgets('a row opens its own record, by entity type', (tester) async {
    final nav = _Nav();
    await _pump(
      tester,
      services: _services(quotes: [_quote('q1')]),
      nav: nav,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('q1', findRichText: true).first);
    await tester.pumpAndSettle();
    expect(nav.location, '/quotes/q1');
  });

  testWidgets('View All opens the list on the tab the strip shows', (
    tester,
  ) async {
    final nav = _Nav();
    await _pump(tester, services: _services(), nav: nav);
    await tester.tap(find.text('Expired'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();
    expect(nav.location, '/quotes');
  });

  testWidgets('a user tap persists the tab; the initial render does not', (
    tester,
  ) async {
    final changes = <String?>[];
    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      onTabChanged: changes.add,
    );
    expect(changes, isEmpty, reason: 'hydrate must not rewrite nav_state');
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    expect(changes, ['draft']);
  });

  testWidgets('a restored tab is selected; an unavailable one heals to All', (
    tester,
  ) async {
    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      initialTabId: 'expired',
    );
    expect(_selectedIndex(tester), _indexOfTab(tester, 'expired'));

    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      initialTabId: 'not_a_mode',
    );
    expect(
      tester
          .widget<EntityListStatusTabs>(find.byType(EntityListStatusTabs))
          .selectedIndex,
      0,
      reason: 'an unknown stored tab degrades to All, not to nothing selected',
    );
  });

  testWidgets('a tab restored AFTER mount is still applied', (tester) async {
    // The ordering that actually happens in production, and the one the
    // mount-time test above cannot reach. `DashboardViewModel._hydrate` is an
    // async Drift read that does NOT notify, while the dashboard body mounts as
    // soon as its formatter resolves — which on a warm navigation is a
    // microtask. So the card mounts with a null `initialTabId` and only later
    // receives the restored one through a rebuild.
    final props = ValueNotifier(const _Props());
    addTearDown(props.dispose);
    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      props: props,
      initialTabId: null,
    );
    expect(_selectedIndex(tester), 0, reason: 'mounts on All');

    props.value = const _Props(initialTabId: 'expired');
    await tester.pumpAndSettle();
    expect(
      _selectedIndex(tester),
      _indexOfTab(tester, 'expired'),
      reason: 'the late-arriving restored tab must still apply',
    );
  });

  testWidgets('a tap before hydrate beats the late restored tab', (
    tester,
  ) async {
    // The latch that makes the fix above safe: a slow `nav_state` read must
    // never yank the user off a tab they have already chosen.
    final props = ValueNotifier(const _Props());
    addTearDown(props.dispose);
    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      props: props,
      initialTabId: null,
    );
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    expect(_selectedIndex(tester), 1);

    props.value = const _Props(initialTabId: 'expired');
    await tester.pumpAndSettle();
    expect(
      _selectedIndex(tester),
      1,
      reason: 'the user has already picked; hydrate must not clobber it',
    );
  });

  testWidgets('a company switch forgets the previous company\'s tap', (
    tester,
  ) async {
    // The tap latch belongs to the company it was made in. This State can
    // outlive a company switch — the dashboard skips its spinner frame when the
    // new company's formatter is cached, and the wide grid's `GlobalKey`s carry
    // it between cells — so a latch left set would skip the new company's
    // late-restored tab and leave it on All.
    final props = ValueNotifier(const _Props());
    addTearDown(props.dispose);
    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      props: props,
      initialTabId: null,
    );
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();
    expect(_selectedIndex(tester), 1);

    props.value = const _Props(companyId: 'other');
    await tester.pumpAndSettle();
    props.value = const _Props(companyId: 'other', initialTabId: 'expired');
    await tester.pumpAndSettle();

    expect(
      _selectedIndex(tester),
      _indexOfTab(tester, 'expired'),
      reason: "the new company's restored tab must apply",
    );
  });

  testWidgets('it survives being scrolled out of the dashboard list', (
    tester,
  ) async {
    // Both dashboard bodies are lazily-collected `ListView`s, so without
    // `AutomaticKeepAliveClientMixin` the card is garbage-collected past the
    // cache extent — taking the selected tab, the subscriptions and the fetch
    // latches with it.
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      services: _services(),
      nav: _Nav(),
      tall: true,
      controller: controller,
    );
    // The card sits behind a 2000 px spacer, so bring it on screen first.
    controller.jumpTo(1900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draft'));
    await tester.pumpAndSettle();

    controller.jumpTo(3500);
    await tester.pumpAndSettle();
    controller.jumpTo(1900);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EntityListStatusTabs>(find.byType(EntityListStatusTabs))
          .selectedIndex,
      1,
      reason: 'the selected tab must survive the scroll',
    );
  });

  testWidgets('a refresh re-arms the fetch, but the first stamp does not', (
    tester,
  ) async {
    final services = _services();
    final props = ValueNotifier(const _Props());
    addTearDown(props.dispose);
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      props: props,
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();
    final repo = services.invoices as _FakeInvoiceRepo;
    final initial = repo.fetches.length;

    // null -> first stamp is the dashboard's initial load completing, not a
    // refresh. Re-arming on it makes every cold start fetch twice.
    props.value = _Props(refreshNonce: DateTime.utc(2026, 9, 14));
    await tester.pumpAndSettle();
    expect(
      repo.fetches.length,
      initial,
      reason: 'first stamp is not a refresh',
    );

    props.value = _Props(refreshNonce: DateTime.utc(2026, 9, 15));
    await tester.pumpAndSettle();
    expect(repo.fetches.length, greaterThan(initial));
  });

  testWidgets('a company switch rebinds the view model', (tester) async {
    final services = _services();
    final props = ValueNotifier(const _Props());
    addTearDown(props.dispose);
    await _pump(
      tester,
      services: services,
      nav: _Nav(),
      props: props,
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();
    final repo = services.invoices as _FakeInvoiceRepo;
    final before = repo.watchedModes.length;

    props.value = const _Props(companyId: 'other');
    await tester.pumpAndSettle();
    expect(repo.watchedModes.length, greaterThan(before));
  });

  testWidgets('a row says how near its deadline is, and only when it is', (
    tester,
  ) async {
    final now = DateTime.now();
    Date inDays(int n) {
      // Through `DateTime`, which rolls the month over.
      final t = DateTime(now.year, now.month, now.day + n);
      return Date(t.year, t.month, t.day);
    }

    Invoice due(String id, Date d, {InvoiceStatus? status}) =>
        _invoice(id, status: status).copyWith(dueDate: d);
    await _pump(
      tester,
      services: _services(
        invoices: [
          due('soon', inDays(3)),
          due('late', inDays(-12)),
          due('far', inDays(90)),
          due('draft', inDays(3), status: InvoiceStatus.draft),
        ],
      ),
      nav: _Nav(),
      narrow: false,
      entity: EntityType.invoice,
    );
    await tester.pumpAndSettle();

    expect(find.text('due in 3 days'), findsOneWidget);
    expect(find.text('12 days late'), findsOneWidget);
    // Far off, or a draft: the date alone.
    expect(find.textContaining('90 days'), findsNothing);
    expect(find.textContaining('due in', findRichText: true), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('12 days late')).style!.color,
      isSameColorAs(InTheme.light.overdue),
    );
  });

  group('the date slot says what the date is', () {
    final year = DateTime.now().year;

    testWidgets('an open invoice its due date, a paid one when it was paid', (
      tester,
    ) async {
      Payment paidOn(Date d, {bool deleted = false}) =>
          emptyPayment().copyWith(date: d, isDeleted: deleted);
      await _pump(
        tester,
        services: _services(
          invoices: [
            _invoice('open').copyWith(dueDate: Date(year, 12, 31)),
            _invoice(
              'paid',
              status: InvoiceStatus.paid,
            ).copyWith(balance: Decimal.zero),
            _invoice(
              'paid-unsynced',
              status: InvoiceStatus.paid,
            ).copyWith(balance: Decimal.zero),
            _invoice('draft', status: InvoiceStatus.draft),
          ],
          payments: _FakePaymentRepo({
            // The latest live payment is the paid date; a deleted one is not.
            'paid': [
              paidOn(Date(year, 1, 2)),
              paidOn(Date(year, 1, 9)),
              paidOn(Date(year, 3, 1), deleted: true),
            ],
          }),
        ),
        nav: _Nav(),
        narrow: false,
        entity: EntityType.invoice,
      );
      await tester.pumpAndSettle();

      expect(find.text('Due Dec 31'), findsOneWidget);
      expect(find.text('Paid Jan 9'), findsOneWidget);
      // No payment on the device, or a draft: the invoice's own date, in the
      // company format.
      expect(find.text('2026-09-14'), findsNWidgets(2));
    });

    testWidgets('a paid row whose lookup fails keeps its invoice date', (
      tester,
    ) async {
      await _pump(
        tester,
        services: _services(
          invoices: [
            _invoice(
              'paid',
              status: InvoiceStatus.paid,
            ).copyWith(balance: Decimal.zero),
          ],
        ),
        nav: _Nav(),
        narrow: false,
        entity: EntityType.invoice,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2026-09-14'), findsOneWidget);
    });

    testWidgets('a quote out with the client its valid-until date', (
      tester,
    ) async {
      await _pump(
        tester,
        services: _services(
          quotes: [
            _quote(
              'sent',
              status: QuoteStatus.sent,
            ).copyWith(dueDate: Date(year, 12, 14)),
            _quote('draft'),
          ],
        ),
        nav: _Nav(),
        narrow: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Valid until Dec 14'), findsOneWidget);
      expect(find.text('2026-09-13'), findsOneWidget);
    });

    testWidgets('a deadline in another year keeps its year', (tester) async {
      await _pump(
        tester,
        services: _services(
          invoices: [_invoice('open').copyWith(dueDate: Date(year + 1, 1, 5))],
        ),
        nav: _Nav(),
        narrow: false,
        entity: EntityType.invoice,
      );
      await tester.pumpAndSettle();
      expect(find.text('Due ${year + 1}-01-05'), findsOneWidget);
    });
  });
}
