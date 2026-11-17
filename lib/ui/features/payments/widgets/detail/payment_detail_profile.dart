import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_gateway.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/custom_field_detail_rows.dart';
import 'package:admin/ui/core/detail/record_details_cards.dart';
import 'package:admin/ui/core/detail/record_profile_layout.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/widgets/clamped_text.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/core/widgets/watch_builder.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/projects/widgets/project_name_label.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/utils/notes_html.dart';
import 'package:admin/domain/payment_types.dart';

/// A payment's reference fields — how and when it was paid, where it came
/// from, the user's own note. Always shown, between the comments card and the
/// tabs.
///
/// The screen it replaces showed none of this: the type, the date, the
/// transaction reference and the note could only be read by opening the
/// payment for editing.
///
/// **Two cards, side by side and level on a wide window**
/// (`RecordProfileLayout`): Details — what the payment is (number, date, type,
/// reference, gateway, conversion) — and Additional Info — what is kept
/// about it (project, assigned user, custom fields, created, updated). It was
/// one full-width card running its rows in two columns, which read as one
/// card with the dates floating in its right half. Below the breakpoint they
/// stack; when only one half has rows it is a single Details card
/// (`recordDetailsCards`). The note stays full width beneath.
///
/// **Each card is gated on having content**, derived from the rows it draws,
/// so a card that would be a title over nothing is not given a gap.
class PaymentDetailProfile extends StatelessWidget {
  const PaymentDetailProfile({
    super.key,
    required this.payment,
    required this.company,
    this.formatter,
  });

  final Payment payment;

  /// For the custom-field labels. Null while the company row is loading.
  final Company? company;
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    // The gateway's name is a stream (the payment carries only its id), and
    // whether there is a Gateway row decides which cards there are — so it
    // is resolved here, once, and handed to the rows.
    if (payment.companyGatewayId.isEmpty) return _build(context, '');
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    return WatchBuilder<CompanyGateway?>(
      cacheKey: (companyId, payment.companyGatewayId),
      create: () => services.companyGateways.watch(
        companyId: companyId,
        id: payment.companyGatewayId,
      ),
      builder: (context, snapshot) {
        final gateway = snapshot.data;
        // Company gateway → `gatewayKey` → the statics `Gateway.name`,
        // falling back to the gateway's own label (the refund screen's
        // lookup). Never the raw id: an unresolved gateway is no row.
        final staticName =
            services.statics.gateways[gateway?.gatewayKey]?.name ?? '';
        return _build(
          context,
          staticName.isNotEmpty ? staticName : (gateway?.label ?? ''),
        );
      },
    );
  }

  Widget _build(BuildContext context, String gatewayName) {
    return RecordProfileLayout(
      lead: recordDetailsCards(
        context,
        facts: PaymentDetailRows.facts(
          context,
          payment,
          formatter: formatter,
          gatewayName: gatewayName,
        ),
        bookkeeping: PaymentDetailRows.bookkeeping(
          context,
          payment,
          company,
          formatter: formatter,
        ),
      ),
      tail: [
        if (PaymentDetailNotesCard.hasContent(payment))
          PaymentDetailNotesCard(payment: payment),
      ],
    );
  }
}

