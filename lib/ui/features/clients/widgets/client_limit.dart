import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/domain/upgrade/client_limit.dart';
import 'package:admin/domain/upgrade/client_usage.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';

/// The route every blank "New client" opens.
const String kNewClientRoute = '/clients/new';

/// A count as the active company formats integers, or plain digits before its
/// formatter has loaded.
String formatClientCount(BuildContext context, int n) {
  final services = context.read<Services?>();
  final companyId = services?.auth.session.value?.currentCompanyId;
  final fmt = companyId == null ? null : services!.formatterIfReady(companyId);
  return fmt?.integer(n) ?? '$n';
}

/// The sentence for an account at or over its Free plan cap: "You have used
/// all 5 clients on the Free plan. Upgrade to add more." (on the new-client
/// form, "…Upgrade to save this client.", [onForm]), or, for an account
/// holding more than the cap (a plan or trial that lapsed), one that says
/// those are kept — never "11 of 5", never a negative count.
///
/// On a store build whose hosted service sells nothing to the account
/// ([purchasesWithheld]) the same sentences stop before "Upgrade …": the
/// limit is still said plainly, with nothing to buy.
String clientLimitReachedMessage(
  BuildContext context, {
  required int limit,
  int? used,
  bool onForm = false,
}) {
  final withheld = purchasesWithheld(context, listen: false);
  if (used != null && used > limit) {
    return context.tr(
      withheld ? 'free_plan_clients_over_info' : 'free_plan_clients_over',
      {
        'count': formatClientCount(context, used),
        'limit': formatClientCount(context, limit),
      },
    );
  }
  // Withheld, the form says the same as everywhere else: the limit.
  final key = withheld
      ? 'free_plan_client_limit_reached_info'
      : onForm
      ? 'free_plan_client_limit_form'
      : 'free_plan_client_limit_reached';
  return context.tr(key, {'count': formatClientCount(context, limit)});
}

/// The Free plan's client limit in our own words, for where the server's
/// `limit_clients` message would otherwise be shown: "You have used all 5
/// clients on the Free plan." when the cap is known, else "You have reached
/// the Free plan's client limit.".
String neutralClientLimitMessage(BuildContext context) {
  final limit =
      context.read<ClientUsage?>()?.limit ??
      freePlanClientLimit(context.read<Services?>()?.auth.session.value);
  if (limit != null && limit > 0) {
    return context.tr('free_plan_client_limit_reached_info', {
      'count': formatClientCount(context, limit),
    });
  }
  return context.tr('free_plan_client_limit_hit');
}

/// A client save's field errors as a screen may show them. On a store build
/// whose hosted service sells nothing to the account ([purchasesWithheld])
/// no server text about the plan reaches the screen: the Free plan's refusal
/// (`limit_clients`, under `id`, [isClientLimitRejection]) becomes
/// [neutralClientLimitMessage]. Anywhere else [errors] come back as they are.
Map<String, List<String>> presentClientFieldErrors(
  BuildContext context,
  Map<String, List<String>> errors,
) {
  if (!isClientLimitRejection(errors)) return errors;
  if (!purchasesWithheld(context, listen: false)) return errors;
  return {
    ...errors,
    'id': [neutralClientLimitMessage(context)],
  };
}

/// The quota as the usage line words it: "3 of 5 clients on the Free plan", or
/// for
/// an account over the cap "You have 11 clients. The Free plan allows 5."
String clientUsageMessage(BuildContext context, ClientQuota quota) {
  if (quota.state == ClientQuotaState.overLimit) {
    return context.tr('free_plan_clients_over_short', {
      'count': formatClientCount(context, quota.used),
      'limit': formatClientCount(context, quota.limit),
    });
  }
  return context.tr('free_plan_clients_used', {
    'used': formatClientCount(context, quota.used),
    'limit': formatClientCount(context, quota.limit),
  });
}

/// Whether a New client must stop at the Free plan's cap — and if so, the
/// dialog that says so is already on its way. Every blank-create path calls it
/// before it navigates (`goToCreateRoute`, the list's New button, the create
/// shortcut, Clone, the pickers' inline create); a backstop banner on the
/// create form covers any other way in ([ClientLimitFormBanner]).
///
/// Reads the count held by [ClientUsage] — no request, so the tap stays
/// instant. An unknown count (offline before the first answer, no
/// `ClientUsage` provided) lets the create through, as before: the server's
/// 422 is still behind it, and its message carries the same Upgrade.
bool interceptNewClientAtLimit(BuildContext context) {
  final usage = context.read<ClientUsage?>();
  final quota = usage?.quota;
  if (quota == null || !quota.blocksNewClient) return false;
  // A count held a while may be stale high (a client purged on the web): ask
  // again, so the next tap goes by the server's number.
  unawaited(usage!.refresh(maxAge: kClientUsageBlockedMaxAge));
  unawaited(
    showClientLimitDialog(context, limit: quota.limit, used: quota.used),
  );
  return true;
}

