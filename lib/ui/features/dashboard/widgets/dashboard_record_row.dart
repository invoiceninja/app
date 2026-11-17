import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_panel_grid.dart';

/// One thing a dashboard row can do. A `Future`, so the button can show that
/// it is working — the actions here fetch the record before they act on it.
typedef RecordRowCallback = Future<void> Function();

/// A button on a [DashboardRecordRow].
class RecordRowAction {
  const RecordRowAction({
    required this.icon,
    required this.tooltipKey,
    required this.onRun,
  });

  final IconData icon;

  /// What the action does, in full ("Send Reminder") — the button's tooltip
  /// and what a screen reader hears. Every action is an icon: a row is rarely
  /// wide enough for labelled buttons *and* the client's name, and where it
  /// was (one list across a whole desktop) the label sat 700 px from the name
  /// it acted on.
  final String tooltipKey;

  /// Null when this row may not do what its neighbours can. The button then
  /// keeps its place, invisible, so the column above and below stays aligned.
  final RecordRowCallback? onRun;
}

/// Vertical padding of a single-line row, top and bottom.
const double _kRowPadding = 6;

/// Row height floor. A floor, never a fixed height: a larger text size must be
/// able to grow the row.
///
/// **It is the action button's box plus the row's padding, exactly** — so a
/// row with a button and a row without are the same height. Two panels sit
/// side by side, one with buttons and one without, and a few pixels'
/// difference per row put their rows visibly out of step by the fifth.
///
/// The [stacked] form adds its first line above the action box; the same sum
/// whether or not a row has actions, so the hairlines of neighbouring columns
/// meet.
///
/// [dense] is the Compact density preference (`dashboard_density.dart` —
/// never [compact], which is the phone form): the action box and the padding
/// shrink together, so the "box plus padding, exactly" rule above holds in
/// both. The phone form keeps its two text lines and loses only padding.
double dashboardRecordRowExtent({
  required bool compact,
  bool stacked = false,
  bool dense = false,
}) {
  if (compact) return dense ? 52 : 60;
  final pad = 2 * _rowPadding(dense: dense);
  final box = dashboardRowActionExtent(dense: dense) + pad;
  if (stacked) return box + _kStackedFirstLine;
  // Compact is one line a record, as on a phone: the second lines fold away
  // (see [DashboardRecordRow]), and the row stays the button's box.
  if (dense) return box;
  // The wide form's cells are two lines (a date over "due in 3 days", an
  // amount over its "≈ base"), and a row with a second line must be no taller
  // than one without — so the floor holds two lines as well as the button.
  final twoLines = _kTwoLines + pad;
  return box > twoLines ? box : twoLines;
}

/// The wide form's two-line cell at the default text size: a first line over
/// an 11 px one, each with a set line height ([_kMainHeight], [_kSubHeight])
/// so the sum is known — the client's 13 px line is the tallest, ~32 px.
const double _kTwoLines = 32;

/// A single-line row's vertical padding: [_kRowPadding], or under Compact
/// [kDenseRowPad] with a pointer and nothing on touch, where the 44 px action
/// box already is the row.
double _rowPadding({required bool dense}) {
  if (!dense) return _kRowPadding;
  return Env.isTouchPrimary ? 0 : kDenseRowPad;
}

/// Height of a stacked row's first line at the default text size.
const double _kStackedFirstLine = 20;

/// One action button's box: the touch target on touch, a compact 32 otherwise.
/// Under Compact ([dense]) the pointer box is [kDenseActionExtent]; touch
/// never drops below the target.
double dashboardRowActionExtent({bool dense = false}) => Env.isTouchPrimary
    ? InSizes.touchTarget
    : (dense ? kDenseActionExtent : 32);

