import 'package:admin/data/repositories/auth/auth_session.dart';

/// Where an Upgrade tap goes. [resolveUpgradeRoute] picks one; `launchUpgrade`
/// carries it out.
enum UpgradeRoute {
  /// The in-app purchase sheet (store builds only).
  purchaseSheet,

  /// The store's own subscription management, for a live in-app plan.
  storeSubscriptions,

  /// The store's subscription management plus a toast saying the in-app
  /// subscription has ended: it may still be in a grace or billing-retry
  /// period, and a second purchase would bill twice.
  storeSubscriptionsEnded,

  /// Account Management → Plan, which explains how the plan is billed.
  planScreen,

  /// The hosted billing portal (`ninja_portal_url`). Never on a store build.
  billingPortal,
}

/// How long an in-app plan must have been over before the purchase sheet is
/// offered again. Until then the old subscription may still be in the store's
/// grace, billing-retry or on-hold window, and could renew alongside a new one.
const kIapRebuyAfter = Duration(days: 60);

/// The upgrade routing, kept pure so every case is unit-testable.
/// [storeBilling] is `isStoreBillingBuild` (store_build.dart).
///
/// Store builds never return [UpgradeRoute.billingPortal]: they may not send
/// anyone to an external purchase (App Store 3.1.1(a), Play Payments 4).
/// Elsewhere (desktop, web, F-Droid) nothing returns [UpgradeRoute.purchaseSheet].
UpgradeRoute resolveUpgradeRoute({
  required bool storeBilling,
  required AuthSession? session,
  required DateTime now,
}) {
  // A self-hosted server has no hosted plan to buy, and the purchase POST
  // would reach that server.
  if (session == null || !session.isHosted) return UpgradeRoute.planScreen;

  final activeIap = session.hasIapPlan && session.isPaidPlanSlug;

  if (!storeBilling) {
    // A plan bought in a store is managed in that store, never the portal.
    if (activeIap) return UpgradeRoute.planScreen;
    return UpgradeRoute.billingPortal;
  }

  if (activeIap) return UpgradeRoute.storeSubscriptions;

  // Billed on the web (a paid plan, or a trial, which hosted runs on a card):
  // a store purchase would bill twice, and the portal is off limits here.
  if (!session.hasIapPlan && (session.isPaidPlanSlug || session.isTrial)) {
    return UpgradeRoute.planScreen;
  }

  // A plan is bought for the whole account, and only its owner may buy it.
  // Checked before the ended-subscription branch: the store page on someone
  // else's device holds nothing of the owner's.
  if (!canBuyForActiveAccount(session)) return UpgradeRoute.planScreen;

  // An in-app plan that is no longer paid may still be in the store's grace or
  // billing-retry window and renew: offer the sheet only once it has been over
  // for [kIapRebuyAfter].
  if (session.hasIapPlan &&
      !iapPlanEndedLongAgo(session.planExpires, now: now)) {
    return UpgradeRoute.storeSubscriptionsEnded;
  }

  return UpgradeRoute.purchaseSheet;
}

/// Whether the signed-in user may buy a plan in-app for the active company's
/// account: they own the active company, and that company's account is the
/// user's own. The hosted endpoint applies a purchase to the user's own
/// account (`user->account`), so selling one while another account's company
/// is active would bill for a plan this account never gets. A session that
/// can't say which account is the user's (`userAccountKey` blank) is not
/// offered one either.
bool canBuyForActiveAccount(AuthSession session) =>
    (session.currentCompany?.isOwner ?? false) &&
    session.userAccountKey.isNotEmpty &&
    session.userAccountKey == session.accountKey;

/// Whether [planExpires] (the account's `plan_expires`, a `YYYY-MM-DD` day the
/// plan is paid through) ended more than [kIapRebuyAfter] before [now].
/// Fails closed: blank, unparseable or a pre-2001 sentinel (`0000-00-00`)
/// reads as recent, so no second purchase is offered on a date we can't read.
bool iapPlanEndedLongAgo(String planExpires, {required DateTime now}) {
  final raw = planExpires.trim();
  if (raw.length < 10) return false;
  final day = DateTime.tryParse('${raw.substring(0, 10)}T00:00:00Z');
  if (day == null || day.year <= 2000) return false;
  final paidThrough = day.add(const Duration(days: 1));
  return now.toUtc().isAfter(paidThrough.add(kIapRebuyAfter));
}
