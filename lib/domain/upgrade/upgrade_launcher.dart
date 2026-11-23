import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/domain/upgrade/purchase_offer.dart';
import 'package:admin/domain/upgrade/purchase_service.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/external_url.dart';
import 'package:admin/ui/core/widgets/legal_links.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/auth/widgets/name_required_dialog.dart';
import 'package:admin/utils/url_safety.dart';

/// The single upgrade entry point. **Every** upgrade surface (the
/// `PlanGateBanner` CTA, the Plan screen's "Upgrade / Change Plan" button, the
/// company picker's plan-limited "New Company" row) routes here, so the store
/// rules are enforced in one place: a store build never sends anyone to an
/// external purchase (App Store 3.1.1(a), Play Payments 4), and never sells a
/// second subscription while one may still bill.
///
/// Where each tap goes is [resolveUpgradeRoute]'s pure decision
/// (upgrade_route.dart); this carries it out. One at a time: a second tap
/// while one is still deciding (asking for the user's name, or the hosted
/// config) or has its sheet open does nothing.
Future<void> launchUpgrade(BuildContext context) async {
  if (upgradeBusy.value) return;
  upgradeBusy.value = true;
  try {
    await _launchUpgrade(context);
  } finally {
    upgradeBusy.value = false;
  }
}

/// True while a [launchUpgrade] runs, which can take seconds before anything
/// shows (the name prompt, the hosted config, the store): the Plan card's
/// button spins and refuses a second tap, rather than looking dead.
final ValueNotifier<bool> upgradeBusy = ValueNotifier<bool>(false);

/// Whether a [launchUpgrade] is still running.
@visibleForTesting
bool get upgradeInProgress => upgradeBusy.value;

/// Stands in for the hosted config's answer in tests, as
/// [debugStoreBillingOverride] stands in for the build: true is a store build
/// whose hosted service sells to the active account. Null in the app, where
/// the answer is the root [PurchaseOffer] (none in most widget tests, which
/// reads as not offered).
@visibleForTesting
bool? debugInAppPurchasesOfferedOverride;

/// Whether the hosted service offers an in-app purchase to the active
/// account ([PurchaseOffer], set by `PurchaseDelivery` from the hosted
/// config): false with none provided. [listen] subscribes [context], for a
/// build method; pass false from a callback.
bool inAppPurchasesOfferedIn(BuildContext context, {bool listen = true}) {
  final override = debugInAppPurchasesOfferedOverride;
  if (override != null) return override;
  final offer = listen
      ? context.watch<PurchaseOffer?>()
      : context.read<PurchaseOffer?>();
  return offer?.offered ?? false;
}

/// Stands in for the hosted config's `purchases_open` in tests. Null: the
/// [debugInAppPurchasesOfferedOverride] when that is set (a store that sells
/// to the account is open), else the root [PurchaseOffer].
@visibleForTesting
bool? debugInAppStoreOpenOverride;

/// Whether the hosted service sells in-app at all ([PurchaseOffer.open],
/// `inAppStoreOpen`), perhaps not to this account: false with no provider.
/// [listen] as for [inAppPurchasesOfferedIn].
bool inAppStoreOpenIn(BuildContext context, {bool listen = true}) {
  final override =
      debugInAppStoreOpenOverride ?? debugInAppPurchasesOfferedOverride;
  if (override != null) return override;
  final offer = listen
      ? context.watch<PurchaseOffer?>()
      : context.read<PurchaseOffer?>();
  return offer?.open ?? false;
}

/// Whether an upgrade prompt under [context] must offer no way to buy:
/// [storePurchasesWithheld] for [session] (the active session when not
/// given) on this build. Every surface that would show Upgrade, Buy, Restore,
/// a trial or "upgrade to …" copy asks this first, and says only which plan
/// the feature or limit belongs to when it answers true (docs/in-app-purchases.md).
///
/// Never true off a store-billing build or for a self-hosted session, and
/// reads nothing there: those keep the billing portal path unchanged.
bool purchasesWithheld(
  BuildContext context, {
  AuthSession? session,
  bool listen = true,
}) {
  if (!isStoreBillingBuild) return false;
  final s = session ?? context.read<Services?>()?.auth.session.value;
  if (s == null || !s.isHosted) return false;
  return storePurchasesWithheld(
    storeBilling: true,
    session: s,
    offered: inAppPurchasesOfferedIn(context, listen: listen),
  );
}