/// A record on the dashboard: which one, where it stands, how much, and what
/// can be done about it.
///
/// Every list on the dashboard draws its rows with this — the needs-attention
/// band and each panel, on both layouts — so they share one grammar:
///
/// ```
/// 0042 · Acme Ltd      12 days late · viewed Oct 2      $1,200.00   [Remind]
/// ```
///
/// It replaced six-column tables whose cells were each their own tap target
/// (about thirty tab stops a panel), whose intrinsic-width columns could not
/// shrink into a half-width card, and whose last column was a `⋮` that opened
/// no menu. Here the row is **one** target that opens the record, and anything
/// else a row can do is a button on it.
///
/// [compact] is the phone's form: two lines, the amount at the end, and at
/// most one action. It is passed by the host rather than measured, because
/// these rows sit inside grid rows that are laid out with `IntrinsicHeight`,
/// where a `LayoutBuilder` cannot be used.
///
/// The wide form is a table row, its columns lining up down the card and with
/// the panel beside it:
///
/// ```
/// 0042   Acme Ltd              Oct 2, 2026      [Sent]    £1,200.00
///        for invoice 0011      12 days late               ≈ $1,512.00
/// ```
///
/// The number is muted mono in a fixed column, so the client — what a reader
/// scans for — starts at one x on every row. Each second line is optional:
/// [clientNote], [subline] and [amountNote] are wide-only, and the phone keeps
/// two lines in all (the [subline] joins the lead there; the notes drop).
/// Under the Compact density the wide form is one line a record the same way
/// — the [subline] after the date, no notes — so its rows keep their 32 px.
///
/// [stacked] is the form for a column of the needs-attention band on a wide
/// screen:
///
/// ```
/// 0042 · Acme Ltd                    $1,200.00
/// 12 days late · viewed Oct 2           ✆ ✉ $
/// ```
///
/// The amount ends the first line and **every** action sits under it as an
/// icon, so nothing a row can do is more than a column's width from the name
/// it acts on — and the form holds from 300 px, so it does not change shape
/// as lists come and go beside it.
class DashboardRecordRow extends StatefulWidget {
  const DashboardRecordRow({
    super.key,
    required this.number,
    required this.client,
    required this.lead,
    required this.amount,
    required this.onTap,
    required this.compact,
    this.stacked = false,
    this.leadIsLate = false,
    this.fact,
    this.actions = const [],
    this.leading,
    this.clientLabel,
    this.badge,
    this.subline,
    this.sublineIsLate = false,
    this.clientNote,
    this.amountNote,
  }) : assert(!(compact && stacked), 'compact and stacked are two forms');

  /// The record's number; a dash when it has none yet.
  final String number;
  final String client;

  /// Draws the client in place of [client], for a row that holds only the
  /// client's id (a `ClientNameLabel`). It inherits the identity line's text
  /// style, so pass it no style of its own.
  final Widget? clientLabel;

  /// A status pill after [lead], at the end of its slot — for a list whose rows
  /// differ by status (the Invoices and Quotes panels' `All` tab), where the
  /// lead alone cannot say which is a draft.
  final Widget? badge;

  /// Where it stands — "12 days late", "due in 3 days", a date. Empty when the
  /// record has nothing to say here: the slot is unlabelled, so a dash in it
  /// would be a mark with no meaning.
  final String lead;

  /// Draws [lead] in the overdue tone. Red is for what is already late; a
  /// deadline still ahead stays neutral.
  final bool leadIsLate;

  /// A second fact after [lead] — "viewed Oct 2".
  final String? fact;

  /// How [lead]'s date stands relative to today — "due in 3 days", "12 days
  /// late" (`rowWhenText`). Under the lead in the wide form, after it on a
  /// phone. Null says nothing; the rules for when to say something are
  /// `invoiceRowWhen` / `quoteRowWhen`.
  final String? subline;

  /// Draws [subline] in the overdue tone.
  final bool sublineIsLate;

  /// A muted line under the client — "for invoice 0011". Wide form only. A
  /// widget, because what it names may resolve from Drift after the row
  /// draws; it inherits the note's text style, so pass it none of its own.
  final Widget? clientNote;

  /// A muted line under the amount — "≈ $1,231.00" (`approxInBaseCurrency`).
  /// Wide form only: a phone row has no room for a third figure.
  final String? amountNote;

  /// The formatted amount.
  final String amount;

  /// Opens the record.
  final VoidCallback onTap;

