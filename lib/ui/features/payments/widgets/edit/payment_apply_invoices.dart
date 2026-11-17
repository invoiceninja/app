import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/data/repositories/invoice_repository.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/payments/view_models/payment_edit_view_model.dart';
import 'package:admin/ui/features/payments/widgets/edit/open_amount.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_allocations_section.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_invoice_checklist.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/utils/search_fold.dart';

/// Below this card width a row stacks its due date and balance under the
/// number — the slide-over panel the editor opens in is 440–560 px.
const double _kTableColumnsMinWidth = 480;

/// "Apply to invoices" on a new payment: the chosen client's open invoices
/// as a ticked table — number, due date (red once past due), balance, and
/// what this payment applies to each ticked one, editable.
///
/// It replaced a picker row per invoice and a Select Invoices dialog: the
/// payment is usually for several of them, and the user reconciling a deposit
/// needs to see them all at once (React's create screen is the same table).
/// Ticking goes through [applyInvoiceSelection], so a ticked row starts at
/// what the row pickers would have filled (the partial first, capped by what
/// is left of a fixed amount), and while the Amount is untouched it follows
/// the ticks ([PaymentEditViewModel.replacePaymentables]).
///
/// **Completeness.** It lists what the device has cached, after asking the
/// server for the client's unpaid invoices and drafts. When that answer did
/// not fit one page (`ensureUnpaidForClientLoaded` → `incomplete`) the table
/// says so, offers a filter that also searches the server, and Auto-apply
/// waits for an oldest-first fetch — "oldest" read from a page of the newest
/// would be a guess.
///
/// Rows the payment already allocates always show, even an invoice the
/// open-invoice rule would leave out (archived since, or not cached).
class PaymentApplyInvoicesSection extends StatefulWidget {
  const PaymentApplyInvoicesSection({
    super.key,
    required this.vm,
    required this.formatter,
    required this.currencyId,
  });

  final PaymentEditViewModel vm;
  final Formatter? formatter;

  /// The payment's effective currency (client → group → company, or the
  /// Currency field's pick) — every figure is formatted in it.
  final String currencyId;

  @override
  State<PaymentApplyInvoicesSection> createState() =>
      _PaymentApplyInvoicesSectionState();
}

