import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/upgrade/client_limit.dart';
import 'package:admin/domain/upgrade/client_usage.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/domain/upgrade/store_build.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/domain/upgrade/upgrade_route.dart';
import 'package:admin/domain/upgrade/white_label.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/features/clients/widgets/client_limit.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/ui/core/fold_geometry.dart';

/// Search keys for the Plan tab, spread into `kSettingsSearchCatalog` so this
/// list is the single source (it used to be duplicated there by hand, and had
/// already drifted — that is how `purchase_license` outlived the button it
/// named).
///
/// Deliberately NOT registered in `search_catalog_consistency_test`: that
/// harness is a text scan for `context.tr('<key>')` literals, and most labels
/// here are looked up through a computed key (`planHeadlineKey`, the
/// upgrade/change `labelKey`), which it cannot see and has no allowlist for.
/// `plan_headline_test` asserts the computed side instead.
const kAccountManagementPlanSearchKeys = <String>[
  'plan',
  'free',
  'pro',
  'enterprise',
  'free_trial',
  'change_plan',
  'expires_on',
  // The rendered string is `days_left` (":days days left") with the count
  // substituted; search shows a field key raw, so it indexes the plain label.
  'days_left_label',
  // Self-hosted White Label card. `white_label_button` ("Purchase White
  // Label") is the string on the button — NOT `purchase_license`, which this
  // screen stopped rendering when the card moved off the Overview tab.
  'white_label',
  'white_label_button',
  'renew_license',
  'apply_license',
  'white_label_expired',
  'license',
];

/// Localization key for the plan headline. Shared by this tab's status card
/// and the Overview tab's plan card, which sit two tabs apart and must not
/// disagree about the same account.
///
/// Hosted reads the plan slug. Self-hosted has no hosted plan, so it reports
/// *license* state instead — the bare "Free" this used to render read as a
/// downgrade on an install where every feature is in fact unlocked, and said
/// nothing about the white-label license the user may have bought (issue #27).
/// React does the same in its `Plan.tsx`, labelling a live license `licensed`;
/// we use the more explicit `plan_white_label` ("Self Hosted (White labeled)")
/// against `plan_free_self_hosted` ("Self Hosted (Free)"). Both keys already
/// ship in every bundled locale.
String planHeadlineKey(AuthSession session) {
  if (session.isSelfHosted) {
    return session.isWhiteLabeled
        ? 'plan_white_label'
        : 'plan_free_self_hosted';
  }
  return session.plan.isEmpty ? 'free' : session.plan;
}

/// Account Management → Plan. Read-mostly surface. The server pre-computes
/// `ninja_portal_url` (per-user hosted-billing URL); the screen displays the
/// current plan state and routes hosted users to that URL for upgrades /
/// downgrades / payment-method management. We do not render plan tiles or
/// payment methods in-app — the hosted page already does both natively and
/// pulling them client-side requires `account_key` plumbing that's not worth
/// the round-trip.
///
/// Self-hosted users see their license state (see [planHeadlineKey]) plus the
/// license expiry when one is applied, and — this is what makes the tab worth
/// visiting on a self-hosted install (issue #41) — the White Label card that
/// owns Purchase / Renew / Apply License. That card used to sit two tabs away
/// on Overview, leaving Plan with a single line of text and nothing to do.
/// React puts it here too (`Plan.tsx:70`).
class AccountManagementPlanScreen extends StatelessWidget {
  const AccountManagementPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<Services>().auth.session;
    return ValueListenableBuilder<AuthSession?>(
      valueListenable: session,
      builder: (context, value, _) {
        if (value == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return SettingsFormShell(
          subtitle: context.tr('account_management_subtitle'),
          sections: [
            _PlanStatusCard(session: value),
            // What the hosted Free plan includes, with live usage
            // (docs/free-plan-limits.md). Never self-hosted, which has no
            // limits.
            if (freePlanClientLimit(value) case final limit?)
              _FreePlanLimitsCard(session: value, limit: limit),
            // Self-hosted only, and mutually exclusive with the hosted card
            // below — `showWhiteLabelCard` owns that guard, because
            // `isWhiteLabeled` alone is true on hosted too.
            if (showWhiteLabelCard(value))
              _SelfHostedLicenseCard(session: value),
            if (showsHostedActionsCard(
              value,
              purchasesWithheld: purchasesWithheld(context, session: value),
              storeOpen: inAppStoreOpenIn(context),
            ))
              _HostedActionsCard(session: value),
          ],
        );
      },
    );
  }
}

