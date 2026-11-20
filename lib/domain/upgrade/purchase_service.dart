import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:logging/logging.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/data/repositories/auth_repository.dart';
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

/// Why the purchase sheet does not open: [unavailable] — the hosted service
/// does not take purchases right now, or the session does not yet know its
/// active account (a cache from before 5.1.14 has no account key until the
/// next refresh); [otherAccount] — a company of another account is active,
/// and a plan bought here lands on the user's own account.
enum SaleRefusal { unavailable, otherAccount }

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
    required AuthRepository auth,
    required PurchaseDelivery delivery,
  }) : _auth = auth,
       _delivery = delivery;

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

  /// Whether the hosted service is taking in-app purchases right now, gave
  /// this account a token to tie one to, and named the account it applies
  /// them to. It reads [PurchaseDelivery.config] (the one request for the
  /// signed-in user and the active company) and **fails closed**: no answer,
  /// an error, or anything but `purchases_enabled: true` with a UUID
  /// `app_account_token` and an `account_key` means no purchase sheet. That keeps purchases off until
  /// the hosted billing can verify them, and lets support switch them off
  /// again without an app release. Delivering a purchase the user already
  /// paid for is never gated on it ([PurchaseDelivery]).
  Future<bool> loadConfig() async {
    _config = await _delivery.config() ?? IapConfig.closed;
    return _config.canPurchase;
  }

  /// Whether a plan bought now goes to the active company's account: the
  /// config's `account_key` is the active account's key
  /// ([IapConfig.sellsTo]). False until [loadConfig] has answered.
  bool get sellsToActiveAccount => saleRefusal == null;

  /// Why nothing may be sold now, or null when a plan may be. A session with
  /// a blank account key does not know its active account yet: that is
  /// [SaleRefusal.unavailable], never [SaleRefusal.otherAccount], or the
  /// owner was told to switch away from their own account.
  SaleRefusal? get saleRefusal {
    final s = _auth.session.value;
    if (s == null || !_config.canPurchase || s.accountKey.isEmpty) {
      return SaleRefusal.unavailable;
    }
    return _config.sellsTo(s) ? null : SaleRefusal.otherAccount;
  }

  /// Whether this store account already holds an active subscription to one
  /// of our plans in this app: StoreKit 2's `Transaction.currentEntitlements`
  /// on Apple, the owned subscriptions Play reports on Android. Selling a
  /// second one would bill twice (Play refuses only the same product again,
  /// not a different plan). False when the store can't be asked.
  Future<bool> hasActiveStoreSubscription() async {
    final ids = await _iap.activeSubscriptionProductIds();
    return ids.any((id) => kProductPlans.contains(planSlugOf(id)));
  }

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
    // Never take money that could not be credited to this account, nor money
    // the store can't tie to it.
    if (!sellsToActiveAccount) {
      _log.warning('the config does not sell to this account, no purchase');
      return;
    }
    final token = _config.appAccountToken!;
    busy.value = true;
    try {
      await _iap.buyNonConsumable(product, applicationUserName: token);
    } catch (e) {
      // A purchase that never started sends no purchase-stream event to clear
      // [busy], so the sheet would stay disabled; and nothing would say why.
      // StoreKit refuses a product that still has an unfinished transaction
      // this way (`storekit_duplicate_product_object`,
      // in_app_purchase_storekit 0.4.10).
      busy.value = false;
      _log.warning('buyNonConsumable: $e');
      if (!_outcomes.isClosed) {
        _outcomes.add(
          PurchaseActivity(
            PurchaseActivityKind.failed,
            productId: product.id,
            message: e is PlatformException ? (e.message ?? e.code) : null,
          ),
        );
      }
    }
  }

  /// Asks the store to hand back this account's purchases; each one reaches
  /// [PurchaseDelivery]. Never gated on [loadConfig].
  Future<void> restore() => _delivery.restore();

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