class _PaymentApplyInvoicesSectionState
    extends State<PaymentApplyInvoicesSection> {
  late final Services _services = context.read<Services>();
  final TextEditingController _filter = TextEditingController();
  Timer? _searchDebounce;

  String? _clientId;
  Stream<List<Invoice>>? _active;
  Stream<List<Invoice>>? _unpaid;
  final Map<String, Stream<Invoice?>> _missing = {};

  /// The unpaid fetch's answer; null while it is in flight.
  UnpaidInvoicesFetch? _fetched;
  bool _draftsHaveMore = false;

  /// The client's oldest unpaid invoices are cached — fetched oldest first
  /// after an incomplete answer, so Auto-apply can trust "oldest".
  bool _oldestLoaded = false;

  PaymentEditViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _filter.dispose();
    super.dispose();
  }

  bool get _complete =>
      _fetched == UnpaidInvoicesFetch.complete && !_draftsHaveMore;

  void _bind(String clientId) {
    if (clientId == _clientId) return;
    _clientId = clientId;
    _fetched = null;
    _draftsHaveMore = false;
    _oldestLoaded = false;
    _missing.clear();
    _active = _services.invoices.watchForClient(
      companyId: vm.companyId,
      clientId: clientId,
    );
    // The archived Sent / Partial ones too, so an allocated invoice archived
    // since still has its row.
    _unpaid = _services.invoices.watchUnpaidForClient(
      companyId: vm.companyId,
      clientId: clientId,
    );
    unawaited(_load(clientId));
  }

  Future<void> _load(String clientId) async {
    final invoices = _services.invoices;
    final companyId = vm.companyId;
    final local = clientId.startsWith('tmp_');
    Future<bool> drafts() async {
      if (local) return false;
      try {
        return await invoices.ensurePageLoaded(
          companyId: companyId,
          page: 1,
          extraFilters: {
            'client_id': {clientId},
            'client_status': const {'draft'},
          },
        );
      } catch (_) {
        return false;
      }
    }

    final draftsMore = drafts();
    final unpaid = await invoices.ensureUnpaidForClientLoaded(
      companyId: companyId,
      clientId: clientId,
    );
    final more = await draftsMore;
    if (!mounted || clientId != _clientId) return;
    setState(() {
      _fetched = unpaid;
      _draftsHaveMore = more;
    });
    if (unpaid != UnpaidInvoicesFetch.incomplete || local) return;
    try {
      // The same narrowed, oldest-first fetch the record's Apply action makes
      // (`oldestUnpaidInvoice`), so the oldest are cached whatever else is.
      await invoices.ensurePageLoaded(
        companyId: companyId,
        page: 1,
        extraFilters: {
          'client_id': {clientId},
          'client_status': const {'unpaid'},
          'sort': const {'date|asc'},
        },
      );
      if (mounted && clientId == _clientId) {
        setState(() => _oldestLoaded = true);
      }
    } catch (_) {
      // Offline: Auto-apply stays off; ticking by hand still works.
    }
  }

  /// A filter on an incomplete list also asks the server — the invoice the
  /// user is typing may be one the first page didn't bring.
  void _onFilterChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    final clientId = _clientId ?? '';
    final text = _filter.text.trim();
    if (_complete ||
        text.isEmpty ||
        clientId.isEmpty ||
        clientId.startsWith('tmp_')) {
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _services.invoices
          .ensurePageLoaded(
            companyId: vm.companyId,
            page: 1,
            search: text,
            extraFilters: {
              'client_id': {clientId},
              'client_status': const {'draft', 'unpaid'},
            },
          )
          .ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    _bind(vm.draft.clientId);
    return StreamBuilder<List<Invoice>>(
      stream: _active,
      builder: (context, activeSnap) => StreamBuilder<List<Invoice>>(
        stream: _unpaid,
        builder: (context, unpaidSnap) => _build(
          context,
          active: activeSnap.data,
          unpaid: unpaidSnap.data ?? const <Invoice>[],
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context, {
    required List<Invoice>? active,
    required List<Invoice> unpaid,
  }) {
    final tokens = context.inTheme;
    final allocations = {
      for (final p in vm.draft.paymentables)
        if (p.invoiceId.isNotEmpty) p.invoiceId: p.amount,
    };
    final invoices = payableInvoicesForApply([
      ...?active,
      ...unpaid,
    ], allocated: allocations.keys.toSet());
    final known = {for (final i in invoices) i.id};
    final missing = [
      for (final id in allocations.keys)
        if (!known.contains(id)) id,
    ];
    final targets = [for (final i in invoices) _targetOf(i)];
    // What the form already allocates: an invoice's Enter Payment opens with
    // its invoice ticked, and a typed partial amount can follow it only once
    // its balance is known. Recorded, not notified — safe during build.
    final held = {
      for (final t in targets)
        if (allocations.containsKey(t.id)) t.id: t.balance,
    };
    if (held.isNotEmpty) vm.noteInvoiceOpenAmounts(held);

    final words = foldedSearchWords(_filter.text);
    final visible = words.isEmpty
        ? invoices
        : [
            for (final i in invoices)
              if (allocations.containsKey(i.id) ||
                  containsEveryWord(foldSearchText(_searchText(i)), words))
                i,
          ];
    final loading = active == null || _fetched == null;
    final incomplete =
        _fetched == UnpaidInvoicesFetch.incomplete || _draftsHaveMore;
    final showFilter =
        incomplete || invoices.length > kInvoiceChecklistFilterThreshold;
    final canAutoApply =
        (_complete || _oldestLoaded) &&
        vm.draft.amount > Decimal.zero &&
        targets.any((t) => !t.isDraft);

    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r3),
      ),
      child: Padding(
        padding: EdgeInsets.all(InSpacing.lg(context)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= _kTableColumnsMinWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The title and Auto-apply share a line where there is room;
                // in the slide-over panel the button drops below the title.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: InSpacing.sm,
                  children: [
                    Semantics(
                      header: true,
                      headingLevel: 2,
                      child: Text(
                        context.tr('apply_to_invoices'),
                        style: TextStyle(
                          color: tokens.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (_complete || _oldestLoaded)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 40),
                        ),
                        icon: const Icon(
                          Icons.auto_fix_high_outlined,
                          size: 18,
                        ),
                        label: Text(context.tr('auto_apply_oldest')),
                        onPressed: canAutoApply
                            ? () => _autoApply(targets)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (showFilter) ...[
                  TextField(
                    controller: _filter,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        FormSaveScope.maybeOf(context)?.trySubmit(),
                    decoration: InputDecoration(
                      hintText: context.tr('filter'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (incomplete) ...[
                  Text(
                    context.tr('payment_apply_more_not_shown'),
                    style: TextStyle(color: tokens.ink3, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                ],
                if (invoices.isEmpty && missing.isEmpty)
                  Text(
                    context.tr(loading ? 'loading' : 'no_open_invoices'),
                    style: TextStyle(color: tokens.ink3),
                  )
                else ...[
                  _HeaderRow(
                    columns: columns,
                    value: _selectAllState(visible, allocations),
                    onChanged: visible.isEmpty
                        ? null
                        : () => _toggleAll(visible, targets),
                  ),
                  Divider(height: 1, color: tokens.border),
                  for (final i in visible)
                    _InvoiceRow(
                      key: ValueKey('payment_apply_${i.id}'),
                      invoice: i,
                      columns: columns,
                      applied: allocations[i.id],
                      enabled: allocations.containsKey(i.id) || _roomLeft,
                      formatter: widget.formatter,
                      currencyId: widget.currencyId,
                      useCommaAsDecimalPlace:
                          widget.formatter?.settings.useCommaAsDecimalPlace ??
                          false,
                      onToggle: (on) => _toggle(i.id, on, targets),
                      onAmount: (amount) => _setAmount(i.id, amount),
                    ),
                  for (final id in missing)
                    StreamBuilder<Invoice?>(
                      key: ValueKey('payment_apply_missing_$id'),
                      stream: _missing.putIfAbsent(
                        id,
                        () => _services.invoices.watchByRealId(
                          companyId: vm.companyId,
                          id: id,
                        ),
                      ),
                      builder: (context, snap) => _InvoiceRow(
                        invoice: snap.data,
                        columns: columns,
                        applied: allocations[id],
                        enabled: true,
                        formatter: widget.formatter,
                        currencyId: widget.currencyId,
                        useCommaAsDecimalPlace:
                            widget.formatter?.settings.useCommaAsDecimalPlace ??
                            false,
                        onToggle: (on) => _toggle(id, on, targets),
                        onAmount: (amount) => _setAmount(id, amount),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  String _searchText(Invoice i) => [
    i.number,
    if (i.isDraft) context.tr('draft'),
    openAmountSearchText(
      i.balanceOrAmount,
      widget.formatter,
      widget.currencyId,
    ),
  ].join(' ');

  /// Whether another invoice can be ticked: always while no amount is fixed,
  /// else only while the amount (and the credits, which pay invoices too)
  /// has some left — a row ticked past that would apply nothing, which the
  /// server refuses.
  bool get _roomLeft {
    final fixed = vm.autoFillCap;
    if (fixed <= Decimal.zero) return true;
    return fixed + vm.creditAllocatedTotal > vm.invoiceAllocatedTotal;
  }

  bool? _selectAllState(
    List<Invoice> visible,
    Map<String, Decimal> allocations,
  ) {
    final ticked = visible.where((i) => allocations.containsKey(i.id)).length;
    if (ticked == 0) return false;
    return ticked == visible.length ? true : null;
  }

  void _commit(List<Paymentable> next, List<AllocationTarget> targets) {
    final ids = {
      for (final p in next)
        if (p.invoiceId.isNotEmpty) p.invoiceId,
    };
    vm.noteInvoiceOpenAmounts({
      for (final t in targets)
        if (ids.contains(t.id)) t.id: t.balance,
    });
    vm.replacePaymentables(next);
  }

  /// The allocations as the VM holds them now — never the build's copy, which
  /// a second tap before the next frame would read stale.
  Set<String> get _allocatedIds => {
    for (final p in vm.draft.paymentables)
      if (p.invoiceId.isNotEmpty) p.invoiceId,
  };

  void _toggle(String id, bool on, List<AllocationTarget> targets) {
    final paymentables = vm.draft.paymentables;
    if (!on) {
      _commit([
        for (final p in paymentables)
          if (p.invoiceId != id) p,
      ], targets);
      return;
    }
    _commit(
      applyInvoiceSelection(
        paymentables: paymentables,
        targets: targets,
        selected: {..._allocatedIds, id},
        paymentAmount: vm.autoFillCap,
      ),
      targets,
    );
  }

  /// Select All: tick the visible rows — in list order (oldest first) and,
  /// with a fixed amount, only while it lasts, so it fills the deposit rather
  /// than overshoot it — or, when they are all ticked or nothing more fits,
  /// untick them.
  void _toggleAll(List<Invoice> visible, List<AllocationTarget> targets) {
    final allocated = _allocatedIds;
    final byId = {for (final t in targets) t.id: t};
    final fixed = vm.autoFillCap;
    var used = vm.invoiceAllocatedTotal - vm.creditAllocatedTotal;
    final toAdd = <String>[];
    if (visible.any((i) => !allocated.contains(i.id))) {
      for (final i in visible) {
        if (allocated.contains(i.id)) continue;
        if (fixed > Decimal.zero && used >= fixed) break;
        final t = byId[i.id];
        if (t == null) continue;
        toAdd.add(i.id);
        used += t.preferredAmount;
      }
    }
    if (toAdd.isEmpty) {
      final drop = {for (final i in visible) i.id};
      _commit([
        for (final p in vm.draft.paymentables)
          if (!drop.contains(p.invoiceId)) p,
      ], targets);
      return;
    }
    _commit(
      applyInvoiceSelection(
        paymentables: vm.draft.paymentables,
        targets: targets,
        selected: {...allocated, ...toAdd},
        paymentAmount: fixed,
      ),
      targets,
    );
  }

  void _setAmount(String id, Decimal amount) {
    vm.replacePaymentables([
      for (final p in vm.draft.paymentables)
        p.invoiceId == id ? p.copyWith(amount: amount) : p,
    ]);
  }

  void _autoApply(List<AllocationTarget> targets) {
    final rows = autoApplyOldestFirst(
      targets: targets,
      amount: vm.draft.amount,
      credits: vm.creditAllocatedTotal,
    );
    vm.noteInvoiceOpenAmounts({for (final t in targets) t.id: t.balance});
    vm.setInvoiceAllocations(rows);
  }
}

AllocationTarget _targetOf(Invoice i) => AllocationTarget(
  id: i.id,
  number: i.number,
  balance: i.balanceOrAmount,
  partial: i.partial,
  date: i.date,
  isDraft: i.isDraft,
);

/// The rows of the Apply table: the client's open invoices — not deleted,
/// not archived, something still owed (a draft's amount counts, as it does
/// in the server's draft rule) — plus every invoice in [allocated], whatever
/// its state, so what the payment applies is never hidden. Oldest first, the
/// order Auto-apply pays them in.
@visibleForTesting
List<Invoice> payableInvoicesForApply(
  List<Invoice> invoices, {
  required Set<String> allocated,
}) {
  final byId = <String, Invoice>{};
  for (final i in invoices) {
    byId[i.id] = i;
  }
  return [
    for (final i in byId.values)
      if (allocated.contains(i.id) ||
          (!i.isDeleted &&
              i.archivedAt == null &&
              i.balanceOrAmount > Decimal.zero))
        i,
  ]..sort((a, b) {
    final byDate = (a.date?.toIso() ?? '').compareTo(b.date?.toIso() ?? '');
    if (byDate != 0) return byDate;
    return a.number.compareTo(b.number);
  });
}

/// Auto-apply: spread [amount] (plus [credits], which pay invoices too) over
/// [targets] oldest first — drafts skipped, as the record's Apply action
/// skips them (nothing is owed on an unsent invoice yet). Two passes: each
/// invoice's partial (its deposit due) first, then what is left of each
/// balance, so a deposit is never starved by an older invoice's full balance.
/// [targets] is already in the table's order (oldest first). Rows the amount
/// does not reach are not returned.
@visibleForTesting
List<Paymentable> autoApplyOldestFirst({
  required List<AllocationTarget> targets,
  required Decimal amount,
  Decimal? credits,
}) {
  final payable = [
    for (final t in targets)
      if (!t.isDraft && t.balance > Decimal.zero) t,
  ];
  var left = amount + (credits ?? Decimal.zero);
  final applied = <String, Decimal>{};
  for (final t in payable) {
    if (left <= Decimal.zero) break;
    if (t.partial <= Decimal.zero) continue;
    final want = t.partial < t.balance ? t.partial : t.balance;
    final take = want < left ? want : left;
    applied[t.id] = take;
    left -= take;
  }
  for (final t in payable) {
    if (left <= Decimal.zero) break;
    final already = applied[t.id] ?? Decimal.zero;
    final want = t.balance - already;
    if (want <= Decimal.zero) continue;
    final take = want < left ? want : left;
    applied[t.id] = already + take;
    left -= take;
  }
  return [
    for (final t in payable)
      if ((applied[t.id] ?? Decimal.zero) > Decimal.zero)
        Paymentable(
          invoiceId: t.id,
          amount: applied[t.id]!,
          refunded: Decimal.zero,
        ),
  ];
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.value,
    required this.onChanged,
  });

  final bool columns;
  final bool? value;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      color: context.inTheme.ink3,
      fontWeight: FontWeight.w500,
    );
    return Row(
      children: [
        Checkbox(
          tristate: true,
          value: value,
          semanticLabel: context.tr('select_all'),
          onChanged: onChanged == null ? null : (_) => onChanged!(),
        ),
        Expanded(
          child: Text(
            columns ? context.tr('invoice') : context.tr('select_all'),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (columns) ...[
          SizedBox(
            width: _kDueWidth,
            child: Text(context.tr('due_date'), style: style, maxLines: 1),
          ),
          SizedBox(
            width: _kBalanceWidth,
            child: Text(
              context.tr('balance'),
              style: style,
              maxLines: 1,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: _kGap),
        ],
        SizedBox(
          width: _kAppliedWidth,
          child: Text(
            context.tr('applied'),
            style: style,
            maxLines: 1,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

const double _kDueWidth = 104;
const double _kBalanceWidth = 104;
const double _kAppliedWidth = 112;
const double _kGap = 12;

/// One invoice: its tick, number, due date and balance, and — once ticked —
/// what the payment applies to it. [invoice] is null only for an allocated
/// invoice not cached on the device yet; the row still shows, and unticks.
class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    super.key,
    required this.invoice,
    required this.columns,
    required this.applied,
    required this.enabled,
    required this.formatter,
    required this.currencyId,
    required this.useCommaAsDecimalPlace,
    required this.onToggle,
    required this.onAmount,
  });

  final Invoice? invoice;
  final bool columns;

  /// What the payment applies to this invoice; null when it is not ticked.
  final Decimal? applied;
  final bool enabled;
  final Formatter? formatter;
  final String currencyId;
  final bool useCommaAsDecimalPlace;
  final ValueChanged<bool> onToggle;
  final ValueChanged<Decimal> onAmount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final i = invoice;
    final ticked = applied != null;
    final number = i == null
        ? '…'
        : (i.number.isEmpty ? context.tr('pending') : '#${i.number}');
    final title = [
      number,
      if (i?.isDraft ?? false) context.tr('draft'),
    ].join('  ·  ');
    final due = i?.partialDueDate ?? i?.dueDate;
    final pastDue = i?.isPastDue ?? false;
    final dueText = due == null || formatter == null
        ? ''
        : formatter!.date(due.toIso());
    final dueStyle = TextStyle(
      fontSize: 12,
      color: pastDue ? tokens.overdue : tokens.ink3,
      fontWeight: pastDue ? FontWeight.w600 : null,
    );
    final balance = i == null
        ? ''
        : formatOpenAmount(i.balanceOrAmount, formatter, currencyId);
    final balanceStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: tokens.ink2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final identity = MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onToggle(!ticked) : null,
        borderRadius: BorderRadius.circular(InRadii.r1),
        child: Row(
          children: [
            Checkbox(
              value: ticked,
              onChanged: enabled ? (v) => onToggle(v ?? false) : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LtrText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      keepRtlScript: true,
                      style: TextStyle(color: tokens.ink),
                    ),
                    if (!columns && (dueText.isNotEmpty || balance.isNotEmpty))
                      Text.rich(
                        TextSpan(
                          children: [
                            if (dueText.isNotEmpty)
                              TextSpan(text: dueText, style: dueStyle),
                            if (dueText.isNotEmpty && balance.isNotEmpty)
                              TextSpan(
                                text: '  ·  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.ink3,
                                ),
                              ),
                            if (balance.isNotEmpty)
                              TextSpan(
                                text: balance,
                                style: balanceStyle?.copyWith(fontSize: 12),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            if (columns) ...[
              SizedBox(
                width: _kDueWidth,
                child: LtrText(dueText, style: dueStyle, maxLines: 1),
              ),
              SizedBox(
                width: _kBalanceWidth,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: LtrText(balance, style: balanceStyle, maxLines: 1),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Row(
      children: [
        Expanded(child: identity),
        if (columns) const SizedBox(width: _kGap),
        SizedBox(
          width: _kAppliedWidth,
          child: ticked
              ? _AppliedField(
                  amount: applied!,
                  label: '${context.tr('applied')} $number',
                  useCommaAsDecimalPlace: useCommaAsDecimalPlace,
                  onChanged: onAmount,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// A ticked row's applied amount. Re-seeds from the allocation when it
/// changes from outside (the Amount field re-spreading it) but never under
/// the user's cursor.
class _AppliedField extends StatefulWidget {
  const _AppliedField({
    required this.amount,
    required this.label,
    required this.useCommaAsDecimalPlace,
    required this.onChanged,
  });

  final Decimal amount;

  /// Read by a screen reader — the row's number, so every field is named.
  final String label;
  final bool useCommaAsDecimalPlace;
  final ValueChanged<Decimal> onChanged;

  @override
  State<_AppliedField> createState() => _AppliedFieldState();
}

class _AppliedFieldState extends State<_AppliedField> {
  late final TextEditingController _controller = TextEditingController(
    text: decimalInputText(widget.amount),
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _AppliedField old) {
    super.didUpdateWidget(old);
    if (_focusNode.hasFocus) return;
    final typed =
        parseDecimal(
          _controller.text,
          useCommaAsDecimalPlace: widget.useCommaAsDecimalPlace,
        ) ??
        Decimal.zero;
    if (typed == widget.amount) return;
    final next = decimalInputText(widget.amount);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(isDense: true),
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        onChanged: (v) => widget.onChanged(
          parseDecimal(
                v,
                useCommaAsDecimalPlace: widget.useCommaAsDecimalPlace,
              ) ??
              Decimal.zero,
        ),
        onSubmitted: (_) => FormSaveScope.maybeOf(context)?.trySubmit(),
      ),
    );
  }
}
