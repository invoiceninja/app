// The pure halves of `StoreBilling`'s Play answers, kept apart from the SDK
// calls so a test can pin them.
//
// Under `src/sdk_only/`: not exported by `package:store_services`, and with
// no copy in the FOSS twin (which never queries a store), so the twins'
// public surfaces still match (test/lint/store_sdk_boundary_test.dart). The
// app's `lib/` never imports this; its test does.

import 'package:store_services/src/store_billing.dart';

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
