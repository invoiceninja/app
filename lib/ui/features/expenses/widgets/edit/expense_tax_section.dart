import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/tax_rate.dart';
import 'package:admin/data/models/value/parsing.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/formatter_host_mixin.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_field_pair.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/formatting.dart';

/// Per-slot string setter — `slot` is 1..3.
typedef TaxSlotSetter = void Function(int slot, String value);

/// Amount + tax entry card, shared by the Expense and Recurring Expense edit
/// screens (both feed it from their own ViewModel — no VM type leaks in).
///
/// Tax entry mirrors React (`expenses/create/components/{Details,Taxes}.tsx`)
/// and admin-portal `TaxRateDropdown`:
///   * a **By rate / By amount** selector (`calculate_tax_by_amount`),
///   * **By rate**: each tier is a searchable picker over the company's
///     configured `tax_rates` (selecting one fills both `tax_name` and
///     `tax_rate`); falls back to a freeform name/rate pair when the company
///     has no rates defined,
///   * **By amount**: each tier is a freeform name + amount pair,
///   * switching modes resets the opposite-mode values + names (React
///     `handleResetTaxValues`).
///
/// The number of tiers tracks `company.settings.enabled_expense_tax_rates`
/// (with an "Add tax" overflow up to 3); when it's 0 a hint links to Tax
/// Settings instead of showing tax inputs (React parity).
///
/// Below the tax inputs the card states the result: the tax and the
/// **Expense Total** (the gross — the amount plus tax, or the amount itself
/// when it already includes tax), which admin-portal printed in the edit
/// footer. The caller computes both from its draft (`taxAmountSum`,
/// `grossAmount`) so the figures are the domain model's own math.
class ExpenseTaxSection extends StatefulWidget {
  const ExpenseTaxSection({
    super.key,
    required this.companyId,
    this.useCommaAsDecimalPlace = false,
    required this.amount,
    this.amountBeside,
    this.amountTrailing,
    this.wrapAmountFields,
    required this.amountError,
    required this.taxNames,
    required this.taxRates,
    required this.taxAmounts,
    required this.usesInclusiveTaxes,
    required this.calculateTaxByAmount,
    required this.currencyId,
    required this.taxTotal,
    required this.total,
    required this.onAmountChanged,
    required this.onTaxNameChanged,
    required this.onTaxRateChanged,
    required this.onTaxAmountChanged,
    required this.onUsesInclusiveTaxesChanged,
    required this.onCalculateByAmountChanged,
    this.amountHelper,
    this.taxHelpers = const [null, null, null],
  });

  final String companyId;

  /// The company's decimal separator, threaded to the numeric fields below.
  /// Without it a comma-locale user typing `12,5` is fought by the re-seed:
  /// `parseDecimal('12,5', useComma: false)` strips the comma and yields 125,
  /// which never equals the parent's canonical `12.5`, so the controller is
  /// rewritten and the caret jumps — the exact bug `numeric` exists to stop.
  final bool useCommaAsDecimalPlace;
  final Decimal amount;

  /// Sits beside the amount where the card has room: the expense's currency
  /// picker, since that is the currency the amount is in.
  final Widget? amountBeside;

  /// Third on the amount's row, after [amountBeside]: the expense's date on
  /// New / Edit Expense, so the two facts every receipt carries are entered
  /// side by side. Recurring Expense passes none (it has no date).
  final Widget? amountTrailing;

  /// Wraps the amount field, and separately the tax inputs, in the caller's
  /// receipt focus scope (`ReceiptFieldFocus`) — the amount and its taxes are
  /// one field for a receipt read, while [amountBeside] and [amountTrailing]
  /// keep scopes of their own, so typing a date never holds a read off the
  /// amount. Null on Recurring Expense, which reads no receipts.
  final Widget Function(Widget child)? wrapAmountFields;
  final String? amountError;

  /// Current tier values, length 3 (index 0 → slot 1).
  final List<String> taxNames;
  final List<Decimal> taxRates;
  final List<Decimal> taxAmounts;

  final bool usesInclusiveTaxes;
  final bool calculateTaxByAmount;

  /// The expense's currency, for the summary below the taxes.
  final String currencyId;

