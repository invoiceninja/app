import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/invoice.dart';

import 'package:admin/data/models/domain/dashboard/dashboard_list_rows.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_record_row.dart';
import 'package:admin/ui/features/dashboard/widgets/list_card.dart';
import 'package:admin/ui/features/dashboard/widgets/status_badge.dart';
import 'package:admin/utils/formatting.dart';

/// The latest payments, newest first. On a wide screen a payment applied to
/// one invoice names it under the client ("for invoice 0011") when that
/// invoice is in the local cache; the amount is in the ordinary ink, like
/// every other amount on the dashboard — not green, and with no "+".
///
/// A row names its status only when it is something other than Completed —
/// which nearly every payment is, so a "Completed" pill on each row was a
/// column of noise that hid the one Pending or Failed payment worth seeing.
class RecentPaymentsCard extends StatelessWidget {
  const RecentPaymentsCard({
    super.key,
    required this.section,
    required this.formatter,
    required this.compact,
    required this.onPaymentTap,
    required this.onViewAll,
    required this.onRetry,
    this.preview,
  });

  final AsyncSection<List<DashboardPaymentRow>> section;
  final Formatter formatter;

  /// The stacked row form — passed by the host; see [DashboardRecordRow].
  final bool compact;
  final void Function(DashboardPaymentRow) onPaymentTap;
  final VoidCallback onViewAll;
  final VoidCallback onRetry;
  final int? preview;

  /// `Payment::STATUS_COMPLETED`.
  static const int _completed = 4;

  @override
  Widget build(BuildContext context) {
    return DashboardListCard<DashboardPaymentRow>(
      title: context.tr('recent_payments'),
      section: section,
      onViewAll: onViewAll,
      onRetry: onRetry,
      emptyTitle: context.tr('no_payments_yet'),
      preview: preview,
      bodyBuilder: (context, rows) => DashboardRecordRows(
        rows: [
          for (final r in rows)
            DashboardRecordRow(
              key: ValueKey('payment:${r.id}'),
              number: r.number,
              client: r.clientName,
              lead: r.date == null ? '' : formatter.date(r.date!.toIso()),
              // One invoice only: "for invoice 0011" over a payment split
              // across three would name a third of it.
              clientNote: r.invoiceIds.length == 1
                  ? PaymentInvoiceNote(invoiceId: r.invoiceIds.single)
                  : null,
              fact: r.statusId == _completed
                  ? null
                  : StatusBadge.paymentStatus(context, r.statusId).$1,
              amount: formatter.money(
                r.amount,
                currencyId: r.currencyId.isEmpty ? null : r.currencyId,
              ),
              onTap: () => onPaymentTap(r),
              compact: compact,
            ),
        ],
      ),
    );
  }
}

/// "for invoice 0011" — the invoice a payment was applied to, read from the
/// local cache. Draws nothing until (unless) the invoice is there: a hashed id
/// means nothing to anyone, and this line is a convenience, not a lookup worth
/// a request per row. Also nothing without `Services` above it (a bare test
/// harness).
class PaymentInvoiceNote extends StatefulWidget {
  const PaymentInvoiceNote({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<PaymentInvoiceNote> createState() => _PaymentInvoiceNoteState();
}

class _PaymentInvoiceNoteState extends State<PaymentInvoiceNote> {
  /// Hoisted out of `build`, so a rebuild does not resubscribe and flash the
  /// line empty for a frame (the "stable stream" rule).
  Stream<Invoice?>? _stream;
  Services? _services;
  String _companyId = '';
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(PaymentInvoiceNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoiceId != widget.invoiceId) _bind();
  }

  void _bind() {
    Services? services;
    try {
      services = context.read<Services>();
    } on ProviderNotFoundException {
      services = null;
    }
    final companyId = services?.auth.session.value?.currentCompanyId ?? '';
    final key = '$companyId|${widget.invoiceId}';
    if (key == _key) return;
    _key = key;
    _services = services;
    _companyId = companyId;
    if (services == null || companyId.isEmpty || widget.invoiceId.isEmpty) {
      _stream = null;
      return;
    }
    _stream = services.invoices.watch(
      companyId: companyId,
      id: widget.invoiceId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    final services = _services;
    if (stream == null || services == null) return const SizedBox.shrink();
    return StreamBuilder<Invoice?>(
      // A first-frame seed only (`peek_is_seed_only_test`): the watch on the
      // same (company, id) owns the value from its first event.
      initialData: services.invoices.peek(
        companyId: _companyId,
        id: widget.invoiceId,
      ),
      stream: stream,
      builder: (context, snapshot) {
        final number = snapshot.data?.number ?? '';
        if (number.isEmpty) return const SizedBox.shrink();
        return Text(context.tr('for_invoice_number', {'number': number}));
      },
    );
  }
}
