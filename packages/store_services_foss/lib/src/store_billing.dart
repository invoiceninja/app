/// FOSS stub: store billing needs the Play Billing library, which F-Droid
/// forbids.
///
/// [StoreBilling.isAvailable] is always false, so every upgrade surface falls
/// back to the web portal (`showUpgradeSheet`) and nothing else here is ever
/// reached. The value types match packages/store_services exactly.
enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;
  final String price;
}

class StoreProductQuery {
  const StoreProductQuery({required this.products, this.error});

  final List<StoreProduct> products;
  final String? error;
}

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
  });

  final String productId;
  final StorePurchaseStatus status;
  final String? error;
  final String? purchaseId;
  final String localVerificationData;
  final String serverVerificationData;
  final bool pendingCompletePurchase;
  final bool isStoreKit1;
  final String? storeKit1OriginalTransactionId;
}

class StoreBilling {
  Future<bool> isAvailable() async => false;

  Stream<List<StorePurchase>> get purchaseStream => const Stream.empty();

  Future<StoreProductQuery> queryProducts(Set<String> ids) async =>
      const StoreProductQuery(products: []);

  Future<void> buyNonConsumable(
    StoreProduct product, {
    String? applicationUserName,
  }) async {}

  Future<List<StorePurchase>> unfinishedPurchases() async => const [];

  Future<Set<String>> activeSubscriptionProductIds() async => const {};

  Future<void> restorePurchases() async {}

  Future<void> completePurchase(StorePurchase purchase) async {}

  Future<bool> showManageSubscriptions() async => false;
}

/// Mirrors packages/store_services: which of Play's product offers to list,
/// one per subscription base plan (the base plan's own offer, else the
/// first). Returns the kept indexes into [offers], in order.
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

/// Mirrors packages/store_services: the product ids of [owned] that are
/// bought or on their way.
Set<String> ownedProductIds(Iterable<StorePurchase> owned) => {
  for (final p in owned)
    if (p.status == StorePurchaseStatus.purchased ||
        p.status == StorePurchaseStatus.restored ||
        p.status == StorePurchaseStatus.pending)
      p.productId,
};
