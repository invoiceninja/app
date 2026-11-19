import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayProductDetails, InAppPurchaseAndroidPlatformAddition;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Where a store purchase stands, as the app acts on it.
enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

/// A purchasable store product.
///
/// Built only by [StoreBilling.queryProducts]; the underlying SDK object rides
/// along privately so [StoreBilling.buyNonConsumable] can hand it back.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  }) : _details = null;

  StoreProduct._(ProductDetails details)
    : id = details.id,
      title = details.title,
      description = details.description,
      price = details.price,
      _details = details;

  final String id;
  final String title;
  final String description;

  /// Localised, formatted by the store.
  final String price;

  final ProductDetails? _details;
}

/// The result of [StoreBilling.queryProducts].
class StoreProductQuery {
  const StoreProductQuery({required this.products, this.error});

  final List<StoreProduct> products;

  /// The store's error, if the query partly or wholly failed.
  final String? error;
}

/// A purchase update from [StoreBilling.purchaseStream].
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.error,
    this.purchaseId,
    this.localVerificationData = '',
    this.serverVerificationData = '',
    this.pendingCompletePurchase = false,
    this.isStoreKit1 = false,
    this.storeKit1OriginalTransactionId,
  }) : _details = null;

  StorePurchase._(PurchaseDetails details)
    : productId = details.productID,
      status = _statusOf(details.status),
      error = details.error?.toString(),
      purchaseId = details.purchaseID,
      localVerificationData = details.verificationData.localVerificationData,
      serverVerificationData = details.verificationData.serverVerificationData,
      pendingCompletePurchase = details.pendingCompletePurchase,
      isStoreKit1 = details is AppStorePurchaseDetails,
      storeKit1OriginalTransactionId = details is AppStorePurchaseDetails
          ? details
                .skPaymentTransaction
                .originalTransaction
                ?.transactionIdentifier
          : null,
      _details = details;

  final String productId;
  final StorePurchaseStatus status;
  final String? error;

  /// Google's `orderId`; Apple's per-transaction id.
  final String? purchaseId;

  /// Apple's `Transaction.jsonRepresentation` under StoreKit 2; Google's
  /// purchase JSON on Android.
  final String localVerificationData;

  /// What the store's server verifies: the transaction's signed JWS under
  /// StoreKit 2 (the base64 app receipt under StoreKit 1), Google's purchase
  /// token on Android.
  final String serverVerificationData;

  final bool pendingCompletePurchase;

  /// True only if `enableStoreKit1()` is ever called — StoreKit 2 is the
  /// plugin default.
  final bool isStoreKit1;

  /// StoreKit 1's original transaction id, populated for restored
  /// transactions only.
  final String? storeKit1OriginalTransactionId;

  final PurchaseDetails? _details;

  static StorePurchaseStatus _statusOf(PurchaseStatus s) => switch (s) {
    PurchaseStatus.pending => StorePurchaseStatus.pending,
    PurchaseStatus.purchased => StorePurchaseStatus.purchased,
    PurchaseStatus.restored => StorePurchaseStatus.restored,
    PurchaseStatus.error => StorePurchaseStatus.error,
    PurchaseStatus.canceled => StorePurchaseStatus.canceled,
  };
}

/// App Store / Play in-app purchases, reduced to the calls the upgrade sheet
/// makes. The receipt handling lives in the app's `PurchaseService`.
class StoreBilling {
  final InAppPurchase _iap = InAppPurchase.instance;

  /// True only on store platforms with a reachable billing backend.
  Future<bool> isAvailable() => _iap.isAvailable();

  Stream<List<StorePurchase>> get purchaseStream => _iap.purchaseStream.map(
    (list) => [for (final p in list) StorePurchase._(p)],
  );

  /// The store products for [ids]. On Play a subscription comes back once
  /// per offer — its base plan, and each free-trial or intro offer on it,
  /// priced at the offer's first phase ("Free") — so only one per base plan
  /// is kept ([playBasePlanOfferIndexes]).
  Future<StoreProductQuery> queryProducts(Set<String> ids) async {
    final resp = await _iap.queryProductDetails(ids);
    final details = resp.productDetails;
    final keep = playBasePlanOfferIndexes([
      for (final d in details) _playOfferOf(d),
    ]);
    return StoreProductQuery(
      products: [for (final i in keep) StoreProduct._(details[i])],
      error: resp.error?.toString(),
    );
  }

