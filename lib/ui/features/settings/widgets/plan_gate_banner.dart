import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/link_text.dart';

/// Visual variant for [PlanGateBanner]. `inset` is the card form (sits inside
/// a page body, padded as a section header); `stripe` is the full-width
/// edge-to-edge form used directly below a TabBar.
enum PlanGateStyle { inset, stripe }

/// Tier the surface is gated behind. Drives the displayed wording and the
/// visibility predicate the banner uses to auto-hide itself.
enum PlanGateLevel { pro, enterprise }

/// Reusable upgrade-nudge banner for plan-gated settings surfaces.
///
/// Replaces the two divergent inline banners (`_PlanGateBanner` in
/// `templates_reminders_body.dart` and `_ProPlanBanner` in
/// `custom_fields_shell.dart`) with a single component:
///
/// - Listens to `services.auth.session` so the banner appears / disappears
///   live when a `/refresh` flips the plan.
/// - Hides itself when the user already has access (so call sites can drop
///   it in unconditionally without a wrapping `if`).
/// - Owner-aware copy: non-owners cannot act on the upgrade, so they see
///   `owner_upgrade_to_paid_plan` with no link CTA; nor does a store build's
///   trial or web-billed plan, which the store cannot change
///   (`plan_managed_on_web`).
/// - CTA helper [openUpgradeFlow] launches `ninjaPortalUrl` externally when
///   set, otherwise navigates to `/settings/account_management` (the Plan tab).
class PlanGateBanner extends StatelessWidget {
  const PlanGateBanner({
    required this.style,
    this.level = PlanGateLevel.pro,
    super.key,
  });

  final PlanGateStyle style;
  final PlanGateLevel level;

  @override
  Widget build(BuildContext context) {
    final session = context.read<Services>().auth.session;
    return ValueListenableBuilder<AuthSession?>(
      valueListenable: session,
      builder: (context, value, _) {
        if (value == null || _hasAccess(value)) {
          return const SizedBox.shrink();
        }
        return _body(context, value);
      },
    );
  }

  // Trial-aware so the banner auto-hides for trialing users (who get full
  // features for free) — gating them would be a regression vs both
  // reference apps.
  bool _hasAccess(AuthSession s) => level == PlanGateLevel.enterprise
      ? s.hasEnterpriseAccess
      : s.hasProAccess;

  Widget _body(BuildContext context, AuthSession session) {
    // Default to owner-style copy + CTA when we don't yet know the role
    // (fresh login, cold restore before /refresh populates `companies`).
    // The non-owner copy is more restrictive — only show it when we're
    // certain the user can't act on the upgrade.
    final me = session.currentCompany;
    final isOwner = me == null ? true : me.isOwner;
    final withheld = purchasesWithheld(context, session: session);
    final copy = planGateCopy(
      level,
      session,
      isOwner: isOwner,
      route: resolveUpgradeRoute(
        storeBilling: isStoreBillingBuild,
        session: session,
        now: DateTime.now(),
        purchasesOffered: !withheld,
      ),
      purchasesWithheld: withheld,
      storeOpen: withheld && inAppStoreOpenIn(context),
    );
    switch (style) {
      case PlanGateStyle.inset:
        return _InsetCard(copy: copy);
      case PlanGateStyle.stripe:
        return _StripeBar(copy: copy);
    }
  }
}

/// Resolved banner message: localization key, optional substitution params,
/// and whether it carries the upgrade button ([cta]).
typedef PlanGateCopy = ({String key, Map<String, String>? params, bool cta});