  /// The summed tax across the tiers, and the gross amount (tax included).
  final Decimal taxTotal;
  final Decimal total;

  final ValueChanged<String> onAmountChanged;
  final TaxSlotSetter onTaxNameChanged;
  final TaxSlotSetter onTaxRateChanged;
  final TaxSlotSetter onTaxAmountChanged;
  final ValueChanged<bool> onUsesInclusiveTaxesChanged;
  final ValueChanged<bool> onCalculateByAmountChanged;

  /// Under the amount and under each tax tier (index 0 → slot 1): a "From
  /// receipt" marker on New Expense (`ReceiptFieldMarker`). Recurring Expense
  /// passes none.
  final Widget? amountHelper;
  final List<Widget?> taxHelpers;

  @override
  State<ExpenseTaxSection> createState() => _ExpenseTaxSectionState();
}

class _ExpenseTaxSectionState extends State<ExpenseTaxSection>
    with FormatterHostMixin {
  @override
  void initState() {
    super.initState();
    loadFormatter(context.read<Services>(), widget.companyId);
  }

  @override
  void didUpdateWidget(ExpenseTaxSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      clearFormatter();
      loadFormatter(context.read<Services>(), widget.companyId);
    }
  }

  /// Tax tiers on screen: the larger of the company's enabled count and the
  /// draft's populated rows, plus any the user added via "Add tax". Grow-only
  /// and recomputed on every build — it used to be latched on the first
  /// build, which on a new expense ran before the company row arrived, so the
  /// company's enabled tiers never appeared and the tax-settings hint stayed.
  int _visibleTaxRows = 0;

  int get _draftPopulated {
    for (var slot = 3; slot >= 1; slot--) {
      final i = slot - 1;
      if (widget.taxNames[i].isNotEmpty ||
          widget.taxRates[i] != Decimal.zero ||
          widget.taxAmounts[i] != Decimal.zero) {
        return slot;
      }
    }
    return 0;
  }

  /// Reveal one more tax tier (up to 3) via the "Add tax" button.
  void _addTaxRow() {
    setState(() {
      if (_visibleTaxRows < 3) _visibleTaxRows++;
    });
  }

  /// Switch tax-entry mode, clearing the opposite-mode values and all names —
  /// mirrors React `handleResetTaxValues` so a stale rate doesn't ship with a
  /// by-amount expense (or vice versa).
  void _onModeChanged(bool byAmount) {
    if (byAmount == widget.calculateTaxByAmount) return;
    widget.onCalculateByAmountChanged(byAmount);
    for (var slot = 1; slot <= 3; slot++) {
      widget.onTaxNameChanged(slot, '');
      if (byAmount) {
        widget.onTaxRateChanged(slot, '0');
      } else {
        widget.onTaxAmountChanged(slot, '0');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    return StreamBuilder<Company?>(
      stream: services.company.watchCompany(widget.companyId),
      // The last company this session saw, so the first frame already knows
      // the enabled tiers.
      initialData: services.company.peek(
        companyId: widget.companyId,
        id: widget.companyId,
      ),
      builder: (context, snapshot) {
        final companyEnabled = (snapshot.data?.enabledExpenseTaxRates ?? 0)
            .clamp(0, 3);
        _visibleTaxRows = max(
          _visibleTaxRows,
          max(companyEnabled, _draftPopulated),
        );
        final visible = _visibleTaxRows;

        final amountField = EntityEditField(
          numeric: true,
          useCommaAsDecimalPlace: widget.useCommaAsDecimalPlace,
          label: context.tr('amount'),
          initial: decimalInputText(widget.amount),
          onChanged: widget.onAmountChanged,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          errorText: widget.amountError,
          helper: widget.amountHelper,
        );
        Widget scoped(Widget child) =>
            widget.wrapAmountFields?.call(child) ?? child;
        final amount = scoped(amountField);
        final beside = widget.amountBeside;
        final trailing = widget.amountTrailing;
        return DashboardCardShell(
          title: context.tr('amount'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (beside != null && trailing != null)
                _AmountRow(children: [amount, beside, trailing])
              else if (beside != null)
                ClientEditFieldPair(left: amount, right: beside)
              else
                amount,
              if (visible == 0)
                _TaxDisabledHint()
              else
                scoped(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TaxArea(
                        state: this,
                        visible: visible,
                        companyId: widget.companyId,
                      ),
                      _TaxSummary(
                        formatter: formatter,
                        currencyId: widget.currencyId,
                        usesInclusiveTaxes: widget.usesInclusiveTaxes,
                        taxTotal: widget.taxTotal,
                        total: widget.total,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Amount, currency and date on one row where the card has room, stacked
/// below [_threeUpWidth]. Measured on the card, not the window: in the
/// two-column form the card is the main column's width.
class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.children});

  final List<Widget> children;

  /// About 165 px a field: enough for an amount, a currency code and a date.
  static const double _threeUpWidth = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _threeUpWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: InSpacing.md(context)),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// What the taxes add up to, under the tax inputs. Exclusive: Tax, then the
/// Expense Total (amount + tax). Inclusive: Net Amount and Tax, then the
/// Expense Total — which is the amount as typed, so the net is the figure the
/// user can't otherwise see; the rows read as net + tax = total. Matches the
/// detail screen's standing card (`ExpenseDetailStanding`).
///
/// An em dash while the company's formatter loads (it is almost always warm).
class _TaxSummary extends StatelessWidget {
  const _TaxSummary({
    required this.formatter,
    required this.currencyId,
    required this.usesInclusiveTaxes,
    required this.taxTotal,
    required this.total,
  });

  final Formatter? formatter;
  final String currencyId;
  final bool usesInclusiveTaxes;
  final Decimal taxTotal;
  final Decimal total;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    String money(Decimal v) =>
        formatter?.money(v, clientCurrencyId: currencyId) ?? '\u2014';
    Widget line(String label, Decimal value, {bool strong = false}) {
      final size = strong ? 15.0 : 13.0;
      final weight = strong ? FontWeight.w600 : FontWeight.w400;
      final color = strong ? tokens.ink : tokens.ink3;
      // One screen-reader stop per row: "Tax, $20.00", never two stray nodes.
      return MergeSemantics(
        child: Padding(
          padding: EdgeInsets.only(top: InSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: weight,
                    color: color,
                  ),
                ),
              ),
              LtrText(
                money(value),
                textAlign: TextAlign.end,
                style: moneyTextStyle(
                  fontSize: size,
                  fontWeight: weight,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: InSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: InSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (usesInclusiveTaxes)
                line(context.tr('net_amount'), total - taxTotal),
              line(context.tr('tax'), taxTotal),
              line(context.tr('expense_total'), total, strong: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hint shown when `enabled_expense_tax_rates == 0` — directs the user to Tax
/// Settings rather than offering tax inputs (React `Taxes.tsx`).
class _TaxDisabledHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Padding(
      padding: EdgeInsets.only(top: InSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('expense_tax_help'),
              style: TextStyle(color: tokens.ink3, fontSize: 13),
            ),
          ),
          // Names where it goes, in the accent, and a full 44 px target on
          // touch — "Settings" alone read as this card's own settings.
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: tokens.accentInk,
              minimumSize: Env.isTouchPrimary
                  ? const Size(64, InSizes.touchTarget)
                  : null,
            ),
            onPressed: () => context.go('/settings/tax_settings'),
            child: Text(context.tr('tax_settings')),
          ),
        ],
      ),
    );
  }
}

class _TaxArea extends StatelessWidget {
  const _TaxArea({
    required this.state,
    required this.visible,
    required this.companyId,
  });

  final _ExpenseTaxSectionState state;
  final int visible;
  final String companyId;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final byAmount = w.calculateTaxByAmount;
    final canAdd = visible < 3;
    final services = context.read<Services>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(top: InSpacing.sm, bottom: InSpacing.xs),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(context.tr('by_rate'))),
                ButtonSegment(
                  value: true,
                  label: Text(context.tr('by_amount')),
                ),
              ],
              selected: {byAmount},
              onSelectionChanged: (set) =>
                  set.isEmpty ? null : state._onModeChanged(set.first),
            ),
          ),
        ),
        // By-rate tiers pick from the company's bundled tax rates. One stream
        // feeds every visible slot.
        if (!byAmount)
          StreamBuilder<List<TaxRate>>(
            stream: services.taxRates.watchAll(companyId: companyId),
            builder: (context, snap) {
              final rates = snap.data ?? const <TaxRate>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var slot = 1; slot <= visible; slot++)
                    _RatePickerSlot(state: state, slot: slot, rates: rates),
                ],
              );
            },
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var slot = 1; slot <= visible; slot++)
                _AmountSlot(state: state, slot: slot),
            ],
          ),
        if (canAdd)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: state._addTaxRow,
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('add_tax')),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: InSpacing.sm),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('inclusive_taxes')),
            value: w.usesInclusiveTaxes,
            onChanged: w.onUsesInclusiveTaxesChanged,
          ),
        ),
      ],
    );
  }
}