  final bool compact;

  /// Two lines with the amount ending the first and every action, as an icon,
  /// ending the second — see the class comment.
  final bool stacked;
  final List<RecordRowAction> actions;

  /// A widget ahead of the action buttons, in a fixed slot (the call button).
  /// First, so the buttons every row has keep one right edge whether or not
  /// this slot draws anything. Not shown in the [compact] form.
  final Widget? leading;

  @override
  State<DashboardRecordRow> createState() => _DashboardRecordRowState();
}

class _DashboardRecordRowState extends State<DashboardRecordRow> {
  /// Indices of [DashboardRecordRow.actions] currently running.
  final Set<int> _busy = {};

  Future<void> _run(int index, RecordRowCallback action) async {
    if (_busy.contains(index)) return;
    setState(() => _busy.add(index));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(index));
    }
  }

  /// The [DashboardRecordRow.stacked] form.
  Widget _stacked(
    Widget identity,
    Widget status,
    Widget money,
    List<Widget> actionWidgets,
  ) {
    final dense = dashboardDense(context);
    final extent = dashboardRowActionExtent(dense: dense);
    // An icon is a glyph centred in a larger box, so the last glyph's edge
    // sits inside the row's. The amount takes the same inset, or the figure
    // and the icons under it end on two different lines.
    final inset = actionWidgets.isEmpty
        ? 0.0
        : (extent - _actionGlyph(dense: dense)) / 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: identity),
            const SizedBox(width: InSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: money,
              ),
            ),
            SizedBox(width: inset),
          ],
        ),
        // The second line is the action box's height with or without actions:
        // a list that offers none keeps rows as tall as its neighbour's.
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: extent),
          child: Row(
            children: [
              Expanded(child: status),
              if (actionWidgets.isNotEmpty) const SizedBox(width: InSpacing.sm),
              for (var i = 0; i < actionWidgets.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                actionWidgets[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The wide form: a table row — see the class comment. [status] is the
  /// badge, if any.
  Widget _wide(
    BuildContext context, {
    required Widget? status,
    required Widget money,
    required List<Widget> actions,
  }) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final w = widget;
    // Compact: one line a record — see the class comment.
    final oneLine = dashboardDense(context);
    final noteStyle = TextStyle(
      fontSize: _kSubLine,
      height: _kSubHeight,
      color: tokens.ink3,
    );

    final number = LtrText(
      w.number.isEmpty ? '—' : w.number,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontFamily: kMonoFontFamily,
        fontSize: 12,
        color: tokens.ink3,
      ),
    );

    final clientStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13,
      height: _kMainHeight,
      color: tokens.ink,
      fontWeight: FontWeight.w500,
    );
    final clientLabel = w.clientLabel;
    final Widget client = DefaultTextStyle.merge(
      style: clientStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: clientLabel ?? Text(w.client),
    );
    final clientNote = oneLine ? null : w.clientNote;
    final Widget clientCell = clientNote == null
        ? client
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              client,
              const SizedBox(height: 1),
              DefaultTextStyle.merge(
                style: noteStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: clientNote,
              ),
            ],
          );

    final lead = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: w.lead,
            style: TextStyle(
              color: w.leadIsLate ? tokens.overdue : tokens.ink2,
              fontWeight: w.leadIsLate ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (w.fact != null)
            TextSpan(text: w.lead.isEmpty ? w.fact : ' · ${w.fact}'),
          if (oneLine && w.subline != null && w.subline!.isNotEmpty)
            TextSpan(
              text: w.lead.isEmpty && w.fact == null
                  ? w.subline
                  : ' · ${w.subline}',
              style: TextStyle(
                color: w.sublineIsLate ? tokens.overdue : tokens.ink3,
                fontWeight: w.sublineIsLate ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _kMainLine,
        height: _kMainHeight,
        color: tokens.ink2,
      ),
    );
    final subline = oneLine ? null : w.subline;
    final Widget when = subline == null || subline.isEmpty
        ? lead
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              lead,
              const SizedBox(height: 1),
              Text(
                subline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _kSubLine,
                  height: _kSubHeight,
                  color: w.sublineIsLate ? tokens.overdue : tokens.ink3,
                  fontWeight: w.sublineIsLate
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          );

    final amountNote = oneLine ? null : w.amountNote;
    // A fixed column, end-aligned, so amounts line up down the card; a long
    // one scales down rather than pushing the buttons.
    final Widget amount = SizedBox(
      width: _kAmountColumn,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: money,
          ),
          if (amountNote != null && amountNote.isNotEmpty) ...[
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: LtrText(
                amountNote,
                maxLines: 1,
                softWrap: false,
                style: moneyTextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                  color: tokens.ink3,
                  height: _kSubHeight,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Row(
      children: [
        SizedBox(width: _kNumberColumn, child: number),
        const SizedBox(width: 10),
        // Three parts client to two parts date. In a half-width card on a
        // 1280 px laptop that leaves the date about 110 px — "due in 30 days"
        // with a little to spare — and the rest to the client's name.
        Expanded(flex: 3, child: clientCell),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: when),
        // The status is a fixed column of its own between the date and the
        // amount: sized by its word, a "Past Due" pill took width from the
        // client and the date, so neither started at one x down the card.
        if (status != null) ...[
          const SizedBox(width: InSpacing.sm),
          SizedBox(
            width: _kStatusColumn,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: status,
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        amount,
        if (actions.isNotEmpty) const SizedBox(width: 12),
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          actions[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final w = widget;
    final dense = dashboardDense(context);

    final identityStyle = theme.textTheme.bodyMedium?.copyWith(
      color: tokens.ink,
    );
    final clientLabel = w.clientLabel;
    final Widget identity = clientLabel == null
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: w.number.isEmpty ? '—' : w.number,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (w.client.isNotEmpty) TextSpan(text: ' · ${w.client}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: identityStyle,
          )
        // The number keeps its width; the client gives way.
        : DefaultTextStyle.merge(
            style: identityStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Row(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: w.number.isEmpty ? '—' : w.number,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' · '),
                    ],
                  ),
                ),
                Flexible(child: clientLabel),
              ],
            ),
          );

    final statusText = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: w.lead,
            style: TextStyle(
              color: w.leadIsLate ? tokens.overdue : tokens.ink2,
              fontWeight: w.leadIsLate ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (w.fact != null)
            TextSpan(text: w.lead.isEmpty ? w.fact : ' · ${w.fact}'),
          // The wide form draws the subline on a line of its own; the phone
          // and the stacked column carry it on the lead's.
          if (w.subline != null && w.subline!.isNotEmpty)
            TextSpan(
              text: w.lead.isEmpty && w.fact == null
                  ? w.subline
                  : ' · ${w.subline}',
              style: TextStyle(
                color: w.sublineIsLate ? tokens.overdue : tokens.ink2,
                fontWeight: w.sublineIsLate ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: tokens.ink2,
        fontSize: 12.5,
      ),
    );
    final badge = w.badge;
    // The lead first, the pill at the slot's end: a pill is as wide as its
    // word, so a date placed after it started at a different x on every row.
    // Led by the date, the dates line up with each other and with the lead of
    // every other panel, and the pills form their own column by the amount.
    final Widget status = badge == null
        ? statusText
        : Row(
            children: [
              Expanded(child: statusText),
              const SizedBox(width: InSpacing.sm),
              badge,
            ],
          );

    final money = LtrText(
      w.amount,
      maxLines: 1,
      softWrap: false,
      style: moneyTextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: tokens.ink,
      ),
    );

    final shownActions = w.compact ? w.actions.take(1).toList() : w.actions;
    final actionWidgets = <Widget>[
      if (w.leading != null && !w.compact)
        SizedBox(
          width: dashboardRowActionExtent(dense: dense),
          height: dashboardRowActionExtent(dense: dense),
          child: Center(child: w.leading),
        ),
      for (var i = 0; i < shownActions.length; i++)
        _RowActionButton(
          action: shownActions[i],
          busy: _busy.contains(i),
          onPressed: shownActions[i].onRun == null
              ? null
              : () => _run(i, shownActions[i].onRun!),
        ),
    ];

    final Widget content = w.stacked
        ? _stacked(identity, status, money, actionWidgets)
        : w.compact
        ? Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // The pill goes under the amount here, not on this line:
                  // the amount's width varies by row, so a pill ending where
                  // it begins would sit at a different x on every row.
                  children: [identity, const SizedBox(height: 2), statusText],
                ),
              ),
              const SizedBox(width: InSpacing.sm),
              if (badge == null)
                money
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [money, const SizedBox(height: 2), badge],
                ),
              if (actionWidgets.isNotEmpty) const SizedBox(width: 4),
              ...actionWidgets,
            ],
          )
        : _wide(context, status: badge, money: money, actions: actionWidgets);

    return InkWell(
      onTap: w.onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: dashboardRecordRowExtent(
            compact: w.compact,
            stacked: w.stacked,
            dense: dense,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: InSpacing.lg(context),
            vertical: w.compact
                ? (dense ? InSpacing.xs : InSpacing.sm)
                : _rowPadding(dense: dense),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// The wide form's number column: "INV-0042" in 12 px mono, ellipsized past
/// that — a fixed width, so the client starts at one x on every row.
const double _kNumberColumn = 64;

/// The wide form's status column — "Past Due" at 11 px; a longer word
/// ("Partial/Deposit") scales down rather than moving the columns.
const double _kStatusColumn = 84;

/// The wide form's amount column.
const double _kAmountColumn = 104;

/// The wide form's first and second line sizes.
const double _kMainLine = 12.5;
const double _kSubLine = 11;
const double _kMainHeight = 1.3;
const double _kSubHeight = 1.2;

/// Size of an action's glyph in its icon-only form.
const double _kActionGlyph = 18;

/// [_kActionGlyph], one step smaller in the Compact pointer box.
double _actionGlyph({required bool dense}) =>
    dense && !Env.isTouchPrimary ? 16 : _kActionGlyph;

class _RowActionButton extends StatelessWidget {
  const _RowActionButton({
    required this.action,
    required this.busy,
    required this.onPressed,
  });

  final RecordRowAction action;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dense = dashboardDense(context);
    final extent = dashboardRowActionExtent(dense: dense);
    final Widget glyph = busy
        ? const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(action.icon, size: _actionGlyph(dense: dense));
    // A fixed box, whatever the button's own idea of its size: Material adds
    // to an icon button's footprint by platform density and tap-target
    // padding, and the row's height is promised above.
    final Widget boxed = SizedBox(
      width: extent,
      height: extent,
      child: IconButton(
        tooltip: context.tr(action.tooltipKey),
        onPressed: busy ? null : onPressed,
        icon: glyph,
        constraints: BoxConstraints.tightFor(width: extent, height: extent),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
    if (action.onRun != null) return boxed;
    // Not offered on this row: hold the space, show nothing, take no focus.
    return Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: boxed,
    );
  }
}

/// The rows of a dashboard list, separated by hairlines.
class DashboardRecordRows extends StatelessWidget {
  const DashboardRecordRows({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    // A panel spanning a two-column grid row flows its rows into two columns,
    // the earlier half on the start side: one row stretched across the whole
    // dashboard is the gap the Invoices & Quotes split was made to remove.
    if (!DashboardPanelCell.spansOf(context) || rows.length < 2) {
      return _column(context, rows);
    }
    final tokens = context.inTheme;
    final split = (rows.length + 1) ~/ 2;
    // The divider is an overlay, not `IntrinsicHeight`: the start column is a
    // row taller than the end one, and the line should run the full height.
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _column(context, rows.sublist(0, split))),
            const SizedBox(width: 1),
            Expanded(child: _column(context, rows.sublist(split))),
          ],
        ),
        Positioned.fill(
          child: Row(
            children: [
              const Spacer(),
              VerticalDivider(width: 1, thickness: 1, color: tokens.border),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _column(BuildContext context, List<Widget> rows) {
    final tokens = context.inTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: tokens.border),
          rows[i],
        ],
      ],
    );
  }
}