/// The client form's save gate: a save that creates a client, at the cap,
/// opens the Upgrade dialog and is not sent — the form keeps what was typed.
/// Covers every way onto a blank form that skipped [interceptNewClientAtLimit]
/// (a deep link, the command palette, a restored draft) and the Retry of a
/// create the server refused for the cap. An edit is never stopped.
Future<bool> confirmNewClientSave(
  BuildContext context,
  GenericEditViewModel<dynamic> vm,
) async => !(vm.savesAsCreate && interceptNewClientAtLimit(context));

/// Shows the Upgrade dialog when [error] is an import the server refused for
/// the Free plan's client cap, and says whether it did. The server's message
/// ("You've hit the 5 client limit…") is wrong for a file that would only
/// pass the cap, and a toast offered no way on, so the import gets its own
/// words and the same Upgrade as everywhere else (docs/free-plan-limits.md).
bool showImportClientLimit(BuildContext context, Object error) {
  if (error is! ValidationException) return false;
  if (!isClientImportLimitRejection(error.fieldErrors)) return false;
  final services = context.read<Services?>();
  final usage = context.read<ClientUsage?>();
  final limit =
      usage?.limit ?? freePlanClientLimit(services?.auth.session.value);
  if (limit == null) return false;
  // The import ran into the cap, so the number held may be behind.
  unawaited(usage?.refresh());
  unawaited(
    showClientLimitDialog(
      context,
      limit: limit,
      detail: context.tr(
        purchasesWithheld(context, listen: false)
            ? 'free_plan_import_too_many_info'
            : 'free_plan_import_too_many',
        {'count': formatClientCount(context, limit)},
      ),
    ),
  );
  return true;
}

/// "You have used all 5 clients on the Free plan. Upgrade to add more." with
/// Upgrade and Close (nothing is cancelled: the form never opened). Upgrade
/// goes through [launchUpgrade], the one entry point that
/// knows which store, portal or Plan screen this build may open. On a store
/// build whose hosted service sells nothing to the account
/// ([purchasesWithheld]) it is "You have used all 5 clients on the Free
/// plan." with Close only.
///
/// [detail], when given, is said instead of the sentence built from [limit]
/// and [used]: the server's own `limit_clients` message for a refusal whose
/// cap the app does not know, or the import's wording.
Future<void> showClientLimitDialog(
  BuildContext context, {
  int? limit,
  int? used,
  String? detail,
}) async {
  final upgrade = await showDialog<bool>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    builder: (dialogContext) =>
        ClientLimitDialog(limit: limit, used: used, detail: detail),
  );
  if (upgrade == true && context.mounted) await launchUpgrade(context);
}

/// The at-limit dialog's body, public for its widget test.
class ClientLimitDialog extends StatelessWidget {
  const ClientLimitDialog({this.limit, this.used, this.detail, super.key});