/// Whether the Plan tab shows its hosted Change Plan card. Always on hosted,
/// except on a store build whose hosted service sells nothing to the account
/// ([purchasesWithheld]): there the card would hold only a disabled Upgrade,
/// so it is left out, unless it has something to manage or explain (a store
/// plan, which keeps Manage subscription, or a plan billed on the web) or
/// the store sells at all ([storeOpen], `purchases_open`): then it carries
/// Restore for the owner, or "only the owner can change the plan".
@visibleForTesting
bool showsHostedActionsCard(
  AuthSession session, {
  required bool purchasesWithheld,
  bool storeOpen = false,
}) {
  if (!session.isHosted) return false;
  if (!purchasesWithheld || storeOpen) return true;
  return session.hasIapPlan || session.isWebBilled;
}

/// Plan-expiry display: format through the active company's [Formatter] so it
/// honors `date_format_id`, falling back to the raw date-only prefix when that
/// company's formatter isn't cached yet (rare — the active company's formatter
/// is loaded on company switch).
String _expiryDisplay(BuildContext context, AuthSession session) {
  final fmt = context.read<Services>().formatterIfReady(
    session.currentCompanyId,
  );
  final formatted = fmt?.date(session.planExpires) ?? '';
  return formatted.isNotEmpty
      ? formatted
      : session.planExpires.split(' ').first;
}

class _PlanStatusCard extends StatelessWidget {
  const _PlanStatusCard({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;

    // A trial is a hosted-only concept, and `session.isTrial` must NOT be
    // trusted on self-hosted. The server sends
    // `trial_days_left = isSelfHost() ? getTrialDays() : 0`
    // (`AccountTransformer`), and `Account::getTrialDays()` returns the days
    // remaining until `plan_expires` whenever that is within 14 — so on a
    // self-hosted install the field is a *white-label license* countdown, and
    // `isTrial` flips true for the last fortnight of a valid license. Gating
    // the trial chrome on `isHosted` keeps a licensed self-host from being
    // told it's on a free trial (with a bogus bar: the transformer never
    // sends `num_trial_days`, so the progress math clamps to 0).
    final isTrialing = session.isHosted && session.isTrial;
    // A hosted trial as the server really sends it (`plan: pro` and its end
    // date; `isTrial` cannot see it there — see [hostedTrialEndsOn]). Its end
    // is when the Free plan's client cap starts to apply, so it is said here.
    final trialEnds = hostedTrialEndsOn(session);
    final planLabel = context.tr(planHeadlineKey(session));
    final headline = isTrialing || trialEnds != null
        ? '$planLabel • ${context.tr('free_trial')}'
        : planLabel;
    // Hosted: the plan's renewal date. Self-hosted: the white-label license's
    // expiry — the one actionable date self-hosted has (renew from the White
    // Label card below). An unlicensed self-host has no usable `plan_expires`
    // (see `AuthSession.planExpiresDate` for the sentinel dates). The
    // self-hosted branch deliberately skips the `isTrial` check above, or the
    // date would disappear during the exact fortnight it matters most.
    final showExpiry =
        trialEnds == null &&
        session.planExpires.isNotEmpty &&
        (session.isHosted
            ? (!session.isTrial && session.plan.isNotEmpty)
            // Lapsed counts too: the card below says the license expired, and
            // "expired" without a date is the less useful half of that.
            : (session.isWhiteLabeled || session.isWhiteLabelLapsed));

    return FormSection(
      title: context.tr('plan'),
      spacing: 0,
      children: [
        Text(
          headline,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: tokens.ink,
          ),
        ),
        if (showExpiry) ...[
          SizedBox(height: InSpacing.sm),
          Text(
            '${context.tr('expires_on')} ${_expiryDisplay(context, session)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink2),
          ),
        ],
        if (isTrialing) ...[
          SizedBox(height: InSpacing.md(context)),
          _TrialProgress(session: session),
        ],
        if (trialEnds != null) ...[
          SizedBox(height: InSpacing.sm),
          Text(
            key: const ValueKey('plan_trial_ends'),
            context.tr('pro_trial_ends_on', {
              'date': _expiryDisplay(context, session),
              'count': formatClientCount(
                context,
                session.hostedClientCount > 0
                    ? session.hostedClientCount
                    : kFreePlanClientLimit,
              ),
            }),
            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink2),
          ),
        ],
        // Self-hosted: nothing more to render on this card — the White Label
        // section below owns Purchase/Renew/Apply License, and there's no
        // hosted-billing portal to link to.
      ],
    );
  }
}

