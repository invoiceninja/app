import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:admin/ui/core/widgets/form_group_heading.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/formatting.dart';

/// The Invoicing card, shared by the Expense and Recurring Expense edit
/// screens (each feeds it from its own view model — no VM type leaks in).
///
/// Who the expense is billed to ([billTo]: Client and Project) is always
/// shown — picking a client is how most people start billing an expense on.
/// **Should be invoiced** is the card's switch, with a line saying what it
/// does; turning it on reveals what only matters for an expense that is
/// billed: whether its documents go on the invoice (seeded from the company's
/// `invoice_expense_documents`, as before) and the currency conversion.
///
/// Turning the switch off hides those fields but keeps their values: the
/// draft is what saves, and a switch flipped by mistake must not wipe a rate.
class ExpenseInvoicingCard extends StatelessWidget {
  const ExpenseInvoicingCard({
    super.key,
    required this.billTo,
    required this.shouldBeInvoiced,
    required this.onShouldBeInvoicedChanged,
    required this.invoiceDocuments,
    required this.onInvoiceDocumentsChanged,
    required this.conversion,
  });

  final Widget billTo;
  final bool shouldBeInvoiced;
  final ValueChanged<bool> onShouldBeInvoicedChanged;
  final bool invoiceDocuments;
  final ValueChanged<bool> onInvoiceDocumentsChanged;

  /// The currency conversion fields ([ExpenseCurrencyConversionFields]).
  final Widget conversion;

  @override
  Widget build(BuildContext context) {
    return DashboardCardShell(
      title: context.tr('invoicing'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          billTo,
          const SizedBox(height: InSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('should_be_invoiced')),
            // Transifex's own help line (React shows the same one).
            subtitle: Text(context.tr('mark_invoiceable_help')),
            value: shouldBeInvoiced,
            onChanged: onShouldBeInvoicedChanged,
          ),
          if (shouldBeInvoiced) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('invoice_documents')),
              value: invoiceDocuments,
              onChanged: onInvoiceDocumentsChanged,
            ),
            FormGroupHeading(context.tr('currency_conversion')),
            conversion,
          ],
        ],
      ),
    );
  }
}

/// The currency conversion fields: the invoice currency, then — once it
/// differs from the expense's own — the exchange rate and the converted
/// amount, both editable (the view model keeps each in step with the other).
///
/// Picking an invoice currency seeds the rate from the two currencies' base
/// rates (React parity); a rate that can't be resolved (an unknown currency,
/// no expense currency yet) is left as it was.
class ExpenseCurrencyConversionFields extends StatelessWidget {
  const ExpenseCurrencyConversionFields({
    super.key,
    required this.expenseCurrencyId,
    required this.invoiceCurrencyId,
    required this.exchangeRate,
    required this.convertedAmount,
    required this.useCommaAsDecimalPlace,
    required this.onInvoiceCurrencyChanged,
    required this.onExchangeRateChanged,
    required this.onConvertedAmountChanged,
    required this.errorFor,
  });

  final String expenseCurrencyId;
  final String invoiceCurrencyId;
  final Decimal exchangeRate;

  /// `foreign_amount` on the wire.
  final Decimal convertedAmount;
  final bool useCommaAsDecimalPlace;
  final ValueChanged<String> onInvoiceCurrencyChanged;

  /// Takes the rate as typed; a seeded rate arrives as its `toString()`.
  final ValueChanged<String> onExchangeRateChanged;
  final ValueChanged<String> onConvertedAmountChanged;

  /// The server's 422 message for a field, by its wire name.
  final String? Function(String field) errorFor;

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final currencies = services.statics.currencies.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    Currency? selected;
    for (final c in currencies) {
      if (c.id == invoiceCurrencyId) {
        selected = c;
        break;
      }
    }
    final converts =
        invoiceCurrencyId.isNotEmpty && invoiceCurrencyId != expenseCurrencyId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Half width like every field on the card; the rate and the converted
        // amount join it only once there is something to convert to.
        ...pairFields([
          SearchableDropdownField<Currency>(
            label: context.tr('invoice_currency'),
            items: currencies,
            initialValue: selected,
            displayString: (c) => '${c.code} · ${c.name}',
            idOf: (c) => c.id,
            onChanged: (c) {
              onInvoiceCurrencyChanged(c?.id ?? '');
              if (c != null) {
                final rate = crossCurrencyRate(
                  services.statics.currencies,
                  fromExpenseCurrencyId: expenseCurrencyId,
                  toInvoiceCurrencyId: c.id,
                );
                if (rate != null) onExchangeRateChanged(rate.toString());
              }
            },
            errorText: errorFor('invoice_currency_id'),
          ),
          if (converts)
            EntityEditField(
              numeric: true,
              useCommaAsDecimalPlace: useCommaAsDecimalPlace,
              label: context.tr('exchange_rate'),
              initial: decimalInputText(exchangeRate),
              onChanged: onExchangeRateChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              errorText: errorFor('exchange_rate'),
            ),
          if (converts)
            EntityEditField(
              numeric: true,
              useCommaAsDecimalPlace: useCommaAsDecimalPlace,
              label: context.tr('converted_amount'),
              initial: decimalInputText(convertedAmount),
              onChanged: onConvertedAmountChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              errorText: errorFor('foreign_amount'),
            ),
        ]),
      ],
    );
  }
}