/// How long an Upgrade tap waits for the hosted config before it treats the
/// answer as no: the store plan is then managed in the store (fails closed).
const kUpgradeConfigTimeout = Duration(seconds: 8);

/// The hosted config, for the one case it can change where Upgrade goes: an
/// owner's active store plan on a Play build, which the config may offer to
/// replace (`replaces_v1_play`, [offersLegacyPlayReplacement]). Null for
/// everyone else (no request, and [purchases] is not read), and on no answer
/// within [timeout].
Future<IapConfig?> replacementConfigFor({
  required bool storeBilling,
  required PurchaseStore? store,
  required AuthSession? session,
  required PurchaseDelivery? Function() purchases,
  Duration timeout = kUpgradeConfigTimeout,
}) async {
  if (!storeBilling ||
      store != PurchaseStore.googlePlay ||
      session == null ||
      !session.isHosted ||
      !session.hasActiveIapPlan ||
      !canBuyForActiveAccount(session)) {
    return null;
  }
  final delivery = purchases();
  if (delivery == null) return null;
  try {
    return await delivery.config().timeout(timeout);
  } on TimeoutException {
    return null;
  }
}

Future<void> _launchUpgrade(BuildContext context) async {
  final services = context.read<Services>();
  // Hosted billing needs the user's first and last name (React #3341): ask
  // before checkout — required here, where elsewhere it's only a nudge — and
  // wait for the save to reach the server.
  if (needsUserName(services.auth.session.value)) {
    final saved = await promptForUserName(context, services, required: true);
    if (!saved || !context.mounted) return;
  }
  if (!context.mounted) return;
  final session = services.auth.session.value;
  final storeBilling = isStoreBillingBuild;
  final store = storeOfBuild;
  // An active store plan is sold over only when the hosted config says the
  // purchase replaces a Legacy-app Play subscription; the config is asked
  // (once per user and company, PurchaseDelivery) only where it could.
  final config = await replacementConfigFor(
    storeBilling: storeBilling,
    store: store,
    session: session,
    purchases: () => services.purchases,
  );
  if (!context.mounted) return;
  final route = resolveUpgradeRoute(
    storeBilling: storeBilling,
    session: session,
    now: DateTime.now(),
    purchasesOffered: inAppPurchasesOfferedIn(context, listen: false),
    store: store,
    config: config,
  );
  switch (route) {
    case UpgradeRoute.billingPortal:
      await _openPortalOrPlanScreen(context, session?.ninjaPortalUrl ?? '');
    case UpgradeRoute.planScreen:
      await _openPortalOrPlanScreen(context, '');
    case UpgradeRoute.storeSubscriptions:
      // Said before the app switches away, or the store simply appears.
      Notify.info(context, context.tr('plan_billed_in_app_store'));
      await openManageSubscriptions();
    case UpgradeRoute.storeSubscriptionsEnded:
      Notify.info(context, context.tr('store_subscription_ended_renew'));
      await openManageSubscriptions();
    case UpgradeRoute.purchaseSheet:
    case UpgradeRoute.legacyPlayReplacement:
      // The sheet reads the same config, and says the Legacy subscription is
      // replaced only on its word (PurchaseService.replacesLegacyPlay).
      await showUpgradeSheet(context);
  }
}

Future<void> _openPortalOrPlanScreen(BuildContext context, String url) async {
  // A server-sent URL: only an http(s) page is handed to the launcher. Falls
  // through to the in-app destination when it isn't one, or doesn't open.
  final uri = isSafeWebUrl(url) ? Uri.tryParse(url) : null;
  if (uri != null && await launchExternalUri(uri)) return;
  if (!context.mounted) return;
  // Plan is the Account Management shell's bare-URL default tab; `/plan` is not
  // a matchable route (it would land on the route-error view).
  context.go('/settings/account_management');
}

/// The store's own subscription management, for a plan bought in-app — the
/// one place a store-billed subscription can be changed or cancelled.
Future<void> openManageSubscriptions() => openStoreSubscriptions(
  platform: defaultTargetPlatform,
  launch: launchExternalUri,
);

