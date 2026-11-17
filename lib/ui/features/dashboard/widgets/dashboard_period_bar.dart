import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/models/value/dashboard_comparison.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/dashed_border.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/dashboard/helpers/converted_hint.dart';
import 'package:admin/ui/features/dashboard/helpers/totals_math.dart';
import 'package:admin/ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/filters/date_range_picker_button.dart';
import 'package:admin/ui/features/dashboard/widgets/filters/settings_popover.dart';
import 'package:admin/utils/formatting.dart';

/// The controls that decide what the period figures and the chart cover: the
/// date range, the currency, and whether drafts count — sitting directly above
/// the things they change.
///
/// They used to live in the page's top bar, and two of them behind a cog
/// labelled "Settings". Up there the range read as a filter on the whole page,
/// but the needs-attention band and the list panels are about *now* and ignore
/// it; and a control you have to open to learn its state is a control you
/// forget is set. Here each one shows its value at rest, and the period the
/// trends compare with is named once, beside the range it derives from.
///
/// **Wide, it reads as one sentence about the period**: the range with the
/// days it resolves to, a dashed "Compare to Oct 1 - Oct 17", the currency and
/// what it is converted to — and Include Drafts pushed to the trailing end,
/// a switch that changes what is counted rather than which period. The dashed
/// box is a label, not a control: no compare picker exists, so it takes no
/// focus, no tap and no fill, and the solid-outlined controls beside it are
/// the ones that open something. When the row is too narrow for both halves
/// the switch drops under the rest (`OverflowBar`).
///
/// **Currency is drawn only when there is a choice** — the company's totals
/// carry a second currency, or one is already selected — and never on the
/// strength of totals that have not loaded: the old dropdown fell back to
/// every currency in the catalogue until they did.
class DashboardPeriodBar extends StatelessWidget {
  const DashboardPeriodBar({
    super.key,
    required this.vm,
    required this.formatter,
    this.compact = false,
  });

  final DashboardViewModel vm;
  final Formatter formatter;

  /// The narrow arrangement: the controls on one wrapping row and what they
  /// resolve to — the windows compared, the conversion — as a caption beneath.
  ///
  /// Inline, as the wide layout has them, each control and its note is too
  /// wide to share a phone's row with the next, so the block came to three
  /// rows of 44 px to say what one row and a line can. Passed by the host
  /// rather than measured: the body already knows which layout it is.
  final bool compact;

  /// The compact caption, "Oct 1 - Oct 7 vs Sep 1 - Sep 7": the days the
  /// trends measure, and the days they measure them against. (Wide, the first
  /// half is [_currentWindow] on the range button and the second the dashed
  /// Compare label.)
  ///
  /// The first half is what a preset's name leaves unsaid — "This Month" on
  /// the 7th is seven days, set against the first seven of the month before
  /// (flutter#37 was a header that named only the window's last month). A
  /// custom range already prints its own dates on the button, so there it is
  /// only the compared window that needs saying — unless the range is still in
  /// progress: the figures then sum it only up to today
  /// (`DashboardApi.fetchTotals`), which the button's dates do not say, so the
  /// current window is named as it is for a preset.
  String _windows(BuildContext context, DashboardComparison comparison) {
    final previous = _previousWindow(comparison);
    final current = _currentWindow(comparison);
    if (current == null) {
      return context.tr('compared_with_range', {'range': previous});
    }
    return context.tr('period_vs_period', {
      'current': current,
      'previous': previous,
    });
  }

  String _previousWindow(DashboardComparison comparison) => formatter.dateRange(
    comparison.previousStart.toIso(),
    comparison.previousEnd.toIso(),
  );

