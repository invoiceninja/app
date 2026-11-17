import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company_gateway.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/payment_types.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/gateways/gateway_order_writer.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/no_gateway_warning.dart'
    show kAddGatewayRoute;
import 'package:admin/ui/features/settings/widgets/settings_nav_row.dart';

/// Where the gateways list lives. At group / client scope the same route
/// renders the gateway display-order screen (`CompanyGatewayListScreen`).
const String kCompanyGatewaysRoute = '/settings/company_gateways';
const String kPaymentTypesRoute = '/settings/online_payments/payment_types';

/// The first card on Settings → Payment Settings: how clients pay, at a
/// glance, and the way to change it — the company's gateways and its payment
/// types, each a [SettingsNavRow] with what is set up now.
///
/// The gateways row is also the page's "no gateway" warning (amber, titled
/// Add Payment Gateway, straight to the add screen), so the page carries no
/// separate `NoGatewayWarning` banner and no second "Add" target.
///
/// At group / client scope only the gateways row shows, as the gateway
/// display order for that scope — payment types are the company's — and it
/// never warns: the scope has no gateways of its own to be missing.
///
/// Everything is read from Drift and the live draft; nothing fetches.
/// `docs/settings-screens.md` § Payment Settings opens with a setup card of
/// two navigation rows.
class PaymentSetupCard extends StatefulWidget {
  const PaymentSetupCard({super.key});

  @override
  State<PaymentSetupCard> createState() => _PaymentSetupCardState();
}

class _PaymentSetupCardState extends State<PaymentSetupCard> {
  Stream<List<CompanyGateway>>? _gateways;
  String? _companyId;

  /// The scope's gateway order (a CSV of ids), once resolved. Until then
  /// the names read in Drift's order.
  List<String> _order = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    if (companyId == _companyId) return;
    _companyId = companyId;
    // Made once per company, outside build: a fresh stream per build would
    // restart the query and drop the card back to its pending state.
    _gateways = companyId.isEmpty
        ? null
        : services.companyGateways.watchPage(
            companyId: companyId,
            states: const {EntityState.active},
          );
    final scope = context.read<SettingsLevelController?>();
    if (scope != null) unawaited(_resolveOrder(services, scope));
  }

  Future<void> _resolveOrder(
    Services services,
    SettingsLevelController scope,
  ) async {
    try {
      final resolved = await resolveGatewayOrder(services, scope);
      if (!mounted) return;
      setState(
        () => _order = resolved.csv
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(growable: false),
      );
    } catch (_) {
      // The order only sorts the names; Drift's order is a fine fallback.
    }
  }

  List<CompanyGateway> _ordered(List<CompanyGateway> rows) {
    if (_order.isEmpty) return rows;
    final byId = {for (final g in rows) g.id: g};
    return [
      for (final id in _order)
        if (byId.containsKey(id)) byId.remove(id)!,
      ...byId.values,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final statics = context.read<Services>().statics;
    return StreamBuilder<List<CompanyGateway>>(
      stream: _gateways,
      builder: (context, snap) {
        final rows = snap.data == null ? null : _ordered(snap.data!);
        return PaymentSetupSection(
          gatewayNames: rows == null
              ? null
              : [
                  for (final g in rows)
                    g.resolveDisplayName(
                      gatewayName: statics.gateway(g.gatewayKey)?.name,
                    ),
                ],
          paymentTypeIds: statics.paymentTypes.keys,
        );
      },
    );
  }
}

/// What [PaymentSetupCard] draws, from data already gathered: the active
/// gateways' display names in the scope's order (null until Drift first
/// answers) and the statics catalog's payment-type ids. The scope and the
/// live draft (hidden payment types) come off Provider.
class PaymentSetupSection extends StatelessWidget {
  const PaymentSetupSection({
    super.key,
    required this.gatewayNames,
    required this.paymentTypeIds,
  });

  final List<String>? gatewayNames;
  final Iterable<String> paymentTypeIds;

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<SettingsLevelController?>();
    final isCompany = scope == null || scope.isCompany;
    return FormSection(
      title: null,
      spacing: InSpacing.xs,
      children: [
        _gatewaysRow(context, isCompany: isCompany),
        // Which types the pickers offer and what they are called is the
        // company's, with no per-group or per-client value.
        if (isCompany) _PaymentTypesRow(ids: paymentTypeIds),
      ],
    );
  }

  Widget _gatewaysRow(BuildContext context, {required bool isCompany}) {
    void open() => context.go(kCompanyGatewaysRoute);
    final title = context.tr(
      isCompany ? 'company_gateways' : 'gateway_display_order',
    );
    final names = gatewayNames;
    // Not answered yet: the title over a blank line, never the warning.
    if (names == null) {
      return SettingsNavRow(
        icon: Icons.account_balance_wallet_outlined,
        title: title,
        statusPending: true,
        onTap: open,
      );
    }
    if (names.isEmpty) {
      if (!isCompany) {
        return SettingsNavRow(
          icon: Icons.account_balance_wallet_outlined,
          title: title,
          status: context.tr('no_gateways_for_reorder_subtitle'),
          onTap: open,
        );
      }
      return SettingsNavRow(
        icon: Icons.warning_amber_rounded,
        title: context.tr('add_gateway'),
        status: context.tr('no_gateway_connected'),
        warning: true,
        onTap: () => context.go(kAddGatewayRoute),
      );
    }
    return SettingsNavRow(
      icon: Icons.account_balance_wallet_outlined,
      title: title,
      status: names.join(' · '),
      count: names.length,
      onTap: open,
    );
  }
}

/// "Payment Types — 12 of 14 shown", from the statics catalog and the live
/// draft's `hidden_payment_types`, so hiding one on its page (or discarding
/// that) shows here at once.
class _PaymentTypesRow extends StatelessWidget {
  const _PaymentTypesRow({required this.ids});

  final Iterable<String> ids;

  @override
  Widget build(BuildContext context) {
    final host = context.watch<SettingsDraftHost>();
    final hidden = parseHiddenPaymentTypes(host.settings.hiddenPaymentTypes);
    final total = ids.length;
    final shown = ids.where((id) => !hidden.contains(id)).length;
    return SettingsNavRow(
      icon: Icons.credit_card_outlined,
      title: context.tr('payment_types'),
      // No catalog yet (a cold start offline): no status, rather than "0 of 0".
      status: total == 0
          ? null
          : context.tr('payment_types_shown_count', {
              'count': '$shown',
              'total': '$total',
            }),
      onTap: () => context.go(kPaymentTypesRoute),
    );
  }
}