  final int? limit;
  final int? used;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final withheld = purchasesWithheld(context);
    return AlertDialog(
      title: Text(context.tr('client_limit')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail ??
                  (limit == null
                      ? (withheld
                            ? context.tr('free_plan_client_limit_hit')
                            : context.tr('client_limit'))
                      : clientLimitReachedMessage(
                          context,
                          limit: limit!,
                          used: used,
                        )),
            ),
            const SizedBox(height: InSpacing.sm),
            Text(
              context.tr('free_plan_clients_count_note'),
              style: TextStyle(color: tokens.ink2, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        // Nothing to buy here: Close is the one action, and Enter takes it.
        if (withheld)
          PrimaryDialogAction(
            buttonKey: const ValueKey('client_limit_close'),
            label: context.tr('close'),
            onPressed: () => Navigator.of(context).pop(false),
          )
        else ...[
          TextButton(
            key: const ValueKey('client_limit_close'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('close')),
          ),
          PrimaryDialogAction(
            buttonKey: const ValueKey('client_limit_upgrade'),
            label: context.tr('upgrade'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ],
    );
  }
}

/// How many places from the cap the clients list starts showing its usage
/// line. Further off, the signup line, the first-run checklist and the Plan
/// screen have said it; a line on every visit to the list would be clutter.
const int kClientUsageLineFromRemaining = 2;

/// The quiet usage line above the Clients list on a hosted Free plan, once
/// the cap is near: "3 of 5 clients on the Free plan", Upgrade at its end.
/// Draws nothing for any other account, further from the cap, or while the
/// count is unknown (unknown is never zero). Opening the list asks for a
/// count older than [kClientUsageMaxAge].
class ClientUsageBanner extends StatefulWidget {
  const ClientUsageBanner({super.key});

  @override
  State<ClientUsageBanner> createState() => _ClientUsageBannerState();
}

class _ClientUsageBannerState extends State<ClientUsageBanner> {
  ClientUsage? _usage;

  @override
  void initState() {
    super.initState();
    _usage = context.read<ClientUsage?>();
    unawaited(_usage?.refresh(maxAge: kClientUsageMaxAge));
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    if (usage == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final quota = usage.quota;
        if (quota == null ||
            quota.limit - quota.used > kClientUsageLineFromRemaining) {
          return const SizedBox.shrink();
        }
        final tokens = context.inTheme;
        final full = quota.blocksNewClient;
        final message = clientUsageMessage(context, quota);
        return Container(
          key: const ValueKey('client_usage_banner'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: full ? tokens.accentSoft : null,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          padding: EdgeInsetsDirectional.only(
            start: InSpacing.lg(context),
            end: InSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.people_outline, size: 16, color: tokens.ink3),
              const SizedBox(width: InSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: InSpacing.xs),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: full ? tokens.ink : tokens.ink2,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              // Nothing to buy on a store build that sells nothing here.
              if (!purchasesWithheld(context)) ...[
                const SizedBox(width: InSpacing.sm),
                _UpgradeButton(
                  buttonKey: const ValueKey('client_usage_upgrade'),
                ),
              ] else
                const SizedBox(width: InSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

/// Upgrade as a text button in accent ink, a full touch target on touch and
/// compact elsewhere — the usage line's and the form notice's.
class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({required this.buttonKey});

  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final touch = Env.isTouchPrimary;
    return TextButton(
      key: buttonKey,
      style: TextButton.styleFrom(
        foregroundColor: context.inTheme.accentInk,
        minimumSize: Size(48, touch ? 44 : 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: InSpacing.sm),
      ),
      onPressed: () => unawaited(launchUpgrade(context)),
      child: Text(context.tr('upgrade')),
    );
  }
}

/// The new-client form's Free plan notice: shown when the form is a create and
/// the account is at its cap (a way in that skipped
/// [interceptNewClientAtLimit] — a deep link, the command palette), or when the
/// server refused a save for the cap (`limit_clients`, [isClientLimitRejection])
/// — an offline create that reached it is the case that used to end as a bare
/// dead row. Says what happened and offers Upgrade; the rejection banner above
/// keeps Retry and Discard.
class ClientLimitFormBanner extends StatelessWidget {
  const ClientLimitFormBanner({required this.vm, super.key});

  final GenericEditViewModel<dynamic> vm;

  @override
  Widget build(BuildContext context) {
    final usage = context.read<ClientUsage?>();
    return ListenableBuilder(
      listenable: Listenable.merge([vm, if (usage != null) usage]),
      builder: (context, _) {
        final rejected = isClientLimitRejection(vm.fieldErrors);
        final quota = usage?.quota;
        // Not on the form's own save: its create is queued (and counted)
        // before the form leaves, so the fifth client would read as the cap
        // reached on the very form that added it.
        final atLimit =
            vm.isCreate &&
            !vm.isSaving &&
            vm.lastSentDraft == null &&
            (quota?.blocksNewClient ?? false);
        if (!rejected && !atLimit) return const SizedBox.shrink();
        final limit =
            quota?.limit ??
            usage?.limit ??
            context.read<Services?>()?.auth.session.value?.hostedClientCount ??
            0;
        final tokens = context.inTheme;
        // A cap the app does not know (an account row without
        // `hosted_client_count`): the server's own words.
        final serverText = (vm.fieldErrors['id'] ?? const <String>[])
            .map((m) => m.trim())
            .firstWhere((m) => m.isNotEmpty, orElse: () => '');
        final message = limit > 0
            ? clientLimitReachedMessage(
                context,
                limit: limit,
                used: quota?.used,
                onForm: true,
              )
            // Never the server's words where purchases are withheld: they
            // may ask the user to upgrade.
            : purchasesWithheld(context)
            ? neutralClientLimitMessage(context)
            : serverText.isNotEmpty
            ? serverText
            : context.tr('client_limit');
        return Material(
          key: const ValueKey('client_limit_form_banner'),
          color: tokens.accentSoft,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: InSpacing.lg(context),
              end: InSpacing.sm,
              top: InSpacing.xs,
              bottom: InSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: tokens.accentInk),
                const SizedBox(width: InSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: InSpacing.xs),
                    child: Text(
                      message,
                      style: TextStyle(color: tokens.ink, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: InSpacing.sm),
                if (!purchasesWithheld(context))
                  const _UpgradeButton(
                    buttonKey: ValueKey('client_limit_form_upgrade'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
