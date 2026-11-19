// The pure halves of `StoreBilling`'s Play answers: which product offers the
// purchase sheet lists, and which subscriptions a Google account already
// owns (so the sheet never sells a second, different plan).

import 'package:flutter_test/flutter_test.dart';
import 'package:store_services/store_services.dart';

void main() {
  group('playBasePlanOfferIndexes', () {
    test('one row per base plan: a free-trial offer is not a second plan', () {
      final offers = [
        // Play lists the trial offer first, priced at its first phase: Free.
        (productId: 'pro_plan', basePlanId: 'monthly', offerId: 'free-trial'),
        (productId: 'pro_plan', basePlanId: 'monthly', offerId: null),
        (productId: 'enterprise_plan', basePlanId: 'monthly', offerId: null),
        (productId: 'enterprise_plan', basePlanId: 'monthly', offerId: 'intro'),
      ];

      expect(playBasePlanOfferIndexes(offers), [1, 2]);
    });

    test(
      'the first offer stands in when the base plan has none of its own',
      () {
        final offers = [
          (productId: 'pro_plan', basePlanId: 'monthly', offerId: 'a'),
          (productId: 'pro_plan', basePlanId: 'monthly', offerId: 'b'),
        ];

        expect(playBasePlanOfferIndexes(offers), [0]);
      },
    );

    test('two base plans of one product are two rows', () {
      final offers = [
        (productId: 'pro_plan', basePlanId: 'monthly', offerId: null),
        (productId: 'pro_plan', basePlanId: 'yearly', offerId: null),
      ];

      expect(playBasePlanOfferIndexes(offers), [0, 1]);
    });

    test('Apple products and Play one-time products pass through', () {
      final offers = [
        (productId: 'pro_plan', basePlanId: null, offerId: null),
        (productId: 'pro_plan_annual', basePlanId: null, offerId: null),
      ];

      expect(playBasePlanOfferIndexes(offers), [0, 1]);
    });
  });

  group('ownedProductIds', () {
    test('counts what is bought or on its way, not a failed purchase', () {
      const owned = [
        StorePurchase(
          productId: 'pro_plan',
          status: StorePurchaseStatus.purchased,
        ),
        StorePurchase(
          productId: 'enterprise_plan',
          status: StorePurchaseStatus.pending,
        ),
        StorePurchase(
          productId: 'enterprise_plan_5',
          status: StorePurchaseStatus.error,
        ),
        StorePurchase(
          productId: 'enterprise_plan_10',
          status: StorePurchaseStatus.canceled,
        ),
      ];

      expect(ownedProductIds(owned), {'pro_plan', 'enterprise_plan'});
    });
  });
}
