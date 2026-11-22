import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/domain/upgrade/client_limit.dart';
import 'package:admin/domain/upgrade/client_usage.dart';
import 'package:admin/domain/upgrade/upgrade_launcher.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/widgets/link_text.dart';
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

/// The sentence for an account at or over its Free plan cap: "The Free plan
/// includes 5 clients. Upgrade to add more.", or, for an account holding more
/// than the cap (a plan or trial that lapsed), one that says those are kept —
/// never "11 of 5", never a negative count.
String clientLimitReachedMessage(
  BuildContext context, {
  required int limit,
  int? used,
}) {
  if (used != null && used > limit) {
    return context.tr('free_plan_clients_over', {
      'count': formatClientCount(context, used),
      'limit': formatClientCount(context, limit),
    });
  }
  return context.tr('free_plan_client_limit_reached', {
    'count': formatClientCount(context, limit),
  });
}

/// The quota as the usage line words it: "3 of 5 free clients used", or for
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
  unawaited(
    showClientLimitDialog(context, limit: quota.limit, used: quota.used),
  );
  return true;
}

/// "The Free plan includes 5 clients. Upgrade to add more." with Upgrade and
/// Cancel. Upgrade goes through [launchUpgrade], the one entry point that
/// knows which store, portal or Plan screen this build may open.
Future<void> showClientLimitDialog(
  BuildContext context, {
  required int limit,
  int? used,
}) async {
  final upgrade = await showDialog<bool>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    builder: (dialogContext) => ClientLimitDialog(limit: limit, used: used),
  );
  if (upgrade == true && context.mounted) await launchUpgrade(context);
}

/// The at-limit dialog's body, public for its widget test.
class ClientLimitDialog extends StatelessWidget {
  const ClientLimitDialog({required this.limit, this.used, super.key});

  final int limit;
  final int? used;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return AlertDialog(
      title: Text(context.tr('client_limit')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(clientLimitReachedMessage(context, limit: limit, used: used)),
            const SizedBox(height: InSpacing.sm),
            Text(
              context.tr('free_plan_clients_count_note'),
              style: TextStyle(color: tokens.ink2, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        PrimaryDialogAction(
          buttonKey: const ValueKey('client_limit_upgrade'),
          label: context.tr('upgrade'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// The quiet usage line above the Clients list on a hosted Free plan: "3 of 5
/// free clients used · Upgrade". Draws nothing for any other account, or
/// while the count is unknown (unknown is never zero). Opening the list asks
/// for a count older than [kClientUsageMaxAge].
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
        if (quota == null) return const SizedBox.shrink();
        final tokens = context.inTheme;
        final full = quota.blocksNewClient;
        final style = TextStyle(
          color: full ? tokens.ink : tokens.ink2,
          fontSize: 13,
        );
        final message = clientUsageMessage(context, quota);
        return Semantics(
          container: true,
          label: message,
          child: Container(
            key: const ValueKey('client_usage_banner'),
            width: double.infinity,
            decoration: BoxDecoration(
              color: full ? tokens.accentSoft : null,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: InSpacing.lg(context),
              vertical: InSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: tokens.ink3),
                const SizedBox(width: InSpacing.sm),
                Flexible(
                  child: ExcludeSemantics(child: Text(message, style: style)),
                ),
                Text(' · ', style: TextStyle(color: tokens.ink3, fontSize: 13)),
                LinkText(
                  label: context.tr('upgrade'),
                  style: style,
                  color: tokens.accentInk,
                  onTap: () => unawaited(launchUpgrade(context)),
                ),
              ],
            ),
          ),
        );
      },
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
        final atLimit = vm.isCreate && (quota?.blocksNewClient ?? false);
        if (!rejected && !atLimit) return const SizedBox.shrink();
        final limit =
            quota?.limit ??
            usage?.limit ??
            context.read<Services?>()?.auth.session.value?.hostedClientCount ??
            0;
        final tokens = context.inTheme;
        final message = limit > 0
            ? clientLimitReachedMessage(
                context,
                limit: limit,
                used: quota?.used,
              )
            : context.tr('client_limit');
        return Material(
          key: const ValueKey('client_limit_form_banner'),
          color: tokens.accentSoft,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: InSpacing.lg(context),
              vertical: InSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: tokens.accentInk,
                  ),
                ),
                const SizedBox(width: InSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: tokens.ink, fontSize: 13),
                  ),
                ),
                const SizedBox(width: InSpacing.sm),
                TextButton(
                  key: const ValueKey('client_limit_form_upgrade'),
                  onPressed: () => unawaited(launchUpgrade(context)),
                  child: Text(context.tr('upgrade')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
