import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:admin/ui/features/expenses/view_models/expense_edit_view_model.dart';
import 'package:admin/utils/formatting.dart';

/// Currency conversion sub-form — exchange_rate + foreign_amount +
/// invoice_currency_id picker. Lives in the Invoicing card under its own
/// heading; this widget only renders the fields themselves.
class ExpenseEditCurrencyConversionSection extends StatelessWidget {
  const ExpenseEditCurrencyConversionSection({super.key, required this.vm});
  final ExpenseEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final currencies = services.statics.currencies.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    Currency? selected;
    for (final c in currencies) {
      if (c.id == vm.draft.invoiceCurrencyId) {
        selected = c;
        break;
      }
    }
    final invoiceCurrency = vm.draft.invoiceCurrencyId;
    final converts =
        invoiceCurrency.isNotEmpty && invoiceCurrency != vm.draft.currencyId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Half width like every field on the card; the rate and the converted
        // amount join it only once there is something to convert to: an
        // invoice currency other than the expense's own.
        ...pairFields([
          SearchableDropdownField<Currency>(
            label: context.tr('invoice_currency'),
            items: currencies,
            initialValue: selected,
            displayString: (c) => '${c.code} · ${c.name}',
            idOf: (c) => c.id,
            onChanged: (c) {
              vm.setInvoiceCurrencyId(c?.id ?? '');
              // Seed the exchange rate from the two currencies' base rates so
              // the user doesn't have to look it up (React parity). The VM then
              // recomputes the foreign amount. Leaves the rate untouched when it
              // can't be resolved (unknown currency / no expense currency yet).
              if (c != null) {
                final rate = crossCurrencyRate(
                  services.statics.currencies,
                  fromExpenseCurrencyId: vm.draft.currencyId,
                  toInvoiceCurrencyId: c.id,
                );
                if (rate != null) vm.setExchangeRate(rate.toString());
              }
            },
            errorText: vm.fieldErrorFor('invoice_currency_id'),
          ),
          if (converts)
            EntityEditField(
              numeric: true,
              useCommaAsDecimalPlace: vm.useCommaAsDecimalPlace,
              label: context.tr('exchange_rate'),
              initial: decimalInputText(vm.draft.exchangeRate),
              onChanged: vm.setExchangeRate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              errorText: vm.fieldErrorFor('exchange_rate'),
            ),
          if (converts)
            EntityEditField(
              numeric: true,
              useCommaAsDecimalPlace: vm.useCommaAsDecimalPlace,
              label: context.tr('foreign_amount'),
              initial: decimalInputText(vm.draft.foreignAmount),
              onChanged: vm.setForeignAmount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              errorText: vm.fieldErrorFor('foreign_amount'),
            ),
        ]),
      ],
    );
  }
}
