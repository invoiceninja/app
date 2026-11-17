import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:logging/logging.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/repositories/list_totals_repository.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/list_totals.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/utils/bidi.dart';
import 'package:admin/utils/formatting.dart';

final _log = Logger('ListTotalsLine');

/// How old a list's cached server totals may be before opening the list asks
/// again. The dashboard refreshes the Clients / Invoices row on its own
/// schedule too, and every line refetches when a change leaves the outbox, so
/// this only matters for a session that goes straight to a list.
const Duration kListTotalsMaxAge = Duration(minutes: 5);

/// How long after a change leaves the outbox the line asks the server again —
/// the dashboard's `kAppliedChangeDelay`, so a burst of saves is one fetch.
const Duration kListTotalsRefetchDelay = Duration(milliseconds: 1500);

/// The muted "Outstanding $5,933.00 · £19,399.00" line of a money list — under
/// the title on a phone, at the end of the status strip's row on a wide
/// screen (docs/entity-lists.md § A money list's totals line).
///
/// What it sums, and under which label, is the entity's [kListTotals] entry;
/// where the figure comes from is [ListTotalsSource] — the server's exact
/// figure where it has one, else the rows Drift holds.
///
/// Draws nothing at all while the figure is unknown (nothing cached and the
/// first fetch still out, the formatter not resolved, [enabled] false) and
/// when every currency's total is zero — unknown is never zero.
class ListTotalsLine extends StatefulWidget {
  const ListTotalsLine({
    required this.source,
    required this.entityType,
    required this.companyId,
    required this.formatter,
    this.enabled = true,
    this.fontSize = 13,
    super.key,
  });

  final ListTotalsSource source;
  final EntityType entityType;
  final String companyId;

  /// Null while the list's formatter is still resolving: the line waits.
  final Formatter? formatter;

  /// False for a user the server would refuse the figure (Clients / Invoices
  /// without `view_dashboard`): nothing is fetched and nothing drawn.
  final bool enabled;

  final double fontSize;

  @override
  State<ListTotalsLine> createState() => _ListTotalsLineState();
}

class _ListTotalsLineState extends State<ListTotalsLine> {
  Stream<CurrencyTotals?>? _stream;
  StreamSubscription<int>? _outbox;
  Timer? _refetch;
  int? _lastActive;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ListTotalsLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId ||
        oldWidget.entityType != widget.entityType ||
        oldWidget.source != widget.source ||
        oldWidget.enabled != widget.enabled) {
      _bind();
    }
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _unbind() {
    _refetch?.cancel();
    _refetch = null;
    unawaited(_outbox?.cancel());
    _outbox = null;
    _lastActive = null;
  }

  /// The stream is held, not built in `build` — a Drift watch replays on
  /// every re-subscribe, which would flash the line on each rebuild.
  void _bind() {
    _unbind();
    if (!widget.enabled || !kListTotals.containsKey(widget.entityType)) {
      _stream = null;
      return;
    }
    _stream = widget.source.watch(widget.entityType, widget.companyId);
    _fetch(maxAge: kListTotalsMaxAge);
    // A change leaving the outbox is when the server's figure moves; nothing
    // in Drift tells a cached server row so. A drop in the active count, not
    // the pending one, which also falls when a row merely goes in flight.
    _outbox = widget.source.watchOutboxActive(widget.companyId).listen((n) {
      final last = _lastActive;
      _lastActive = n;
      if (last == null || n >= last) return;
      _refetch?.cancel();
      _refetch = Timer(kListTotalsRefetchDelay, () => _fetch(maxAge: null));
    });
  }

  void _fetch({required Duration? maxAge}) {
    unawaited(
      widget.source
          .refresh(widget.entityType, widget.companyId, maxAge: maxAge)
          .catchError((Object e) {
            // Offline, a company switch under the fetch, a server error: the
            // line keeps what is cached, or falls back to the local sum.
            _log.fine('List totals not refreshed: $e');
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    final formatter = widget.formatter;
    final spec = kListTotals[widget.entityType];
    if (stream == null || formatter == null || spec == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<CurrencyTotals?>(
      stream: stream,
      builder: (context, snap) {
        final amounts = orderedCurrencyTotals(
          snap.data,
          baseCurrencyId: formatter.settings.currencyId,
        );
        // A currency the formatter cannot resolve (statics not loaded yet)
        // formats to '' — left out rather than drawn as a bare separator.
        final formatted = [
          for (final a in amounts ?? const <CurrencyAmount>[])
            formatter.money(a.amount, currencyId: a.currencyId),
        ].where((s) => s.isNotEmpty).toList();
        if (formatted.isEmpty) return const SizedBox.shrink();
        return TotalsLineText(
          label: context.tr(spec.labelKey),
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
class TotalsLineText extends StatelessWidget {
  const TotalsLineText({
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
