import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/payments/view_models/payment_edit_view_model.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

/// Running totals under a new payment's allocations: **Applied** and
/// **Unapplied** — never "credit": money left on a payment stays on the
/// payment, to be applied later; it is not a credit note.
///
///   * **Applied** — what the invoices take net of the credits that pay them
///     too ([PaymentEditViewModel.netApplied]). An error (icon + tooltip) when
///     the credits outweigh the invoices (`credit_payment_error`), or the
///     invoices outweigh the amount and the credits
///     (`amounts_do_not_balance`) — the two rules the save enforces.
///   * **Unapplied** — what the amount received leaves over, shown once an
///     amount is typed. An error while the company has Manual Overpayments
///     (`enable_applying_payments`) off: there it is
///     `over_payments_disabled` at save.
class PaymentAllocationsFooter extends StatelessWidget {
  const PaymentAllocationsFooter({
    super.key,
    required this.vm,
    this.formatter,
    this.currencyId,
  });

  final PaymentEditViewModel vm;
  final Formatter? formatter;

  /// Effective payment currency, resolved by the layout (client → group →
  /// company). Falls back to `draft.currencyId` when not supplied.
  final String? currencyId;

  // `clientCurrencyId` matters: the Formatter handed down here is
  // company-scoped, so without it a JPY/EUR client's totals rendered with the
  // company's symbol, separators AND precision.
  String _fmt(Decimal value) => formatter == null
      ? value.toString()
      : formatter!.money(
          value,
          clientCurrencyId: currencyId?.isNotEmpty == true
              ? currencyId
              : vm.draft.currencyId,
        );

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final applied = vm.netApplied;
    final amount = vm.draft.amount;
    final hasAnyAllocation = vm.draft.paymentables.isNotEmpty;

    // Nothing to sum before the user has done anything.
    if (!hasAnyAllocation && amount == Decimal.zero) {
      return const SizedBox.shrink();
    }

    final overCredited = applied < Decimal.zero;
    final overApplied =
        !overCredited &&
        amount > Decimal.zero &&
        vm.invoiceAllocatedTotal.round(scale: 2) >
            (amount + vm.creditAllocatedTotal).round(scale: 2);
    final unapplied = vm.unappliedAmount;
    final unappliedRefused =
        !vm.enableApplyingPayments && unapplied > Decimal.zero;
    final errorColor = theme.colorScheme.error;
    Widget errorIcon() =>
        Icon(Icons.error_outline, color: errorColor, size: 16);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _Cell(
            label: context.tr('applied'),
            value: _fmt(applied),
            valueColor: overCredited || overApplied ? errorColor : tokens.ink,
            leading: overCredited || overApplied ? errorIcon() : null,
            tooltip: overCredited
                ? context.tr('credit_payment_error')
                : overApplied
                ? context.tr('amounts_do_not_balance')
                : null,
          ),
          if (amount > Decimal.zero)
            _Cell(
              label: context.tr('unapplied'),
              value: _fmt(unapplied),
              valueColor: unappliedRefused
                  ? errorColor
                  : unapplied > Decimal.zero
                  ? tokens.ink
                  : tokens.ink3,
              leading: unappliedRefused ? errorIcon() : null,
              tooltip: unappliedRefused
                  ? context.tr('over_payments_disabled')
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    required this.valueColor,
    this.leading,
    this.tooltip,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Widget? leading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 4)],
        Text('$label ', style: TextStyle(color: tokens.ink3, fontSize: 12)),
        LtrText(
          value,
          style: moneyTextStyle(color: valueColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: row);
    }
    return row;
  }
}
