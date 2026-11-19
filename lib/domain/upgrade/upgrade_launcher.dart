import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/domain/upgrade/purchase_service.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/external_url.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/auth/widgets/name_required_dialog.dart';

/// The single upgrade entry point. **Every** upgrade surface (the
/// `PlanGateBanner` CTA, the Plan screen's "Upgrade / Change Plan" button, the
/// company picker's plan-limited "New Company" row) routes here, so the store
/// rules are enforced in one place: a store build never sends anyone to an
/// external purchase (App Store 3.1.1(a), Play Payments 4), and never sells a
/// second subscription while one may still bill.
///
/// Where each tap goes is [resolveUpgradeRoute]'s pure decision
/// (upgrade_route.dart); this carries it out.
Future<void> launchUpgrade(BuildContext context) async {
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
  final route = resolveUpgradeRoute(
    storeBilling: isStoreBillingBuild,
    session: session,
    now: DateTime.now(),
  );
  switch (route) {
    case UpgradeRoute.billingPortal:
      await _openPortalOrPlanScreen(context, session?.ninjaPortalUrl ?? '');
    case UpgradeRoute.planScreen:
      await _openPortalOrPlanScreen(context, '');
    case UpgradeRoute.storeSubscriptions:
      await openManageSubscriptions();
    case UpgradeRoute.storeSubscriptionsEnded:
      Notify.info(context, context.tr('app_store_subscription_ended'));
      await openManageSubscriptions();
    case UpgradeRoute.purchaseSheet:
      await showUpgradeSheet(context);
  }
}

Future<void> _openPortalOrPlanScreen(BuildContext context, String url) async {
  if (url.isNotEmpty) {
    final uri = Uri.tryParse(url);
    // Falls through to the in-app destination when it doesn't open.
    if (uri != null && await launchExternalUri(uri)) return;
  }
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
/// lifetime so the purchase-stream subscription is scoped to the sheet.
Future<void> showUpgradeSheet(BuildContext context) async {
  final services = context.read<Services>();
  final svc = PurchaseService(
    apiClient: services.apiClient,
    auth: services.auth,
  );
  if (!await svc.isAvailable) {
    // Store billing unreachable (no Play Services, not signed in to the
    // store). Only store builds open this sheet ([resolveUpgradeRoute]; the
    // F-Droid build takes the portal path), and a store build may not send
    // anyone to an external purchase, so: say so, and offer to try again.
    await svc.dispose();
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
  // Purchases stay off until the hosted service says it takes them (it fails
  // closed): no store sheet, so nobody pays for a plan that can't be applied.
  if (!await svc.purchasesEnabled()) {
    if (context.mounted) {
      Notify.info(context, context.tr('in_app_purchases_unavailable'));
    }
    await svc.dispose();
    return;
  }
  await svc.init();
  if (!context.mounted) {
    await svc.dispose();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _UpgradeSheet(service: svc),
  );
  await svc.dispose();
}

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet({required this.service});

  final PurchaseService service;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(InSpacing.lg(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('upgrade'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: InSpacing.md(context)),
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
                        ListTile(
                          title: Text(p.title),
                          subtitle: Text(p.description),
                          trailing: Text(
                            p.price,
                            style: TextStyle(color: tokens.accentInk),
                          ),
                          onTap: busy ? null : () => service.buy(p),
                        ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: InSpacing.md(context)),
            TextButton(
              onPressed: () => service.restore(),
              child: Text(context.tr('restore_purchases')),
            ),
            // A Legacy-app subscription can't be restored here, and needn't
            // be: the plan is on the account already.
            Text(
              context.tr('restore_purchases_help'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
