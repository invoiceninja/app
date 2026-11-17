import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/repositories/client_settings_cascade.dart';
import 'package:admin/domain/billing/selection_totals.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/utils/formatting.dart';

/// What the selected rows of a billing-document list come to — Amount, Net
/// Amount and (invoices, credits) Balance, one line per currency.
///
/// React totals the current page in a table footer. These lists load as you
/// scroll, so there is no page to total, and a sum of "whatever has loaded"
/// changes as you scroll; the selection is a set the user chose, so its total
/// is exact. Shown under the list while rows are selected.
///
/// Each row is in its party's currency — a client's (client → group →
/// company), or a purchase order's vendor's (vendor → company) — which only
/// resolves asynchronously, so the bar subscribes once per distinct party —
/// the cascade `PartyCurrencyBuilder` uses per row — and shows its figures once
/// every party has answered.
class SelectionTotalsBar extends StatefulWidget {
  const SelectionTotalsBar({
    super.key,
    required this.companyId,
    required this.rows,
    this.formatter,
  });

  final String companyId;
  final List<SelectionTotalsRow> rows;
  final Formatter? formatter;

  @override
  State<SelectionTotalsBar> createState() => _SelectionTotalsBarState();
}

class _SelectionTotalsBarState extends State<SelectionTotalsBar> {
  final Map<String, StreamSubscription<String>> _subscriptions = {};
  final Map<String, String> _currencies = {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(SelectionTotalsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _subscribe();
  }

  /// Follow exactly the parties the selection names: a party that leaves it
  /// stops being watched, one that joins starts.
  void _subscribe() {
    final services = context.read<Services>();
    final wanted = {for (final r in widget.rows) r.partyKey};
    for (final key in _subscriptions.keys.toList()) {
      if (wanted.contains(key)) continue;
      _subscriptions.remove(key)!.cancel();
      _currencies.remove(key);
    }
    for (final key in wanted) {
      if (_subscriptions.containsKey(key)) continue;
      final Stream<String> currency;
      if (key.startsWith(kVendorPartyPrefix)) {
        // A vendor names its currency or inherits the company's (`''`).
        currency = services.vendors
            .watch(
              companyId: widget.companyId,
              id: key.substring(kVendorPartyPrefix.length),
            )
            .map((v) => v?.currencyId ?? '');
      } else {
        currency = watchEffectiveClientCurrency(
          clients: services.clients,
          groups: services.groupSettings,
          companyId: widget.companyId,
          clientId: key,
        );
      }
      _subscriptions[key] = currency.listen((currencyId) {
        if (!mounted) return;
        setState(() => _currencies[key] = currencyId);
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final f = widget.formatter;
    // `''` is "the company's": named, so that two rows in the company currency
    // — one inheriting it, one naming it — land on one line.
    final companyCurrency = f?.settings.currencyId ?? '';
    final totals = selectionTotals(widget.rows, (partyKey) {
      final c = _currencies[partyKey];
      if (c == null) return null;
      return c.isEmpty ? companyCurrency : c;
    });
    String money(Decimal value, String currencyId) =>
        f?.money(value, clientCurrencyId: currencyId) ?? value.toString();
    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: InSpacing.lg(context),
            vertical: InSpacing.md(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in totals ?? const <CurrencyTotals>[])
                Wrap(
                  spacing: 24,
                  runSpacing: 4,
                  children: [
                    _Figure(
                      label: context.tr('amount'),
                      value: money(t.amount, t.currencyId),
                    ),
                    _Figure(
                      label: context.tr('net_amount'),
                      value: money(t.net, t.currencyId),
                    ),
                    if (t.balance != null)
                      _Figure(
                        label: context.tr('balance'),
                        value: money(t.balance!, t.currencyId),
                      ),
                  ],
                ),
              // Still resolving a client's currency: hold the bar's height
              // rather than print a total that is missing rows.
              if (totals == null) const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(fontSize: 12, color: tokens.ink3),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