  /// The days the figures sum, or null where the range button already prints
  /// them: a finished custom range shows its own dates.
  String? _currentWindow(DashboardComparison comparison) {
    if (vm.filter.range is DashboardCustomRange) {
      final (_, end) = vm.filter.resolveDates(today: vm.today);
      if (comparison.currentEnd.compareTo(end) >= 0) return null;
    }
    return formatter.dateRange(
      comparison.currentStart.toIso(),
      comparison.currentEnd.toIso(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final comparison = vm.comparison;
    final showCurrency =
        vm.filter.currencyId != kDashboardCurrencyAll ||
        hasForeignCurrency(vm.totals.data, formatter.settings.currencyId);
    final converted = convertedToBaseCaption(
      context,
      selectedCurrencyId: vm.filter.currencyId,
      totals: vm.totals.data,
      formatter: formatter,
    );
    final caption = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.ink2);
    if (compact) {
      final range = DateRangePickerButton(
        current: vm.filter.range,
        onChange: vm.setDateRange,
        formatter: formatter,
        showChevron: true,
      );
      final windows = comparison == null ? null : _windows(context, comparison);
      final notes = [?windows, ?converted].join(' · ');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: InSpacing.md(context),
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              range,
              if (showCurrency) _CurrencyButton(vm: vm),
              IncludeDraftsSwitch(vm: vm),
            ],
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(notes, style: caption),
            ),
        ],
      );
    }

    final range = DateRangePickerButton(
      current: vm.filter.range,
      onChange: vm.setDateRange,
      formatter: formatter,
      resolvedDates: comparison == null ? null : _currentWindow(comparison),
      showChevron: true,
    );
    final gap = InSpacing.md(context);
    // Two halves: the period and its currency at the start, the drafts switch
    // at the end. `OverflowBar` keeps them on one line while they fit and
    // otherwise stacks the switch under the rest — a `Row` with a spacer
    // would leave the start half to wrap in whatever the switch left it.
    return OverflowBar(
      spacing: gap,
      overflowSpacing: InSpacing.sm,
      alignment: MainAxisAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: gap,
          runSpacing: InSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            range,
            if (comparison != null)
              DashboardCompareLabel(dates: _previousWindow(comparison)),
            if (showCurrency) _CurrencyButton(vm: vm),
            // Said once, beside the control it is about: under "All
            // currencies" the figures and the chart below are the server's
            // conversion into the company's own currency. It used to be
            // repeated under each card.
            if (converted != null) Text(converted, style: caption),
          ],
        ),
        IncludeDraftsSwitch(vm: vm),
      ],
    );
  }
}

/// "Compare to Oct 1 - Oct 17": the window the trends are measured against,
/// as a dashed box that is deliberately not a control.
///
/// There is no compare picker — the previous window follows from the range —
/// so this must not look or act like one: a dashed outline and no fill where
/// the controls beside it are solid, no hover, no focus, no tap. It is plain
/// text to a screen reader, read as one phrase. The dates are a value, so
/// they stay left-to-right in an RTL locale (`LtrText`).
class DashboardCompareLabel extends StatelessWidget {
  const DashboardCompareLabel({super.key, required this.dates});

  final String dates;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.ink2);
    return MergeSemantics(
      child: DashedBorder(
        color: tokens.borderStrong,
        radius: InRadii.r2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('compare_to'), style: style),
              const SizedBox(width: 6),
              // Ellipsised rather than overflowing in a row narrower than
              // the label — only a test's em-wide glyphs get there.
              Flexible(
                child: LtrText(
                  dates,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(
                    color: tokens.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected currency, as a button that opens the (searchable) picker.
class _CurrencyButton extends StatelessWidget {
  const _CurrencyButton({required this.vm});

  final DashboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final id = vm.filter.currencyId;
    final name = id == kDashboardCurrencyAll
        ? context.tr('all_currencies')
        : (vm.availableCurrencies['$id'] ?? context.tr('currency'));
    return Builder(
      builder: (anchor) => TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: tokens.ink2,
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InRadii.r2),
            side: BorderSide(color: tokens.border),
          ),
        ),
        icon: const Icon(Icons.payments_outlined, size: 14),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2),
              child: Icon(Icons.expand_more, size: 16, color: tokens.ink3),
            ),
          ],
        ),
        onPressed: () => openDashboardCurrencyPopover(anchor, vm: vm),
      ),
    );
  }
}

/// "Include Drafts" as a label and a switch — its state visible without
/// opening anything.
///
/// The server applies it to the totals (`totals_v2`) and, from
/// invoiceninja/invoiceninja#13365, to the chart (`chart_summary_v2`, which
/// the app already sends it to) — never to the lists. So it sits with the
/// figures and is not offered as if it re-scoped the page (`BACKEND.md`).
class IncludeDraftsSwitch extends StatelessWidget {
  const IncludeDraftsSwitch({super.key, required this.vm});

  final DashboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final on = vm.filter.includeDrafts;
    return Tooltip(
      message: context.tr('count_unsent_in_totals'),
      child: _control(context, tokens, on),
    );
  }

  Widget _control(BuildContext context, InTheme tokens, bool on) {
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: Env.isTouchPrimary ? InSizes.touchTarget : 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact on a pointer so the row stays one line; the touch theme's
            // own switch size stands on touch.
            Transform.scale(
              scale: Env.isTouchPrimary ? 1 : 0.8,
              child: Switch(
                value: on,
                onChanged: vm.setIncludeDrafts,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // A larger target for a finger only: the merged node already
              // carries the switch's own toggle action.
              excludeFromSemantics: true,
              onTap: () => vm.setIncludeDrafts(!on),
              child: Text(
                context.tr('include_drafts'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
