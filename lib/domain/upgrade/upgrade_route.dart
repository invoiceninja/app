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

  /// Account Management → Plan, which explains how the plan is billed: in a
  /// store, on the web, or by the account's owner.
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

  // An in-app plan that is no longer paid may still be in the store's grace or
  // billing-retry window and renew: nothing new is sold, in the store or on
  // the web, until it has been over for [kIapRebuyAfter].
  final lapsedIapRecently =
      session.hasIapPlan &&
      !session.hasActiveIapPlan &&
      !iapPlanEndedLongAgo(session.planExpires, now: now);

  if (!storeBilling) {
    // A plan bought in a store is managed in that store, never the portal;
    // and one that may still renew there is not sold again here.
    if (session.hasActiveIapPlan || lapsedIapRecently) {
      return UpgradeRoute.planScreen;
    }
    return UpgradeRoute.billingPortal;
  }

  if (session.hasActiveIapPlan) return UpgradeRoute.storeSubscriptions;

  // Billed on the web (a paid plan, or a trial, which hosted runs on a card):
  // a store purchase would bill twice, and the portal is off limits here.
  if (session.isWebBilled) return UpgradeRoute.planScreen;

  // A plan is bought for the whole account, and only its owner may buy it.
  // Checked before the ended-subscription branch: the store page on someone
  // else's device holds nothing of the owner's.
  if (!canBuyForActiveAccount(session)) return UpgradeRoute.planScreen;

  if (lapsedIapRecently) return UpgradeRoute.storeSubscriptionsEnded;

  return UpgradeRoute.purchaseSheet;
}

/// Whether an upgrade on this build could only say the plan is managed on
/// the web: a store build ([storeBilling]) with a trial or a web-billed plan
/// ([AuthSession.isWebBilled]), which [resolveUpgradeRoute] sends to the Plan
/// screen. Every upgrade prompt then shows that, with no button: a store build
/// may not link to the web billing, and a store plan would bill twice. A
/// long-expired web plan is a free account again (the slug is blank), so it
/// is offered the purchase sheet like any other.
bool planManagedOnWeb({
  required bool storeBilling,
  required AuthSession? session,
}) =>
    storeBilling && session != null && session.isHosted && session.isWebBilled;

/// Whether the signed-in user may buy a plan in-app for the active company's
/// account: they own the active company. Which account a purchase lands on is
/// the hosted config's answer (`account_key`, `IapConfig.sellsTo`), checked
/// when the sheet opens, since the hosted endpoint applies a purchase to the
/// user's own account, which may not be the active company's.
bool canBuyForActiveAccount(AuthSession session) =>
    session.currentCompany?.isOwner ?? false;

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
