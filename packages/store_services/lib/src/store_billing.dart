import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show BillingResponse;
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show
        GooglePlayProductDetails,
        InAppPurchaseAndroidPlatform,
        InAppPurchaseAndroidPlatformAddition;
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    show InAppPurchasePlatform;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'package:store_services/src/sdk_only/play_billing_helpers.dart';

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

  /// Finishes [purchase] with the store: StoreKit's `finish()`, Play's
  /// acknowledgement. False when the store did not confirm it — Play answered
  /// its acknowledgement with anything but OK — so the caller can try again
  /// before Play's three-day refund. StoreKit reports no result: true once
  /// the call returns.
  Future<bool> completePurchase(StorePurchase purchase) async {
    final details = purchase._details;
    if (details == null) {
      throw StateError('completePurchase needs a purchase from purchaseStream');
    }
    // `InAppPurchase.completePurchase` drops the result; Android's platform
    // returns Play's BillingResult for the acknowledgement.
    final platform = InAppPurchasePlatform.instance;
    if (platform is InAppPurchaseAndroidPlatform) {
      final result = await platform.completePurchase(details);
      return result.responseCode == BillingResponse.ok;
    }
    await _iap.completePurchase(details);
    return true;
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
