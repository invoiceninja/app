import 'package:flutter/foundation.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/domain/upgrade/purchase_delivery.dart';

/// Whether this build sells plans through the store's own billing: a store
/// build ([StoreReview.isStoreBuild], false in the F-Droid twin) running on
/// iOS, Android or macOS. Every native macOS build is the Mac App Store build
/// (docs/setup.md), and the web and the Windows / Linux builds have no store
/// billing.
///
/// A build that sells in-app may not send anyone to an external purchase
/// (App Store 3.1.1(a) outside the US, Play Payments policy 4): no billing
/// portal, no white-label checkout, no PEPPOL credit packs, no Stripe page
/// from the DocuNinja embed. The F-Droid and GitHub APKs answer false here and
/// keep those paths (docs/fdroid.md).
bool storeBillingFor({
  required bool isStoreBuild,
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    isStoreBuild &&
    !isWeb &&
    (platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.macOS);

/// Lets a test pick the build, as `debugDefaultTargetPlatformOverride` picks
/// the platform: [StoreReview.isStoreBuild] is a const, and `flutter test`
/// always links the store package, so without this every test on the
/// default (Android) platform is a store build. Null in the app.
@visibleForTesting
bool? debugStoreBillingOverride;

/// [storeBillingFor] for the running build.
bool get isStoreBillingBuild =>
    debugStoreBillingOverride ??
    storeBillingFor(
      isStoreBuild: StoreReview.isStoreBuild,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );

/// The store this build sells through, and so the only store its copy may
/// name: App Review rejects a build that names another platform's store
/// (2.3.10). Null off a store-billing build (desktop, the web, F-Droid),
/// whose copy says "app store" without naming one.
PurchaseStore? get storeOfBuild =>
    isStoreBillingBuild ? PurchaseStore.of(defaultTargetPlatform) : null;

/// Stripe's hosted payment pages: Checkout, the customer billing portal,
/// Payment Links and hosted invoices.
const _kStripePaymentHosts = {
  'checkout.stripe.com',
  'billing.stripe.com',
  'buy.stripe.com',
  'pay.stripe.com',
  'invoice.stripe.com',
};

/// Invoice Ninja's own billing portal — `ninja_portal_url`, the white-label
/// checkout and the PEPPOL credit packs all live here.
const _kInvoiceNinjaBillingHost = 'invoiceninja.invoicing.co';

/// Whether [uri] is a page that sells something outside the store: Stripe's
/// payment pages, Invoice Ninja's billing portal, a subscription checkout on
/// any client portal, or the pricing pages. A store build refuses to open one
/// it didn't choose to (the DocuNinja embed hands us any off-origin link).
bool isExternalPurchaseUri(Uri uri) {
  final host = uri.host.toLowerCase();
  if (_kStripePaymentHosts.contains(host)) return true;
  if (host == _kInvoiceNinjaBillingHost) return true;
  final path = uri.path.toLowerCase();
  if (path.startsWith('/client/subscriptions')) return true;
  if ((host == 'invoiceninja.com' || host == 'www.invoiceninja.com') &&
      path.startsWith('/pricing')) {
    return true;
  }
  return false;
}
