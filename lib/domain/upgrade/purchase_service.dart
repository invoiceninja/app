import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/services/api_client.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';

/// App Store / Play product identifiers for the hosted plans. Mirrors
/// admin-portal's `kProductPlans` (legacy `lib/constants.dart`). The server
/// maps the productID back to a plan slug (`-` → `_`).
const String kProductProPlanMonth = 'pro_plan';
const String kProductProPlanYear = 'pro_plan_annual';
const String kProductEnterprisePlanMonth = 'enterprise_plan';
const String kProductEnterprisePlanMonth5 = 'enterprise_plan_5';
const String kProductEnterprisePlanMonth10 = 'enterprise_plan_10';
const String kProductEnterprisePlanMonth20 = 'enterprise_plan_20';
const String kProductEnterprisePlanYear = 'enterprise_plan_annual';
const String kProductEnterprisePlanYear5 = 'enterprise_plan_annual_5';
const String kProductEnterprisePlanYear10 = 'enterprise_plan_annual_10';
const String kProductEnterprisePlanYear20 = 'enterprise_plan_annual_20';

const Set<String> kProductPlans = {
  kProductProPlanMonth,
  kProductProPlanYear,
  kProductEnterprisePlanMonth,
  kProductEnterprisePlanMonth5,
  kProductEnterprisePlanMonth10,
  kProductEnterprisePlanMonth20,
  kProductEnterprisePlanYear,
  kProductEnterprisePlanYear5,
  kProductEnterprisePlanYear10,
  kProductEnterprisePlanYear20,
};

/// How often a plan bills, for the purchase sheet's disclosure (App Review
/// 3.1.2, Play's subscriptions policy).
enum PlanBillingPeriod { monthly, yearly }

/// The billing period of a plan product, read from its id: every yearly plan
/// is `…_annual` / `…_annual_N` (with or without the `v2_` prefix), every
/// other plan is monthly. The ids are fixed by [kProductPlans] and the store
/// records match them, so this is exact without asking the store.
PlanBillingPeriod billingPeriodOf(String productId) =>
    planSlugOf(productId).contains('_annual')
    ? PlanBillingPeriod.yearly
    : PlanBillingPeriod.monthly;

/// The hosted service's in-app purchase settings for the signed-in account
/// (`GET /api/admin/iap/config`).
@immutable
class IapConfig {
  const IapConfig({required this.purchasesEnabled, this.appAccountToken});

  /// Fail-closed default: no purchases.
  static const closed = IapConfig(purchasesEnabled: false);

  final bool purchasesEnabled;

  /// The account's purchase token, a UUID: sent with every purchase as
  /// Apple's `appAccountToken` / Play's `obfuscatedAccountId`, so the store
  /// (and the server notifications it sends) name the account the purchase
  /// was made for. Null when the server sent none, or not a UUID — StoreKit
  /// drops a non-UUID token without a word, and the server then refuses the
  /// paid purchase.
  final String? appAccountToken;

  /// Whether a purchase may be started: the service takes them, and there is
  /// a token to tie one to this account.
  bool get canPurchase => purchasesEnabled && appAccountToken != null;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Reads the config response; anything of the wrong shape is [closed].
  factory IapConfig.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return closed;
    final token = json['app_account_token'];
    return IapConfig(
      purchasesEnabled: json['purchases_enabled'] == true,
      appAccountToken: token is String && _uuid.hasMatch(token.trim())
          ? token.trim()
          : null,
    );
  }
}

/// The upgrade sheet's side of an in-app purchase: lists the store products
/// and starts a purchase. Created when the sheet opens, disposed when it
/// closes.
///
/// It never delivers anything. Every purchase update — this sheet's purchase,
/// a renewal, an Ask to Buy approved days later — reaches the app-lifetime
/// [PurchaseDelivery], which posts it to `/api/admin/subscription` and
/// reports on [PurchaseDelivery.activity]; this follows that to keep [busy]
/// right and to tell the sheet when a purchase was [applied].
///
/// The SDK itself sits behind [StoreBilling] (`package:store_services`), so
/// the F-Droid build can drop Play Billing — there it reports unavailable, and
/// the F-Droid build never opens the sheet: `resolveUpgradeRoute` sends it to
/// the billing portal (docs/fdroid.md).
///
/// NOTE: requires App Store Connect / Play Console product configuration
/// (the `kProductPlans` IDs) and sandbox testing — that store-side setup is
/// outside the Flutter codebase and cannot be exercised in CI.
class PurchaseService {
  PurchaseService({
    required ApiClient apiClient,
    required AuthRepository auth,
    required PurchaseDelivery delivery,
  }) : _apiClient = apiClient,
       _auth = auth,
       _delivery = delivery;

  final ApiClient _apiClient;
  final AuthRepository _auth;
  final PurchaseDelivery _delivery;
  final _log = Logger('PurchaseService');

  StoreBilling get _iap => _delivery.billing;

  StreamSubscription<PurchaseActivity>? _sub;
  VoidCallback? _releaseSheet;
  final ValueNotifier<List<StoreProduct>> products = ValueNotifier(const []);
  final ValueNotifier<bool> busy = ValueNotifier(false);