/// State-aware copy, for where an upgrade tap would go ([route],
/// `resolveUpgradeRoute`). A used-trial or expired-paid user must never be
/// told to "start a free trial" (a dead-end lie). Order matters: trial
/// countdown and expiry-renewal take precedence over the generic upgrade
/// nudge.
///
/// The trial is promised only where the tap opens the web billing
/// ([UpgradeRoute.billingPortal]): on a store build a hosted trial starts on
/// the web with a card, and the store sheet the button opens sells a paid
/// plan. And on a store build a trial or web-billed plan gets no button at
/// all ([planManagedOnWeb]): it would only reach a Plan screen saying the
/// plan is managed on the web.
///
/// A store build whose hosted service sells nothing to this account
/// ([purchasesWithheld]) says only which plans the feature is on: no button,
/// nothing to buy, upgrade or start (App Store 3.1.3(f), Play Payments
/// policy). A member is told the owner can upgrade only once the store sells
/// at all ([storeOpen], `purchases_open`), still with no button.
@visibleForTesting
PlanGateCopy planGateCopy(
  PlanGateLevel level,
  AuthSession s, {
  required bool isOwner,
  required UpgradeRoute route,
  bool purchasesWithheld = false,
  bool storeOpen = false,
}) {
  if (route == UpgradeRoute.planScreen && s.isWebBilled && isOwner) {
    return (key: 'plan_managed_on_web', params: null, cta: false);
  }
  if (purchasesWithheld && !isOwner && storeOpen) {
    return (key: 'owner_upgrade_to_paid_plan', params: null, cta: false);
  }
  if (purchasesWithheld) {
    return (
      key: level == PlanGateLevel.enterprise
          ? 'requires_an_enterprise_plan'
          : 'feature_needs_pro_or_enterprise',
      params: null,
      cta: false,
    );
  }
  if (!isOwner) {
    return (key: 'owner_upgrade_to_paid_plan', params: null, cta: false);
  }
  if (s.isTrial) {
    return (
      key: 'free_trial_ends_in_days',
      params: {'count': '${s.trialDaysRemaining}'},
      cta: true,
    );
  }
  // Hosted account that previously paid (non-empty slug) but lapsed.
  if (s.isHosted && s.plan.isNotEmpty && s.isPlanExpired) {
    return (key: 'plan_expired_renew', params: null, cta: true);
  }
  if (level == PlanGateLevel.enterprise) {
    // Not `enterprise_plan_features` — it ends with ":link to see the full
    // list of features" and this banner has no link to substitute. This key
    // is placeholder-free, translated, and matches the sibling copy's length.
    return (key: 'requires_an_enterprise_plan', params: null, cta: true);
  }
  if (s.isEligibleForTrial && route == UpgradeRoute.billingPortal) {
    return (key: 'start_free_trial_message', params: null, cta: true);
  }
  return (key: 'upgrade_to_paid_plan', params: null, cta: true);
}

/// Opens the user's upgrade flow. Delegates to the single platform-conditional
/// [launchUpgrade] seam (store IAP on store builds, portal elsewhere) so
/// the App Store payment-steering rule is enforced in one place. Kept as a
/// thin alias so existing banner call sites don't change.
Future<void> openUpgradeFlow(BuildContext context) => launchUpgrade(context);

class _InsetCard extends StatelessWidget {
  const _InsetCard({required this.copy});

  final PlanGateCopy copy;

  @override
  Widget build(BuildContext context) {
    final t = context.inTheme;
    final theme = Theme.of(context);
    final message = context.tr(copy.key, copy.params);
    // `Semantics(container: true)` collapses the icon + body text + button into
    // a single semantic node for assistive tech, so the screen reader
    // announces "Upgrade required, button: Manage Plan" instead of three
    // disconnected reads.
    return Semantics(
      container: true,
      label: message,
      child: Padding(
        padding: EdgeInsets.only(bottom: InSpacing.lg(context)),
        child: Container(
          decoration: BoxDecoration(
            color: t.accentSoft,
            borderRadius: BorderRadius.circular(InRadii.r3),
            border: Border.all(color: t.border),
          ),
          padding: EdgeInsets.all(InSpacing.lg(context)),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: t.accent),
              const SizedBox(width: InSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.ink),
                ),
              ),
              if (copy.cta) ...[
                const SizedBox(width: InSpacing.sm),
                OutlinedButton(
                  onPressed: () => unawaited(openUpgradeFlow(context)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 40),
                  ),
                  child: Text(context.tr('plan_change')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StripeBar extends StatelessWidget {
  const _StripeBar({required this.copy});

  final PlanGateCopy copy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(color: tokens.ink);
    final message = context.tr(copy.key, copy.params);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: InSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: tokens.ink),
          const SizedBox(width: InSpacing.sm),
          Expanded(child: Text(message, style: bodyStyle)),
          if (copy.cta) ...[
            SizedBox(width: InSpacing.md(context)),
            LinkText(
              label: context.tr('plan_change'),
              style: bodyStyle,
              color: tokens.accent,
              onTap: () => unawaited(openUpgradeFlow(context)),
            ),
          ],
        ],
      ),
    );
  }
}
