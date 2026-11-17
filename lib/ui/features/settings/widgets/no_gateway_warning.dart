import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/link_text.dart';

/// Where a new gateway is created — the same target as the dashboard setup
/// checklist's "Connect a gateway" row.
const String kAddGatewayRoute = '/settings/company_gateways/new';

/// Visual variant: [inset] sits in a settings body above the first card;
/// [stripe] is the edge-to-edge bar an entity list draws under its toolbar
/// (Payment Links), next to `PlanGateBanner(style: stripe)`.
enum NoGatewayWarningStyle { inset, stripe }

/// Says the company has no payment gateway, with a way to add one.
///
/// The predicate is the dashboard setup checklist's (`hasGateway` in
/// `SetupChecklistViewModel`): the active, non-deleted `company_gateways`
/// rows in Drift. Gateways are bundled with `/refresh`, so the count is
/// complete without a fetch. Nothing is drawn until the stream has answered
/// — a warning must never flash on open for a company that has gateways.
class NoGatewayWarning extends StatefulWidget {
  const NoGatewayWarning({
    required this.messageKey,
    this.style = NoGatewayWarningStyle.inset,
    this.countStream,
    super.key,
  });

  /// The sentence — each surface says what the missing gateway costs it.
  final String messageKey;

  final NoGatewayWarningStyle style;

  /// Test seam; defaults to the company's active-gateway count.
  final Stream<int>? countStream;

  @override
  State<NoGatewayWarning> createState() => _NoGatewayWarningState();
}

class _NoGatewayWarningState extends State<NoGatewayWarning> {
  // Hoisted out of build: a Drift watch re-subscribed per build replays.
  Stream<int>? _count;
  String? _companyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.countStream != null) {
      _count ??= widget.countStream;
      return;
    }
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    if (companyId == _companyId && _count != null) return;
    _companyId = companyId;
    _count = companyId.isEmpty
        ? null
        : services.db.companyGatewayDao.watchActiveCount(companyId: companyId);
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    if (count == null) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: count,
      builder: (context, snap) {
        final n = snap.data;
        if (n == null || n > 0) return const SizedBox.shrink();
        return widget.style == NoGatewayWarningStyle.inset
            ? _Inset(messageKey: widget.messageKey)
            : _Stripe(messageKey: widget.messageKey);
      },
    );
  }
}

void _addGateway(BuildContext context) => context.go(kAddGatewayRoute);

class _Inset extends StatelessWidget {
  const _Inset({required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: InSpacing.lg(context)),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.warningSoft,
          borderRadius: BorderRadius.circular(InRadii.r3),
          border: Border.all(color: tokens.border),
        ),
        padding: EdgeInsets.all(InSpacing.lg(context)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final message = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: tokens.warning),
                const SizedBox(width: InSpacing.sm),
                Expanded(
                  child: Text(
                    context.tr(messageKey),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.ink,
                    ),
                  ),
                ),
              ],
            );
            // Outlined, like the plan-gate banner's action: the page's Save
            // is its one filled button.
            final action = OutlinedButton(
              onPressed: () => _addGateway(context),
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
              child: Text(context.tr('add_gateway')),
            );
            // The action under the sentence where a row would squeeze the
            // sentence into a sliver (a phone, a long translation).
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  message,
                  SizedBox(height: InSpacing.md(context)),
                  action,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: message),
                SizedBox(width: InSpacing.md(context)),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stripe extends StatelessWidget {
  const _Stripe({required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: tokens.ink);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.warningSoft,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: InSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warning),
          const SizedBox(width: InSpacing.sm),
          Expanded(child: Text(context.tr(messageKey), style: bodyStyle)),
          SizedBox(width: InSpacing.md(context)),
          LinkText(
            label: context.tr('add_gateway'),
            style: bodyStyle,
            color: tokens.accent,
            onTap: () => _addGateway(context),
          ),
        ],
      ),
    );
  }
}