/// What a hosted Free plan includes, said plainly so nobody meets the cap as
/// a surprise: the clients used of the cap (the server's total, refreshed on
/// opening — [ClientUsage]), the companies, and that archived and deleted
/// clients count too. An account over the cap (a plan or trial that lapsed)
/// is told its clients are kept. Upgrade is the Change Plan card's below.
class _FreePlanLimitsCard extends StatefulWidget {
  const _FreePlanLimitsCard({required this.session, required this.limit});

  final AuthSession session;
  final int limit;

  @override
  State<_FreePlanLimitsCard> createState() => _FreePlanLimitsCardState();
}

class _FreePlanLimitsCardState extends State<_FreePlanLimitsCard> {
  ClientUsage? _usage;

  @override
  void initState() {
    super.initState();
    _usage = context.read<ClientUsage?>();
    unawaited(_usage?.refresh(maxAge: const Duration(seconds: 15)));
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    if (usage == null) return _card(context, null);
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) => _card(context, usage.quota),
    );
  }

  Widget _card(BuildContext context, ClientQuota? quota) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final body = theme.textTheme.bodyMedium?.copyWith(color: tokens.ink);
    final hint = theme.textTheme.bodySmall?.copyWith(color: tokens.ink2);
    final companies = widget.session.hostedCompanyCount;
    final String clientsLine;
    if (quota == null) {
      clientsLine = context.tr('free_plan_up_to_clients', {
        'count': formatClientCount(context, widget.limit),
      });
    } else if (quota.state == ClientQuotaState.overLimit) {
      clientsLine = clientLimitReachedMessage(
        context,
        limit: quota.limit,
        used: quota.used,
      );
    } else {
      clientsLine = clientUsageMessage(context, quota);
    }
    return FormSection(
      key: const ValueKey('plan_free_limits'),
      title: context.tr('free_plan_limits'),
      children: [
        Text(
          clientsLine,
          key: const ValueKey('plan_free_clients'),
          style: body,
        ),
        if (quota != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(InRadii.r1),
            child: LinearProgressIndicator(
              value: (quota.used / quota.limit).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: tokens.border,
            ),
          ),
        Text(
          companies > 1
              ? context.tr('free_plan_up_to_companies', {
                  'count': formatClientCount(context, companies),
                })
              : context.tr('free_plan_one_company'),
          style: body,
        ),
        // The one place the way out of "deleted clients count" is said:
        // never in the add-a-client flow, where it would invite deleting
        // invoices to make room.
        Text(
          '${context.tr('free_plan_clients_count_note')} '
          '${context.tr('free_plan_purge_note')}',
          key: const ValueKey('plan_free_count_note'),
          style: hint,
        ),
      ],
    );
  }
}

class _TrialProgress extends StatelessWidget {
  const _TrialProgress({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final total = session.numTrialDays <= 0 ? 1 : session.numTrialDays;
    final remaining = session.trialDaysRemaining;
    final progress = ((total - remaining) / total).clamp(0.0, 1.0);
    final label = context
        .tr('days_left')
        .replaceAll(':days', remaining.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(InRadii.r1),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: tokens.border,
          ),
        ),
        SizedBox(height: InSpacing.sm),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink2),
        ),
      ],
    );
  }
}

class _HostedActionsCard extends StatefulWidget {
  const _HostedActionsCard({required this.session});

  final AuthSession session;

  @override
  State<_HostedActionsCard> createState() => _HostedActionsCardState();
}

class _HostedActionsCardState extends State<_HostedActionsCard> {
  /// The hosted config, asked only where it can change the route: an owner's
  /// active store plan on a Play build, which the config may offer to
  /// replace (a Legacy-app Play subscription, `replaces_v1_play`). Asked
  /// again for a new session (a delivered purchase refreshes it, and
  /// PurchaseDelivery forgets the answer then); otherwise PurchaseDelivery
  /// keeps the answer, so that is no second request.
  Future<IapConfig?>? _config;
  AuthSession? _configFor;