/// The store's subscriptions page, for an IAP-billed plan. Neither is payment
/// steering.
///
/// Apple's is the web page, never StoreKit's in-app sheet: that sheet lists
/// only *this* app's subscriptions, so a plan bought in the Legacy app would
/// not be there. The page lists every subscription on the Apple ID, and opens
/// the App Store's account page on iOS and macOS alike.
@visibleForTesting
Future<void> openStoreSubscriptions({
  required TargetPlatform platform,
  required Future<bool> Function(Uri) launch,
}) async {
  await launch(
    platform == TargetPlatform.android
        ? Uri.parse('https://play.google.com/store/account/subscriptions')
        : Uri.parse('https://apps.apple.com/account/subscriptions'),
  );
}

/// Bottom sheet listing the store products. Owns a [PurchaseService] for its
/// lifetime, which lists the products and starts a purchase; the purchase
/// itself is delivered by the app-lifetime [PurchaseDelivery]
/// (`Services.purchases`), and the sheet closes once one is applied.
Future<void> showUpgradeSheet(BuildContext context) async {
  final services = context.read<Services>();
  final delivery = services.purchases;
  final svc = delivery == null
      ? null
      : PurchaseService(auth: services.auth, delivery: delivery);
  if (svc == null || !await svc.isAvailable) {
    // Store billing unreachable (no Play Services, not signed in to the
    // store). Only store builds open this sheet ([resolveUpgradeRoute]; the
    // F-Droid build takes the portal path), and a store build may not send
    // anyone to an external purchase, so: say so, and offer to try again.
    await svc?.dispose();
    if (context.mounted) {
      Notify.error(
        context,
        context.tr('store_billing_unreachable'),
        retryOp: () async {
          if (context.mounted) await showUpgradeSheet(context);
        },
      );
    }
    return;
  }
  // Purchases stay off until the hosted service says it takes them, and has
  // given this account a token to tie one to (it fails closed): no store
  // sheet, so nobody pays for a plan that can't be applied.
  if (!await svc.loadConfig()) {
    if (context.mounted) {
      Notify.info(context, context.tr('in_app_purchases_unavailable'));
    }
    await svc.dispose();
    return;
  }
  // The hosted service applies a purchase to the user's own account (the
  // config's `account_key`); while a company of another account is active,
  // a plan bought here would never reach that company. A session that does
  // not know its account key yet is not "another account".
  //
  // A live store plan is sold over only when the purchase replaces a Legacy
  // Play subscription (the config's `replaces_v1_play`): anything else is
  // managed in the store, never billed twice.
  if (svc.saleRefusal case final refusal?) {
    await svc.dispose();
    final message = switch (refusal) {
      SaleRefusal.unavailable => 'in_app_purchases_unavailable',
      SaleRefusal.otherAccount => 'store_purchase_own_account_only',
      SaleRefusal.activeStorePlan => null,
    };
    if (message == null) {
      if (context.mounted) {
        Notify.info(context, context.tr('plan_billed_in_app_store'));
      }
      await openManageSubscriptions();
    } else if (context.mounted) {
      Notify.info(context, context.tr(message));
    }
    return;
  }
  // A store account that already subscribes in this app would be billed
  // twice: the sheet offers only Restore then.
  final alreadySubscribed = await svc.hasActiveStoreSubscription();
  await svc.init();
  if (!context.mounted) {
    await svc.dispose();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => UpgradeSheet(
      service: svc,
      store: delivery!.store,
      alreadySubscribed: alreadySubscribed,
      replacesLegacyPlay: svc.replacesLegacyPlay,
    ),
  );
  await svc.dispose();
}

/// The purchase sheet's body. Lists each plan with what App Review 3.1.2 and
/// Play's subscriptions policy require next to a subscription's buy button:
/// its name, how often it bills, the billed amount as the most prominent
/// figure, the store's auto-renew and cancel terms, and the privacy policy
/// and terms of service.
@visibleForTesting
class UpgradeSheet extends StatefulWidget {
  const UpgradeSheet({
    super.key,
    required this.service,
    required this.store,
    this.alreadySubscribed = false,
    this.replacesLegacyPlay = false,
  });

  final PurchaseService service;

  /// Whose renewal terms to state. Never the other store's: App Review
  /// rejects a build that names Google Play, and the reverse reads as wrong.
  final PurchaseStore store;

  /// This store account already subscribes in this app (StoreKit's current
  /// entitlements, Play's owned subscriptions): say so and offer Restore,
  /// instead of selling a second.
  final bool alreadySubscribed;

  /// A plan bought here replaces the account's Legacy-app Google Play
  /// subscription ([PurchaseService.replacesLegacyPlay]): say that the Legacy
  /// one is cancelled, and its unused time refunded, once the new one is
  /// active.
  final bool replacesLegacyPlay;