/// One by-rate tier: a searchable picker over the bundled tax rates (picking
/// one writes both name + rate). Falls back to a freeform name/rate pair when
/// the company has no rates configured. Mirrors the products tax slot.
class _RatePickerSlot extends StatelessWidget {
  const _RatePickerSlot({
    required this.state,
    required this.slot,
    required this.rates,
  });

  final _ExpenseTaxSectionState state;
  final int slot;
  final List<TaxRate> rates;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final i = slot - 1;
    final name = w.taxNames[i];
    final rate = w.taxRates[i];

    if (rates.isEmpty) {
      // No bundled rates → keep a freeform pair so a tax can still be entered.
      return Padding(
        padding: EdgeInsets.symmetric(vertical: InSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: EntityEditField(
                label: context.tr('tax_name$slot'),
                initial: name,
                onChanged: (v) => w.onTaxNameChanged(slot, v),
              ),
            ),
            SizedBox(width: InSpacing.md(context)),
            Expanded(
              flex: 2,
              child: EntityEditField(
                numeric: true,
                useCommaAsDecimalPlace: w.useCommaAsDecimalPlace,
                label: context.tr('tax_rate$slot'),
                initial: decimalInputText(rate),
                onChanged: (v) => w.onTaxRateChanged(slot, v),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                helper: w.taxHelpers[i],
              ),
            ),
          ],
        ),
      );
    }

    final sorted = [...rates]..sort((a, b) => a.name.compareTo(b.name));
    TaxRate? selected;
    for (final r in sorted) {
      if (r.name == name && numToDecimal(r.rate) == rate) {
        selected = r;
        break;
      }
    }
    // Stored value not in the bundled list (a legacy hand-entered rate) → show
    // a synthetic entry so the user still sees what's saved.
    if (selected == null && name.isNotEmpty) {
      selected = TaxRate(
        id: '__current__',
        name: name,
        rate: rate.toDouble(),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        archivedAt: null,
        isDeleted: false,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: InSpacing.xs),
      child: SearchableDropdownField<TaxRate>(
        label: context.tr('tax_rate$slot'),
        items: sorted,
        initialValue: selected,
        displayString: (r) => '${r.name} (${r.rate}%)',
        idOf: (r) => '${r.name}|${r.rate}',
        helper: w.taxHelpers[i],
        onChanged: (r) {
          w.onTaxNameChanged(slot, r?.name ?? '');
          w.onTaxRateChanged(slot, r == null ? '0' : r.rate.toString());
        },
      ),
    );
  }
}

/// One by-amount tier: freeform name + tax-amount pair.
class _AmountSlot extends StatelessWidget {
  const _AmountSlot({required this.state, required this.slot});

  final _ExpenseTaxSectionState state;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final w = state.widget;
    final i = slot - 1;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: InSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: EntityEditField(
              label: context.tr('tax_name$slot'),
              initial: w.taxNames[i],
              onChanged: (v) => w.onTaxNameChanged(slot, v),
            ),
          ),
          SizedBox(width: InSpacing.md(context)),
          Expanded(
            flex: 2,
            child: EntityEditField(
              numeric: true,
              useCommaAsDecimalPlace: w.useCommaAsDecimalPlace,
              label: context.tr('tax_amount'),
              initial: decimalInputText(w.taxAmounts[i]),
              onChanged: (v) => w.onTaxAmountChanged(slot, v),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              helper: w.taxHelpers[i],
            ),
          ),
        ],
      ),
    );
  }
}