  Future<IapConfig?>? _configFuture(AuthSession session, bool withheld) {
    final asks =
        !withheld &&
        isStoreBillingBuild &&
        storeOfBuild == PurchaseStore.googlePlay &&
        session.hasActiveIapPlan &&
        canBuyForActiveAccount(session);
    if (!asks) return null;
    if (_config == null || !identical(_configFor, session)) {
      _configFor = session;
      _config = replacementConfigFor(
        storeBilling: isStoreBillingBuild,
        store: storeOfBuild,
        session: session,
        purchases: () => context.read<Services>().purchases,
      );
    }
    return _config;
  }

  @override
  Widget build(BuildContext context) {
    final withheld = purchasesWithheld(context, session: widget.session);
    final future = _configFuture(widget.session, withheld);
    if (future == null) return _card(context, null, withheld);
    // Until the config answers (or with no answer), the store plan is
    // managed in the store: nothing is offered over it.
    return FutureBuilder<IapConfig?>(
      future: future,
      builder: (context, snapshot) {
        // Asking: what the card offers depends on the answer, so it offers
        // nothing yet, rather than Manage subscription that then swaps for
        // the Legacy offer under the user's finger.
        if (snapshot.connectionState != ConnectionState.done) {
          return FormSection(
            title: context.tr('change_plan'),
            children: const [
              LinearProgressIndicator(
                key: ValueKey('plan_actions_loading'),
                minHeight: 2,
              ),
            ],
          );
        }
        return _card(context, snapshot.data, withheld);
      },
    );
  }

  Widget _card(BuildContext context, IapConfig? config, bool withheld) {
    final session = widget.session;
    final tokens = context.inTheme;
    final storeBilling = isStoreBillingBuild;
    final hint = TextStyle(color: tokens.ink2);
    // Restore re-delivers purchases already paid for, so it is offered to the
    // account's owner on a store-billing build whenever the store sells at
    // all (`purchases_open`): App Review requires a restore mechanism once
    // subscriptions are sold, including for a subscriber the config sells
    // nothing more to. Not before ([purchasesWithheld] and closed): nothing
    // can have been bought in this app then, and the button would read as a
    // way to buy (a purchase left over from a sale that was switched off is
    // still delivered on its own, at launch and on every resume).
    final storeOpen = !withheld || inAppStoreOpenIn(context);
    final showRestore =
        storeBilling && storeOpen && (session.currentCompany?.isOwner ?? false);

    // Where an Upgrade tap goes decides what this card offers, so the card
    // never shows a button that `launchUpgrade` would not honour.
    final route = resolveUpgradeRoute(
      storeBilling: storeBilling,
      session: session,
      now: DateTime.now(),
      purchasesOffered: !withheld,
      store: storeOfBuild,
      config: config,
    );

    Widget explained(String? key, {bool manage = false}) => FormSection(
      title: context.tr('change_plan'),
      children: [
        if (key != null) Text(context.tr(key), style: hint),
        if (manage)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(160, 40)),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(context.tr('manage_subscription')),
              onPressed: () => unawaited(openManageSubscriptions()),
            ),
          ),
        if (showRestore) const _RestorePurchasesButton(),
      ],
    );

    final String? disabledReason;
    switch (route) {
      case UpgradeRoute.storeSubscriptions:
        // Bought in this build's store: managed only in that store's
        // subscription settings (admin-portal's `isProPlan && hasIapPlan`).
        return explained('plan_billed_in_app_store', manage: true);
      case UpgradeRoute.planScreen:
        // Bought in a store, seen from desktop or the web (the subscription is
        // on someone's Apple ID or Google account, not this device), or one
        // that may still renew there.
        if (session.hasIapPlan) {
          return explained(
            session.hasActiveIapPlan
                ? 'plan_billed_in_app_store'
                // A store build that sells nothing says only that it ended,
                // not where to renew it.
                : withheld
                ? 'store_subscription_ended_info'
                : 'store_subscription_ended_renew',
          );
        }
        // A store build may not link to the web billing (App Store 3.1.1(a),
        // Play Payments 4), and selling a store plan on top of a web-billed
        // one (a trial runs on a card too) would bill twice.
        if (session.isWebBilled) return explained('plan_managed_on_web');
        // Nothing sold to this account, but the store sells (the card is
        // shown only then): Restore for the owner, the reason for a member.
        if (withheld) {
          return explained(
            canBuyForActiveAccount(session) ? null : 'store_plan_owner_only',
          );
        }
        // Only the owner of the active company can buy; anyone else's
        // Upgrade would only reopen this screen.
        disabledReason = 'store_plan_owner_only';
      case UpgradeRoute.billingPortal:
        // The button opens the hosted billing portal: with no URL yet (a
        // transient pre-refresh state) there's nowhere to send the user.
        disabledReason = session.ninjaPortalUrl.isEmpty
            ? 'error_refresh_page'
            : null;
      case UpgradeRoute.storeSubscriptionsEnded:
      case UpgradeRoute.purchaseSheet:
      case UpgradeRoute.legacyPlayReplacement:
        disabledReason = null;
    }
    // A Legacy-app Play subscriber may buy here: the new plan replaces the
    // Legacy one, which the hosted service then cancels and refunds.
    final replacesLegacy = route == UpgradeRoute.legacyPlayReplacement;
    final canUpgrade = disabledReason == null;
    // Decide button label: free → "Upgrade Plan"; paid → "Change Plan";
    // trial → "Upgrade Plan" so the user knows they're paying.
    // A Legacy Play subscriber is choosing a plan here, beside the store's
    // own management: two buttons that both read "Manage" told them apart
    // by nothing.
    final labelKey = replacesLegacy
        ? 'choose_plan_in_app'
        : session.isPaidPlanSlug && !session.isTrial
        ? 'change_plan'
        : 'upgrade_plan';

    return FormSection(
      title: context.tr('change_plan'),
      children: [
        if (replacesLegacy)
          Text(
            key: const ValueKey('plan_replaces_legacy_play'),
            context.tr('store_legacy_play_replaced_on_subscribe'),
            style: hint,
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: InSpacing.md(context),
            runSpacing: InSpacing.sm,
            children: [
              // Spins while an Upgrade is deciding (it can take seconds before
              // the sheet or the store shows), and takes no second tap.
              ValueListenableBuilder<bool>(
                valueListenable: upgradeBusy,
                builder: (context, busy, _) => FilledButton.icon(
                  key: const ValueKey('plan_upgrade'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                  ),
                  // The store's own sheet opens in place; the portal is a
                  // page in the browser.
                  icon: busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          storeBilling ? Icons.upgrade : Icons.open_in_new,
                          size: 18,
                        ),
                  label: Text(context.tr(labelKey)),
                  onPressed: canUpgrade && !busy
                      ? () => launchUpgrade(context)
                      : null,
                ),
              ),
              if (replacesLegacy)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(160, 40),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(context.tr('manage_in_google_play')),
                  onPressed: () => unawaited(openManageSubscriptions()),
                ),
            ],
          ),
        ),
        if (disabledReason != null)
          Padding(
            padding: EdgeInsets.only(top: InSpacing.sm),
            child: Text(
              context.tr(disabledReason),
              style: TextStyle(color: tokens.ink3),
            ),
          ),
        if (showRestore) const _RestorePurchasesButton(),
      ],
    );
  }
}

