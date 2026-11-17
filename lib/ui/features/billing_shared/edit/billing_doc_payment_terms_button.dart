import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/payment_term.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/core/widgets/in_date_field.dart';
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
/// Built for the due date's [slot] (`InDateField.trailingAction`): a 28 px
/// icon inside a field wide enough for it beside the calendar; on a narrow
/// field's label line at Comfortable, the same icon in the label's touch
/// square; and on a narrow field at Compact, the field's only icon — the
/// calendar — opening a menu of "Select date" (the picker) and the terms.
/// That last is a menu rather than a terms entry in the picker because
/// `showDatePicker` has no slot for one, and a menu keeps every preset one
/// tap away at the cost of one tap for the picker.
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
    this.slot = const InDateFieldActionSlot(
      placement: InDateFieldActionPlacement.inField,
    ),
  });

  final String companyId;

  /// The invoice date counted from; null disables the button.
  final Date? date;

  /// The new due date.
  final ValueChanged<Date> onPicked;

  /// Shows each preset's resulting date beside it; omitted while null.
  final Formatter? formatter;

  /// Where the due date field draws this.
  final InDateFieldActionSlot slot;

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
        final slot = widget.slot;
        final merged =
            slot.placement == InDateFieldActionPlacement.replacesCalendar;
        // Small, like the calendar button beside it — except on the label
        // line, where `LabeledField` sizes and places the square.
        IconButton icon({
          required IconData glyph,
          required String tooltip,
          required VoidCallback? onPressed,
        }) => slot.placement == InDateFieldActionPlacement.labelLine
            ? IconButton(
                iconSize: 16,
                icon: Icon(glyph),
                tooltip: tooltip,
                onPressed: onPressed,
              )
            : IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(glyph),
                tooltip: tooltip,
                onPressed: onPressed,
              );
        if (days.isEmpty) {
          // No terms: in the calendar's place it is just the calendar.
          return merged
              ? icon(
                  glyph: Icons.date_range,
                  tooltip: context.tr('select_date'),
                  onPressed: slot.openPicker,
                )
              : const SizedBox.shrink();
        }
        final date = widget.date;
        final formatter = widget.formatter;
        return BackDismissibleMenuAnchor(
          consumeOutsideTap: true,
          menuChildren: [
            if (merged)
              MenuItemButton(
                leadingIcon: const Icon(Icons.date_range, size: 18),
                onPressed: slot.openPicker,
                child: Text(context.tr('select_date')),
              ),
            if (merged && date != null) const Divider(height: 1),
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
          // A small icon beside the due date's calendar button: a labelled
          // button under the field took a row of its own and crowded the
          // fields below it.
          builder: (context, controller, _) {
            void toggle() =>
                controller.isOpen ? controller.close() : controller.open();
            return merged
                ? icon(
                    glyph: Icons.date_range,
                    tooltip: context.tr('select_date'),
                    onPressed: toggle,
                  )
                : icon(
                    glyph: Icons.event_repeat_outlined,
                    tooltip: context.tr('payment_terms'),
                    onPressed: date == null ? null : toggle,
                  );
          },
        );
      },
    );
  }
}