/// The payment record's label / value rows, in display order. Blank rows are
/// left out.
abstract final class PaymentDetailRows {
  /// What the payment is — number, date, type, reference, gateway,
  /// conversion. The Details card.
  static List<Widget> facts(
    BuildContext context,
    Payment payment, {
    Formatter? formatter,
    String gatewayName = '',
  }) {
    final p = payment;
    final f = formatter;
    final statics = context.read<Services>().statics;
    final type = p.typeId.isEmpty
        ? ''
        : paymentTypeLabel(
            Localization.of(context),
            p.typeId,
            statics.paymentType(p.typeId)?.name ?? '',
          );
    final date = p.date;
    // A conversion is worth a row only when there is one: a foreign currency
    // named, and a rate that is not the identity (0 is the legacy "none").
    final converted =
        p.exchangeCurrencyId.isNotEmpty &&
        p.exchangeCurrencyId != p.currencyId &&
        p.effectiveExchangeRate != Decimal.one;
    return [
      if (p.number.isNotEmpty)
        DetailInfoRow(label: context.tr('number'), value: p.number),
      if (date != null && f != null)
        DetailInfoRow(
          label: context.tr('payment_date'),
          value: f.date(date.toIso()),
          copyable: false,
        ),
      if (type.isNotEmpty)
        DetailInfoRow(
          label: context.tr('payment_type'),
          value: type,
          copyable: false,
        ),
      if (p.transactionReference.isNotEmpty)
        DetailInfoRow(
          label: context.tr('transaction_reference'),
          value: p.transactionReference,
        ),
      // Assigned by the processor and never user-editable; here for
      // reference.
      if (gatewayName.isNotEmpty)
        DetailInfoRow(
          label: context.tr('gateway'),
          value: gatewayName,
          copyable: false,
        ),
      if (converted) ...[
        DetailInfoRow(
          label: context.tr('exchange_rate'),
          value:
              f?.decimal(p.exchangeRate.toDouble(), maxDecimals: 6) ??
              p.exchangeRate.toString(),
          copyable: false,
        ),
        if (f != null)
          DetailInfoRow(
            label: context.tr('converted_amount'),
            value: f.money(
              p.amount * p.effectiveExchangeRate,
              currencyId: p.exchangeCurrencyId,
            ),
            copyable: false,
          ),
      ],
    ];
  }

  /// What is kept about the payment — the project it is filed under, who it
  /// is assigned to, the custom fields, created and updated. The Additional
  /// Info card. Created / updated are left out on a phone, where
  /// `RecordTimestampsLine` says them.
  static List<Widget> bookkeeping(
    BuildContext context,
    Payment payment,
    Company? company, {
    Formatter? formatter,
  }) {
    final p = payment;
    return [
      if (p.projectId.isNotEmpty)
        DetailInfoRow(
          label: context.tr('project'),
          value: '',
          copyable: false,
          child: ProjectNameLabel(
            projectId: p.projectId,
            style: _valueStyle(context),
          ),
        ),
      if (p.assignedUserId.isNotEmpty)
        DetailInfoRow(
          label: context.tr('assigned_user'),
          value: '',
          copyable: false,
          child: UserNameLabel(
            userId: p.assignedUserId,
            style: _valueStyle(context),
          ),
        ),
      ..._customRows(context, p, company),
      ...recordTimestampRows(
        context,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
        formatter: formatter,
      ),
    ];
  }

  /// The value style `DetailInfoRow` gives a string, for a row whose value is
  /// a widget and so does not get it.
  static TextStyle? _valueStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.inTheme.ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      );

  static List<Widget> _customRows(
    BuildContext context,
    Payment p,
    Company? company,
  ) {
    final values = [
      p.customValue1,
      p.customValue2,
      p.customValue3,
      p.customValue4,
    ];
    if (company == null || values.every((v) => v.isEmpty)) return const [];
    final services = context.read<Services>();
    final rows = customFieldDetailRows(
      company: company,
      prefix: 'payment',
      values: values,
      formatter: services.formatterIfReady(
        services.auth.session.value?.currentCompanyId ?? '',
      ),
      yes: context.tr('yes'),
      no: context.tr('no'),
    );
    return [
      for (final r in rows) DetailInfoRow(label: r.label, value: r.value),
    ];
  }
}

/// The user's private note on the payment. Hidden when there are no words in
/// it — the field is free text, and markup that renders as nothing must not
/// open a card.
class PaymentDetailNotesCard extends StatelessWidget {
  const PaymentDetailNotesCard({super.key, required this.payment});

  final Payment payment;

  static bool hasContent(Payment payment) =>
      plainTextFromHtml(payment.privateNotes).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final notes = plainTextFromHtml(payment.privateNotes);
    if (notes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    return DashboardCardShell(
      title: context.tr('private_notes'),
      // A note has no length limit; unclamped, one long one decides where
      // everything below this card starts.
      child: ClampedText(
        text: notes,
        maxLines: 6,
        style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink),
      ),
    );
  }
}