/// Restore Purchases, outside the purchase sheet: it asks the store to hand
/// back this store account's purchases, and the app-wide delivery applies
/// any the account doesn't have yet. Works while new purchases are switched
/// off, since it only re-delivers what was already paid for.
class _RestorePurchasesButton extends StatelessWidget {
  const _RestorePurchasesButton();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey('plan_restore_purchases'),
        icon: const Icon(Icons.restore, size: 18),
        label: Text(context.tr('restore_purchases')),
        onPressed: () {
          final delivery = context.read<Services>().purchases;
          if (delivery == null) return;
          Notify.info(context, context.tr('store_restore_requested'));
          unawaited(delivery.restore());
        },
      ),
    );
  }
}

/// Self-hosted white-label license: buy one, renew a lapsed one, or redeem a
/// key. Moved here from Account Management → Overview (issue #41) so the Plan
/// tab isn't a dead end on self-hosted; React renders the same pair on its
/// Plan tab (`Licence.tsx` via `Plan.tsx:70`).
///
/// **No price is shown, deliberately.** The server exposes none, and every
/// Transifex string that describes the offer carries a placeholder we cannot
/// fill — `white_label_text` (`:price`), `white_label_custom_css`
/// (`:link`/`:price`), `license_expiring` (`:count`/`:link`),
/// `reseller_text` (`:email`). Rendering one leaks the raw token and
/// `no_unsubstituted_placeholders_test` fails the build; hardcoding a price
/// would go stale the moment billing changes it. The checkout page states the
/// price. `white_label_expired` is the one placeholder-free line, so it's the
/// only prose here.
class _SelfHostedLicenseCard extends StatefulWidget {
  const _SelfHostedLicenseCard({required this.session});

