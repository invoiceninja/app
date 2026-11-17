import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/payment_term.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/utils/formatting.dart';

/// The day counts [terms] offer as due-date presets: each distinct
/// `num_days` once, shortest first. Two terms the user named differently but
/// with the same days set the same date, so the menu lists the date rule, not
/// the name.
List<int> paymentTermPresetDays(Iterable<PaymentTerm> terms) {
  final days = <int>{
    for (final t in terms)
      if (!t.isDeleted && t.numDays >= 0) t.numDays,
  }.toList()..sort();
  return days;
}

/// A preset's label: "Due on Receipt" for 0 days, else "Net 30" — the words
/// the due date's own cascade hint (`_dueDaysHint`) uses for the same setting.
String paymentTermPresetLabel(BuildContext context, int days) =>
    days == 0 ? context.tr('due_on_receipt') : '${context.tr('net')} $days';

/// "Payment Terms" under an invoice's due date: a menu of the company's
/// payment terms, each setting the due date to the invoice date plus its days
/// — the arithmetic the server's `setDueDate` does from the `payment_terms`
/// setting when a blank due date is sent, done here so the user sees it.
///
/// Disabled while the invoice date is blank (there is nothing to count from);
/// absent when the company has no terms. Invoices only — the caller gates it on
/// `BillingDocType.offersPaymentTermPresets`.
///
/// Stateful so the Drift watch is opened once: the edit layout rebuilds on
/// every keystroke, and a stream built in `build` would re-subscribe each time.
class BillingDocPaymentTermsButton extends StatefulWidget {
  const BillingDocPaymentTermsButton({
    super.key,
    required this.companyId,
    required this.date,
    required this.onPicked,
    this.formatter,
  });

  final String companyId;

  /// The invoice date counted from; null disables the button.
  final Date? date;

  /// The new due date.
  final ValueChanged<Date> onPicked;

  /// Shows each preset's resulting date beside it; omitted while null.
  final Formatter? formatter;

  @override
  State<BillingDocPaymentTermsButton> createState() =>
      _BillingDocPaymentTermsButtonState();
}

class _BillingDocPaymentTermsButtonState
    extends State<BillingDocPaymentTermsButton> {
  late Stream<List<PaymentTerm>> _terms = _watch();

  Stream<List<PaymentTerm>> _watch() => context
      .read<Services>()
      .paymentTerms
      .watchAll(companyId: widget.companyId);

  @override
  void didUpdateWidget(BillingDocPaymentTermsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) _terms = _watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentTerm>>(
      stream: _terms,
      builder: (context, snapshot) {
        final days = paymentTermPresetDays(snapshot.data ?? const []);
        if (days.isEmpty) return const SizedBox.shrink();
        final date = widget.date;
        final formatter = widget.formatter;
        return BackDismissibleMenuAnchor(
          consumeOutsideTap: true,
          menuChildren: [
            if (date != null)
              for (final d in days)
                MenuItemButton(
                  onPressed: () => widget.onPicked(date.addDays(d)),
                  trailingIcon: formatter == null
                      ? null
                      : Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16),
                          child: LtrText(
                            formatter.date(date.addDays(d).toIso()),
                          ),
                        ),
                  child: Text(paymentTermPresetLabel(context, d)),
                ),
          ],
          // A small icon inside the due date field, beside its calendar
          // button: a labelled button under the field took a row of its own
          // and crowded the fields below it.
          builder: (context, controller, _) => IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Icons.event_repeat_outlined),
            tooltip: context.tr('payment_terms'),
            onPressed: date == null
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
          ),
        );
      },
    );
  }
}