  @override
  State<UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<UpgradeSheet> {
  StreamSubscription<PurchaseActivity>? _sub;
  bool _closed = false;

  /// "Will be applied later" is said once per sheet: the delivery tries
  /// again with a backoff, and each try that fails reports it again.
  bool _toldRetryLater = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.outcomes.listen(_onOutcome);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _onOutcome(PurchaseActivity a) {
    if (!mounted) return;
    switch (a.kind) {
      case PurchaseActivityKind.applied:
        // The first applied purchase ends the sale; the plan is on the
        // account now (the delivery refreshed the session).
        if (_closed) return;
        _closed = true;
        Notify.success(context, context.tr('thank_you_for_your_purchase'));
        Navigator.of(context).pop();
      case PurchaseActivityKind.rejected:
        Notify.error(
          context,
          context.tr('store_purchase_not_applied'),
          detail: _nonBlank(a.message),
        );
      case PurchaseActivityKind.retryLater:
        if (_toldRetryLater) return;
        _toldRetryLater = true;
        Notify.warning(context, context.tr('store_purchase_retry_later'));
      case PurchaseActivityKind.failed:
        Notify.error(
          context,
          context.tr('store_purchase_failed'),
          detail: _nonBlank(a.message),
        );
      case PurchaseActivityKind.pending:
      case PurchaseActivityKind.delivering:
      case PurchaseActivityKind.canceled:
        break;
    }
  }

  static String? _nonBlank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final tokens = context.inTheme;
    final textTheme = Theme.of(context).textTheme;
    final caption = textTheme.bodySmall?.copyWith(color: tokens.ink2);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(InSpacing.lg(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              headingLevel: 1,
              child: Text(context.tr('upgrade'), style: textTheme.titleLarge),
            ),
            SizedBox(height: InSpacing.md(context)),
            if (widget.alreadySubscribed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  key: const ValueKey('store_subscription_already_active'),
                  context.tr(switch (widget.store) {
                    PurchaseStore.appStore =>
                      'store_subscription_already_active',
                    PurchaseStore.googlePlay =>
                      'store_subscription_already_active_google',
                  }),
                ),
              )
            else ...[
              if (widget.replacesLegacyPlay)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    key: const ValueKey('store_replaces_legacy_play'),
                    context.tr('store_legacy_play_replaced_on_subscribe'),
                  ),
                ),
              ValueListenableBuilder<bool>(
                valueListenable: service.busy,
                builder: (context, busy, _) => ValueListenableBuilder(
                  valueListenable: service.products,
                  builder: (context, products, _) {
                    if (busy && products.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (products.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(context.tr('no_results')),
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in products)
                          _PlanTile(
                            product: p,
                            onTap: busy ? null : () => service.buy(p),
                          ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(height: InSpacing.md(context)),
              Text(
                context.tr(switch (widget.store) {
                  PurchaseStore.appStore => 'store_auto_renew_terms_apple',
                  PurchaseStore.googlePlay => 'store_auto_renew_terms_google',
                }),
                key: const ValueKey('store_auto_renew_terms'),
                style: caption,
              ),
            ],
            const LegalLinks(alignment: WrapAlignment.center),
            TextButton(
              onPressed: () => service.restore(),
              child: Text(context.tr('restore_purchases')),
            ),
            // A Legacy-app subscription can't be restored here, and needn't
            // be: the plan is on the account already.
            Text(
              context.tr('restore_purchases_help'),
              textAlign: TextAlign.center,
              style: caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// One plan: its name and billing period, and the price it bills — the
/// largest figure on the row.
class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.product, required this.onTap});

  final StoreProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final textTheme = Theme.of(context).textTheme;
    final description = product.description.trim();
    return ListTile(
      title: Text(product.title),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(switch (billingPeriodOf(product.id)) {
              PlanBillingPeriod.monthly => 'store_billed_monthly',
              PlanBillingPeriod.yearly => 'store_billed_yearly',
            }),
          ),
          if (description.isNotEmpty) Text(description),
        ],
      ),
      // A store-formatted amount: laid out left-to-right in every language,
      // unless the store wrote it in an RTL script.
      trailing: LtrText(
        product.price,
        keepRtlScript: true,
        style: textTheme.titleMedium?.copyWith(
          color: tokens.accentInk,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: onTap,
    );
  }
}