  final AuthSession session;

  @override
  State<_SelfHostedLicenseCard> createState() => _SelfHostedLicenseCardState();
}

class _SelfHostedLicenseCardState extends State<_SelfHostedLicenseCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final session = widget.session;
    // `isWhiteLabeled` is the server-authoritative signal; `isWhiteLabelLapsed`
    // reads the past `plan_expires` the transformer still sends after the slug
    // has been blanked, which is the only way to tell "renew" from "buy".
    final licensed = session.isWhiteLabeled;
    final lapsed = session.isWhiteLabelLapsed;

    return FormSection(
      title: context.tr('white_label'),
      children: [
        if (lapsed)
          Text(
            context.tr('white_label_expired'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.ink2),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: InSpacing.md(context),
            runSpacing: InSpacing.sm,
            children: [
              // A licensed install has nothing to buy — only a key to re-apply
              // once they've renewed upstream.
              if (!licensed)
                FilledButton.icon(
                  // Explicit minimumSize: the theme default is
                  // `Size.fromHeight(44)` (= infinite width), which stretches
                  // edge-to-edge inside a Wrap.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                  ),
                  // The external-link glyph is the whole icon slot: a second
                  // decorative icon plus this label is wider than a phone once
                  // the string is translated (see the ellipsis note below).
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    context.tr(lapsed ? 'renew_license' : 'white_label_button'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _busy
                      ? null
                      : () => unawaited(launchWhiteLabelPurchase(context)),
                ),
              OutlinedButton(
                // Stable identity: on the licensed transition the Wrap's
                // children go [Filled, Outlined] -> [Outlined], so without a
                // key index 0 changes runtimeType and this button is torn
                // down and rebuilt rather than moved.
                key: const ValueKey('apply_license'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                ),
                onPressed: _busy ? null : () => _onApply(context),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        context.tr('apply_license'),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onApply(BuildContext context) async {
    final licenseKey = await _promptLicenseKey(context);
    if (licenseKey == null || licenseKey.isEmpty) return;
    if (!context.mounted) return;
    final services = context.read<Services>();
    final successMsg = context.tr('bought_white_label');
    final errorMsg = context.tr('error_refresh_page');
    // Captured before the await, not read from `context` after it. This
    // awaits `refresh(fullSync: true)` (10-30 s on a large install), and a
    // `TabBarView` tab switch during that window disposes this State — with a
    // plain `if (!mounted) return` the user would be told *nothing* about a
    // license that did or didn't apply. The toast host is global and outlives
    // the context; both strings are `tr()`-derived, which the captured path
    // requires (it has no blank-message fallback).
    final toasts = Notify.capture(context);
    setState(() => _busy = true);
    try {
      await services.auth.applyLicense(licenseKey);
      toasts?.success(successMsg);
    } catch (e) {
      toasts?.error(errorMsg, detail: formatNotifyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Inline single-field input dialog. Returns the trimmed entered value, or
/// null when the user cancels. Kept private to this screen — if a second
/// place ever needs it, lift to `lib/ui/core/widgets/`.
Future<String?> _promptLicenseKey(BuildContext context) => showDialog<String>(
  context: context,
  anchorPoint: foldAnchorPoint(context),
  builder: (_) => const _LicenseKeyDialog(),
);

/// Stateful so the `TextEditingController` is owned by an element and disposed
/// in `State.dispose()` — which runs after `finalizeRoute`. Disposing it after
/// `await showDialog(...)` would race the exit transition: `Route.didPop`
/// resolves that future immediately (routes deliberately "should not wait for
/// their exit animation"), leaving the autofocused field and its live
/// `TextInputConnection` mounted with a disposed controller behind them.
class _LicenseKeyDialog extends StatefulWidget {
  const _LicenseKeyDialog();

  @override
  State<_LicenseKeyDialog> createState() => _LicenseKeyDialogState();
}

class _LicenseKeyDialogState extends State<_LicenseKeyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('apply_license')),
      content: SizedBox(
        width: 360,
        child: FormSaveScope(
          enabled: true,
          onSubmit: _submit,
          child: LabeledField(
            label: context.tr('license'),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('license'),
                border: const InFieldOutlineBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              autocorrect: false,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        PrimaryDialogAction(
          label: context.tr('submit'),
          autofocus: false,
          onPressed: _submit,
        ),
      ],
    );
  }
}
