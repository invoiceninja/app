import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/custom_field_types.dart';
import 'package:admin/domain/billing/totals_calculator.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

/// Read-only totals breakdown card. Drives the sticky-bottom footer on
/// every billing-doc edit screen (Invoice / Quote / Credit / PO /
/// RecurringInvoice) and the totals card on the detail screen.
///
/// Inputs are pure value types — no entity coupling. The host computes a
/// [BillingTotalsResult] via [computeTotals] and feeds it here alongside
/// the four custom-surcharge labels + values (which aren't in the totals
/// struct because they're invoice-level inputs, not derived). Money
/// rendering uses a basic [NumberFormat] today; when the formatter
/// pipeline reaches the shared layer the widget will switch to
/// `Formatter.money(...)` per CLAUDE.md.
class TotalsWidget extends StatelessWidget {
  TotalsWidget({
    super.key,
    required this.totals,
    Decimal? discount,
    this.discountIsAmount = false,
    this.surcharges = const <TotalsSurcharge>[],
    Decimal? partial,
    this.balance,
    this.paidToDate,
    this.balanceLabelKey = 'balance',
    this.paidToDateLabelKey = 'paid_to_date',
    this.leadBalance = false,
    this.editor,
    this.padded = true,
    this.dense = false,
    this.slim = false,
    this.bordered = true,
    this.formatter,
    this.currencyId,
  }) : discount = discount ?? Decimal.zero,
       partial = partial ?? Decimal.zero;

  /// The computed result from `computeTotals(...)`.
  final BillingTotalsResult totals;

  /// Invoice-level discount value as the user entered it (raw — % or
  /// amount, the widget renders both flavors).
  final Decimal discount;
  final bool discountIsAmount;

  /// Up to four invoice-level surcharges with display labels. Pass the
  /// company's custom surcharge labels (e.g. `[(label: 'Shipping',
  /// amount: 12.00), …]`). Zero-amount entries are hidden.
  final List<TotalsSurcharge> surcharges;

  /// Partial-payment amount (if the invoice supports staged payment).
  /// Zero hides the row.
  final Decimal partial;

  /// Balance after paid-to-date. When null the widget shows just the
  /// computed total (useful for new-invoice drafts where balance =
  /// total by definition).
  final Decimal? balance;
  final Decimal? paidToDate;

  /// What the [balance] and [paidToDate] rows are called — `balance_due` /
  /// `paid_to_date` on an invoice, `credit_remaining` / `applied` on a credit
  /// (`BillingDocType.balanceLabelKey` / `settledLabelKey`).
  final String balanceLabelKey;
  final String paidToDateLabelKey;

  /// The balance is the figure that leads (the edit form's totals card,
  /// while the document is open): drawn even when it equals the total, last
  /// and larger. Ignored in [dense].
  final bool leadBalance;

  /// Inputs drawn inside the breakdown, after its rows and before the rule
  /// over the total — the edit form's document taxes, inclusive-tax switch
  /// and surcharges, so the card that sums them is where they are set.
  /// Ignored in [slim].
  final Widget? editor;

  /// With [bordered] false: the plain row list pads itself. False when the
  /// host is already a padded card.
  final bool padded;

  /// Compact mode: smaller padding + 13 px text. Used in the edit-screen
  /// sticky-bottom footer. Default false renders the larger detail-screen
  /// variant.
  final bool dense;

  /// Slim mode: render only the grand-total row (plus balance when it
  /// differs from total). Used by the always-visible bottom bar on the
  /// desktop edit screen, where the full breakdown lives in a separate
  /// card. Implies a flat dense strip; ignored unless [dense] is true.
  final bool slim;

  /// When false (non-dense only), render the rows as a plain padded
  /// list with no border / shadow / radius — matches the React + old
  /// Flutter references where the totals are a borderless row list.
  /// Default true keeps the bordered detail-screen card.
  final bool bordered;