  /// What [loadConfig] last answered; [IapConfig.closed] until it has.
  IapConfig _config = IapConfig.closed;

  final _outcomes = StreamController<PurchaseActivity>.broadcast();

  /// The delivery outcomes the sheet tells the user about: applied, rejected
  /// (with the server's message), retry later, and a failed store purchase.
  Stream<PurchaseActivity> get outcomes => _outcomes.stream;

  /// True only on store platforms with a reachable billing backend.
  Future<bool> get isAvailable => _iap.isAvailable();

  /// Whether the hosted service is taking in-app purchases right now, and
  /// gave this account a token to tie one to. It asks
  /// `GET /api/admin/iap/config` and **fails closed**: no answer, an error, or
  /// anything but `purchases_enabled: true` with a UUID `app_account_token`
  /// means no purchase sheet. That keeps purchases off until the hosted
  /// billing can verify them, and lets support switch them off again without
  /// an app release. Delivering a purchase the user already paid for is never
  /// gated on it ([PurchaseDelivery]).
  Future<bool> loadConfig() async {
    try {
      _config = IapConfig.fromJson(
        await _apiClient.getOne('/api/admin/iap/config'),
      );
    } catch (e) {
      _log.info('iap config unavailable, purchases off: $e');
      _config = IapConfig.closed;
    }
    if (_config.purchasesEnabled && _config.appAccountToken == null) {
      _log.warning('iap config has no usable app_account_token, purchases off');
    }
    return _config.canPurchase;
  }

  /// Whether this Apple Account already holds an active subscription to one
  /// of our plans in this app (StoreKit 2's `Transaction.currentEntitlements`).
  /// Selling a second one would bill twice. Always false on Android — Play
  /// refuses a second purchase of an owned product itself — and when StoreKit
  /// can't be asked.
  Future<bool> hasActiveStoreSubscription() async {
    final ids = await _iap.activeSubscriptionProductIds();
    return ids.any((id) => kProductPlans.contains(planSlugOf(id)));
  }

  /// `account.key`, which the hosted endpoint looks the account up by. Blank
  /// only on an offline cold start from a cache older than 5.1.14, until the
  /// background refresh fills it.
  String get _accountKey => _auth.session.value?.accountKey ?? '';

  /// Follows the delivery and lists the products.
  Future<void> init() async {
    _releaseSheet = _delivery.holdSheet();
    _sub = _delivery.activity.listen(_onActivity);
    await _queryProducts();
  }

  Future<void> _queryProducts() async {
    busy.value = true;
    try {
      final resp = await _iap.queryProducts(kProductPlans);
      if (resp.error != null) {
        _log.warning('queryProductDetails: ${resp.error}');
      }
      products.value = resp.products;
    } finally {
      busy.value = false;
    }
  }

  Future<void> buy(StoreProduct product) async {
    // Never take money that could not be credited to an account.
    if (_accountKey.isEmpty) {
      _log.warning('no account key yet, not starting a purchase');
      return;
    }
    // Nor money the store can't tie to this account.
    final token = _config.canPurchase ? _config.appAccountToken : null;
    if (token == null) {
      _log.warning('no app account token, not starting a purchase');
      return;
    }
    busy.value = true;
    try {
      await _iap.buyNonConsumable(product, applicationUserName: token);
    } catch (e) {
      // A purchase that never started sends no purchase-stream event to clear
      // [busy], so the sheet would stay disabled. StoreKit refuses a product
      // that still has an unfinished transaction this way
      // (`storekit_duplicate_product_object`, in_app_purchase_storekit 0.4.10).
      busy.value = false;
      _log.warning('buyNonConsumable: $e');
    }
  }

  /// Asks the store to hand back this account's purchases; each one reaches
  /// [PurchaseDelivery]. Never gated on [loadConfig].
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _log.warning('restorePurchases: $e');
    }
  }

  void _onActivity(PurchaseActivity a) {
    if (busy.value != _busyAfter(a.kind)) busy.value = _busyAfter(a.kind);
    switch (a.kind) {
      case PurchaseActivityKind.applied:
      case PurchaseActivityKind.rejected:
      case PurchaseActivityKind.retryLater:
      case PurchaseActivityKind.failed:
        if (!_outcomes.isClosed) _outcomes.add(a);
      case PurchaseActivityKind.pending:
      case PurchaseActivityKind.delivering:
      case PurchaseActivityKind.canceled:
        break;
    }
  }

  // A cancelled store sheet sends `canceled`, not `error` (StoreKit 2, and
  // Play's user-cancelled) — it must clear [busy] too, or every plan tile
  // stayed disabled until the sheet was reopened.
  static bool _busyAfter(PurchaseActivityKind kind) => switch (kind) {
    PurchaseActivityKind.pending || PurchaseActivityKind.delivering => true,
    _ => false,
  };

  Future<void> dispose() async {
    _releaseSheet?.call();
    await _sub?.cancel();
    await _outcomes.close();
    products.dispose();
    busy.dispose();
  }
}
