import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_totals.dart';
import 'package:admin/domain/outstanding_by_currency.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/utils/bidi.dart';
import 'package:admin/utils/formatting.dart';

final _log = Logger('ListOutstandingLine');

/// How old the cached outstanding totals may be before opening a list asks the
/// server again. The dashboard refreshes the same row on its own schedule (and
/// whenever a change leaves the outbox), so this only matters for a session
/// that goes straight to a list.
const Duration kListOutstandingMaxAge = Duration(minutes: 5);

/// The muted "Outstanding $22,924.00 · £6,091.00" line under the Clients and
/// Invoices narrow (phone) list titles — the wide header is one toolbar row
/// with no title, so it has none — the server's per-currency outstanding totals, read
/// from the dashboard's own cache row (`DashboardRepository.watchOutstanding`,
/// drafts left out), never summed on the device from whatever rows happen to
/// be loaded.
///
/// Draws nothing at all while the figure is unknown (nothing cached, the
/// formatter not resolved, a user without `view_dashboard`, whom the server
/// refuses the endpoint) and when nothing is outstanding — unknown is never
/// zero. See `docs/entity-lists.md` § A list's title row.
class ListOutstandingLine extends StatefulWidget {
  const ListOutstandingLine({
    required this.companyId,
    required this.formatter,
    this.fontSize = 13,
    super.key,
  });

  final String companyId;

  /// Null while the list's formatter is still resolving: the line waits.
  final Formatter? formatter;

  final double fontSize;

  @override
  State<ListOutstandingLine> createState() => _ListOutstandingLineState();
}

class _ListOutstandingLineState extends State<ListOutstandingLine> {
  Stream<DashboardTotals?>? _stream;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ListOutstandingLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) _bind();
  }

  bool get _allowed =>
      context.read<Services>().auth.session.value?.currentCompany?.can(
        'view_dashboard',
      ) ??
      false;

  /// The stream is held, not built in `build` — a Drift watch replays on
  /// every re-subscribe, which would flash the line on each rebuild.
  void _bind() {
    if (!_allowed) {
      _stream = null;
      return;
    }
    final repo = context.read<Services>().dashboard;
    _stream = repo.watchOutstanding(widget.companyId, includeDrafts: false);
    unawaited(
      repo
          .refreshOutstanding(
            widget.companyId,
            includeDrafts: false,
            maxAge: kListOutstandingMaxAge,
          )
          .catchError((Object e) {
            // Offline, a company switch under the fetch, a server error: the
            // line keeps whatever is cached, or stays hidden.
            _log.fine('Outstanding totals not refreshed: $e');
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    final formatter = widget.formatter;
    if (stream == null || formatter == null) return const SizedBox.shrink();
    return StreamBuilder<DashboardTotals?>(
      stream: stream,
      builder: (context, snap) {
        final amounts = outstandingByCurrency(
          snap.data,
          baseCurrencyId: formatter.settings.currencyId,
        );
        // A currency the formatter cannot resolve (statics not loaded yet)
        // formats to '' — left out rather than drawn as a bare separator.
        final formatted = [
          for (final a in amounts ?? const <OutstandingAmount>[])
            formatter.money(a.amount, currencyId: a.currencyId),
        ].where((s) => s.isNotEmpty).toList();
        if (formatted.isEmpty) return const SizedBox.shrink();
        return OutstandingLineText(
          label: context.tr('outstanding'),
          amounts: formatted,
          fontSize: widget.fontSize,
        );
      },
    );
  }
}

/// The line itself: a muted label, then each currency's formatted amount,
/// joined with ` · `. One line, ellipsised as a whole rather than wrapped, so
/// the header never grows for it and a narrow title row never overflows.
///
/// One `Text.rich` rather than a label beside an `LtrText`: a `Row` could not
/// ellipsise the label when the pane is tight. In a right-to-left layout each
/// amount is wrapped in a left-to-right isolate instead (the `amount_paid_label`
/// recipe in `client_list_tile.dart`), so `-$1,234.50` stays one token.
class OutstandingLineText extends StatelessWidget {
  const OutstandingLineText({
    required this.label,
    required this.amounts,
    this.fontSize = 13,
    super.key,
  });

  final String label;
  final List<String> amounts;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final joined = [
      for (final a in amounts) rtl ? ltrIsolate(a) : a,
    ].join(' · ');
    return Semantics(
      container: true,
      label: '$label ${amounts.join(' · ')}',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: tokens.ink3),
            ),
            TextSpan(
              text: joined,
              style: moneyTextStyle(
                fontWeight: FontWeight.w600,
                color: tokens.ink2,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: fontSize),
      ),
    );
  }
}