  /// Starts a purchase of [product]. [applicationUserName] ties it to an
  /// account on our side: StoreKit 2 sends it as the transaction's
  /// `appAccountToken`, which must be a UUID (StoreKit drops anything else
  /// without a word), and Play as the `obfuscatedAccountId`.
  Future<void> buyNonConsumable(
    StoreProduct product, {
    String? applicationUserName,
  }) async {
    final details = product._details;
    if (details == null) {
      throw StateError('buyNonConsumable needs a product from queryProducts');
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: details,
        applicationUserName: applicationUserName,
      ),
    );
  }

  /// Paid purchases the app has not finished with the store yet: on Android
  /// the purchased, unacknowledged ones (Play refunds those after three days),
  /// on iOS and macOS StoreKit 2's `Transaction.unfinished`. Empty anywhere
  /// else, and when the store can't be asked.
  ///
  /// Each comes back as [StorePurchaseStatus.purchased] and can be handed to
  /// [completePurchase].
  Future<List<StorePurchase>> unfinishedPurchases() async {
    if (kIsWeb) return const [];
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final resp = await _iap
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
              .queryPastPurchases();
          return [
            for (final p in resp.pastPurchases)
              if (p.status == PurchaseStatus.purchased &&
                  p.pendingCompletePurchase)
                StorePurchase._(p),
          ];
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          final transactions = await SK2Transaction.unfinishedTransactions();
          return [
            for (final t in transactions)
              StorePurchase._(
                SK2PurchaseDetails(
                  productID: t.productId,
                  purchaseID: t.id,
                  verificationData: PurchaseVerificationData(
                    localVerificationData: t.jsonRepresentation ?? '',
                    serverVerificationData: t.receiptData ?? '',
                    source: kIAPSource,
                  ),
                  transactionDate: t.purchaseDate,
                  status: PurchaseStatus.purchased,
                  appAccountToken: t.appAccountToken,
                  expirationDate: t.expirationDate,
                  sk2Transaction: t,
                ),
              ),
          ];
        default:
          return const [];
      }
    } on Exception {
      return const [];
    }
  }

  /// The product ids this store account holds an active subscription to in
  /// this app — StoreKit 2's `Transaction.currentEntitlements` on iOS and
  /// macOS, and on Android the subscriptions Play reports the Google account
  /// owns (`queryPurchasesAsync`: bought and not yet expired, cancelled or
  /// not, acknowledged or not). Empty anywhere else, and when the store can't
  /// be asked; so an empty answer never proves there is none.
  Future<Set<String>> activeSubscriptionProductIds() async {
    if (kIsWeb) return const {};
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final resp = await _iap
              .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
              .queryPastPurchases();
          return ownedProductIds([
            for (final p in resp.pastPurchases) StorePurchase._(p),
          ]);
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          final entitlements = await SK2Transaction.currentEntitlements();
          return {for (final t in entitlements) t.productId};
        default:
          return const {};
      }
    } on Exception {
      return const {};
    }
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> completePurchase(StorePurchase purchase) async {
    final details = purchase._details;
    if (details == null) {
      throw StateError('completePurchase needs a purchase from purchaseStream');
    }
    await _iap.completePurchase(details);
  }

  /// Presents Apple's own manage-subscriptions sheet over the app (StoreKit 2,
  /// iOS 15+). False when it was not shown — any other platform (StoreKit has
  /// no such sheet on macOS), or a StoreKit refusal such as no key window
  /// scene — so the caller can fall back to the subscriptions page.
  Future<bool> showManageSubscriptions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      await _iap
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>()
          .showManageSubscriptions();
      return true;
    } on Exception {
      return false;
    }
  }
}

/// The product's Play offer, as [playBasePlanOfferIndexes] reads it; no base
/// plan for anything that is not a Play subscription.
({String productId, String? basePlanId, String? offerId}) _playOfferOf(
  ProductDetails d,
) {
  if (d is GooglePlayProductDetails) {
    final index = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    if (index != null && offers != null && index < offers.length) {
      final offer = offers[index];
      return (
        productId: d.id,
        basePlanId: offer.basePlanId,
        offerId: offer.offerId,
      );
    }
  }
  return (productId: d.id, basePlanId: null, offerId: null);
}

/// Which of Play's product offers to list: one per subscription base plan.
///
/// Play hands a subscription back once per offer — its base plan (no
/// `offerId`) and each offer on it, a free trial priced "Free" among them —
/// so listing them all shows one plan several times. Keeps, per product and
/// base plan, the base plan's own offer, or the first offer when the base
/// plan's isn't there; anything that is not a Play subscription is kept as
/// is. Returns the kept indexes into [offers], in order.
List<int> playBasePlanOfferIndexes(
  List<({String productId, String? basePlanId, String? offerId})> offers,
) {
  final chosen = <String, int>{};
  for (var i = 0; i < offers.length; i++) {
    final o = offers[i];
    final basePlan = o.basePlanId;
    if (basePlan == null) {
      chosen['$i'] = i;
      continue;
    }
    final key = '${o.productId}|$basePlan';
    final current = chosen[key];
    if (current == null ||
        (offers[current].offerId != null && o.offerId == null)) {
      chosen[key] = i;
    }
  }
  return chosen.values.toList()..sort();
}

/// The product ids of [owned] that are bought or on their way (a Play
/// pending payment): what a second sale would bill alongside.
Set<String> ownedProductIds(Iterable<StorePurchase> owned) => {
  for (final p in owned)
    if (p.status == StorePurchaseStatus.purchased ||
        p.status == StorePurchaseStatus.restored ||
        p.status == StorePurchaseStatus.pending)
      p.productId,
};