  /// When provided, money rows render via `Formatter.money` (currency symbol,
  /// company precision + separators) instead of the bare [NumberFormat]
  /// fallback. [currencyId] feeds the client-currency cascade.
  final Formatter? formatter;
  final String? currencyId;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    if (dense && slim) {
      // One line, the figures at the end: Total, and Balance Due beside it
      // while it says something the total does not.
      final showBalance = balance != null && balance != totals.total;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: InSpacing.lg(context),
          vertical: InSpacing.sm,
        ),
        color: tokens.surfaceAlt,
        child: showBalance
            ? Wrap(
                alignment: WrapAlignment.end,
                spacing: InSpacing.xl,
                children: [
                  _pair(context, context.tr('total'), totals.total),
                  _pair(context, context.tr(balanceLabelKey), balance!),
                ],
              )
            : _row(
                context,
                label: context.tr('total'),
                amount: totals.total,
                strong: true,
              ),
      );
    }
    final rows = <Widget>[
      _row(context, label: context.tr('subtotal'), amount: totals.subtotal),
      if (discount != Decimal.zero)
        _row(
          context,
          label: context.tr('discount'),
          amount: discountIsAmount ? discount : null,
          rawText: discountIsAmount
              ? null
              : (formatter?.percent(discount.toDouble()) ??
                    '${discount.toString()}%'),
          subtractive: true,
        ),
      for (final s in surcharges)
        if (s.amount != Decimal.zero)
          _row(
            context,
            label: s.labelIsKey ? context.tr(s.label) : s.label,
            amount: s.amount,
          ),
      for (final entry in totals.taxBreakdown.entries)
        if (entry.value != Decimal.zero)
          _row(
            context,
            label: entry.key.isEmpty ? context.tr('tax') : entry.key,
            amount: entry.value,
          ),
      if (partial != Decimal.zero)
        _row(context, label: context.tr('partial'), amount: partial),
      ?editor,
      Divider(height: InSpacing.lg(context), color: tokens.border),
      _row(
        context,
        label: context.tr('total'),
        amount: totals.total,
        strong: true,
      ),
      if (paidToDate != null && paidToDate! != Decimal.zero)
        _row(
          context,
          label: context.tr(paidToDateLabelKey),
          amount: paidToDate!,
          subtractive: true,
        ),
      if (balance != null && !dense && leadBalance)
        _leadRow(context, context.tr(balanceLabelKey), balance!)
      else if (balance != null && balance != totals.total)
        _row(
          context,
          label: context.tr(balanceLabelKey),
          amount: balance!,
          strong: true,
        ),
    ];
    // In dense mode the totals widget is the sticky strip pinned to the
    // bottom of the edit screen — render flat (no border / radius) on
    // the alt surface so it reads as a footer rather than a card-inside-
    // a-strip. Non-dense mode (used in the detail screen) keeps the
    // bordered card chrome.
    if (dense) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: InSpacing.lg(context),
          vertical: InSpacing.sm,
        ),
        color: tokens.surfaceAlt,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      );
    }
    if (!bordered) {
      // Borderless row list — matches the React / old-Flutter
      // references where the totals sit as plain rows, no card.
      return Padding(
        padding: padded
            ? EdgeInsets.all(InSpacing.lg(context))
            : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      );
    }
    return Container(
      padding: EdgeInsets.all(InSpacing.lg(context)),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    Decimal? amount,
    String? rawText,
    bool strong = false,
    bool subtractive = false,
  }) {
    final tokens = context.inTheme;
    final amountText = rawText ?? _formatAmount(amount, subtractive);
    final color = subtractive ? tokens.ink3 : tokens.ink;
    final size = dense ? 13.0 : 14.0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2 : InSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: size,
              color: color,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          LtrText(
            amountText,
            style: moneyTextStyle(
              fontSize: size,
              color: color,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// The figure that leads — the open balance — on its own tinted band,
  /// a size up from the total above it.
  Widget _leadRow(BuildContext context, String label, Decimal amount) {
    final tokens = context.inTheme;
    return Container(
      margin: const EdgeInsets.only(top: InSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: InSpacing.sm,
        vertical: InSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: tokens.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          LtrText(
            _formatAmount(amount, false),
            style: moneyTextStyle(
              fontSize: 18,
              color: tokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// A label and its figure side by side, for the slim bar's one line.
  Widget _pair(BuildContext context, String label, Decimal amount) {
    final tokens = context.inTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: tokens.ink2)),
        const SizedBox(width: InSpacing.sm),
        LtrText(
          _formatAmount(amount, false),
          style: moneyTextStyle(
            fontSize: 13,
            color: tokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Money rendering: `Formatter.money` when a [formatter] was supplied, else
  /// the legacy bare [NumberFormat] (no symbol). Subtractive rows keep the
  /// leading `-`.
  String _formatAmount(Decimal? amount, bool subtractive) {
    if (amount == null) return '—';
    final sign = subtractive && amount > Decimal.zero ? '-' : '';
    final f = formatter;
    if (f != null) {
      // [currencyId] is the already-resolved party currency (client *or*
      // vendor) — pass it through the explicit slot so it's unambiguous for
      // vendor docs (purchase orders) too, not just clients.
      return '$sign${f.money(amount, currencyId: currencyId)}';
    }
    final numberFormat = NumberFormat.decimalPattern()
      ..minimumFractionDigits = 2
      ..maximumFractionDigits = 2;
    return '$sign${numberFormat.format(amount.toDouble())}';
  }
}

/// Helper struct: display-label + Decimal amount. Used by [TotalsWidget]
/// for the four invoice-level custom surcharges (whose labels come from
/// `company.customFields['surcharge1'..'surcharge4']`).
class TotalsSurcharge {
  const TotalsSurcharge({
    required this.label,
    required this.amount,
    this.labelIsKey = false,
  });

  /// Either the company's configured label, or — when it has none — a
  /// localization KEY (see [labelIsKey]).
  final String label;
  final Decimal amount;

  /// True when [label] is a localization key rather than user-entered text.
  final bool labelIsKey;
}

/// Build the [TotalsSurcharge] rows for a billing doc: one per slot the
/// company has labelled (`customFields['surcharge1'..'surcharge4']`) that also
/// carries a non-zero amount.
///
/// `computeTotals` folds all four surcharges into `total`, so a doc with a
/// surcharge and no row here renders a footer that doesn't add up (Subtotal
/// 100 → Total 150, nothing explaining the 50). Shared by the edit footer and
/// the read-only Overview tab so both itemize identically.
List<TotalsSurcharge> buildSurchargeRows({
  required Map<String, String>? customFields,
  required List<Decimal> amounts,
}) {
  final rows = <TotalsSurcharge>[];
  for (var i = 0; i < amounts.length && i < 4; i++) {
    // Visibility keys off the AMOUNT alone, matching the PDF
    // (`PdfBuilder::…` shows the row whenever the value is non-zero; the
    // label is a separate slot that may legitimately be blank). Skipping an
    // unlabelled surcharge here would put back the non-reconciling footer
    // this function exists to prevent — an invoice created by API/import, or
    // one billed before the label was cleared, still carries the amount.
    if (amounts[i] == Decimal.zero) continue;
    final label = surchargeLabel(customFields?['surcharge${i + 1}']);
    // Fall back to the generic slot label key (`surcharge1`…`surcharge4` are
    // real localization keys) so an unlabelled row still reads sensibly.
    rows.add(
      TotalsSurcharge(
        label: label.isNotEmpty ? label : 'surcharge${i + 1}',
        amount: amounts[i],
        labelIsKey: label.isEmpty,
      ),
    );
  }
  return rows;
}
