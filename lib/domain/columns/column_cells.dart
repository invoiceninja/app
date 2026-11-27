import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/color_hex.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/formatter_scope.dart';
import 'package:admin/ui/core/widgets/link_text.dart';
import 'package:admin/utils/notes_html.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/domain/payment_types.dart';

/// Shared rendering helpers for `ColumnDefinition<T>.cellBuilder`.
///
/// Every entity's list table renders one of: a text cell, a money cell, a
/// date cell, or an em-dash for empty. The widget anatomy is identical
/// across entities — only the field accessor differs — so the cell
/// renderers live here and each entity's columns file passes its domain
/// field through.
///
/// NOTE: although this lives under `lib/domain/`, it is a **UI-layer
/// helper** — it imports `package:material_ui/material_ui.dart`, returns
/// `Widget`s, and is only ever invoked from the list render path. The
/// `lib/domain/columns/` location is pre-existing misfiling; importing
/// `lib/ui/...` from here is therefore not a new layering regression.
///
/// [cellMoney] formats through the active-company [Formatter] (per-client
/// → company currency cascade + Euro override) when a [FormatterScope] is
/// in the tree — which the list scaffold provides for money-bearing
/// entities. Without a scope (non-financial screens, or the formatter
/// still resolving on a cold start) it falls back to the cached
/// locale-only `NumberFormat`. Entities whose row carries its own
/// currency (`client`/`payment`/`vendor`/`expense`/`recurring_expense`/
/// `bank_transaction`) pass it through the matching cascade slot; billing
/// docs (`invoice`/`quote`/`credit`/…) carry no row currency and so
/// format with the company default — correct symbol/precision, just not
/// per-client.

/// Empty / placeholder cell. Renders an em-dash in muted ink.
Widget cellEmpty() => const CellText(value: '—', muted: true);

/// Plain text cell. Empty strings render as [cellEmpty]. Set [bold] for the
/// identity / name column.
Widget cellText(String value, {bool bold = false}) {
  if (value.isEmpty) return cellEmpty();
  return CellText(value: value, bold: bold);
}

/// Notes cell for one of the HTML-bearing fields (`public_notes`,
/// `private_notes`, `terms`, `footer`).
///
/// Those carry markup — written here, by the React client, or by the pre-v5
/// apps — and a table cell has one line to spend, so the markup is flattened
/// to its words. Without this the cell printed `<p>` tags at the user, which
/// it already did for anything authored on the web.
///
/// A cell shows one line, so a longer value also gets the whole text, line
/// breaks kept, in a tooltip — a task described in several lines (a category
/// line, then the detail) was otherwise unreadable past its first words.
Widget cellNotes(String value) {
  final line = plainTextFromHtml(value, singleLine: true);
  if (line.isEmpty) return cellEmpty();
  final full = plainTextFromHtml(value);
  if (full == line && line.length <= 30) return CellText(value: line);
  return Tooltip(
    message: full,
    waitDuration: InTooltip.labelDelay,
    child: CellText(value: line),
  );
}

/// Currency cell — resolves [currencyId] to its ISO code (e.g. "USD") from the
/// static catalog; falls back to the raw id when the catalog lacks it (or hasn't
/// loaded yet). Static data, so a synchronous read is fine — no watch needed.
Widget cellCurrency(BuildContext context, String currencyId) {
  if (currencyId.isEmpty) return cellEmpty();
  final code = context.read<Services>().statics.currencies[currencyId]?.code;
  return cellText(code == null || code.isEmpty ? currencyId : code);
}

/// Payment-type cell — resolves [typeId] to its name (e.g. "Credit Card") from
/// the static catalog; falls back to the raw id.
Widget cellPaymentType(BuildContext context, String typeId) {
  if (typeId.isEmpty) return cellEmpty();
  final name = paymentTypeLabel(
    Localization.of(context),
    typeId,
    context.read<Services>().statics.paymentTypes[typeId]?.name ?? '',
  );
  return cellText(name.isEmpty ? typeId : name);
}

/// Linked text cell. Renders the value with the same typographic weight as
/// [cellText] but reveals an underline + pointer cursor on hover and fires
/// [onTap] when clicked. Used on the Number cell to open the row's
/// full-width **view** page (editing is reached from the view's Edit
/// button). [LinkText] absorbs the tap with an opaque hit-test so the
/// surrounding row [InkWell] does not also fire its slide-over preview.
/// Wrapped in a [Tooltip] so the two distinct click targets in one row
/// (link = full view page, row = preview pane) are discoverable.
Widget cellLink(
  BuildContext context,
  String value, {
  required VoidCallback onTap,
  bool bold = false,
}) {
  if (value.isEmpty) return cellEmpty();
  final tokens = context.inTheme;
  return Tooltip(
    message: context.tr('view'),
    waitDuration: InTooltip.hintDelay,
    child: LinkText(
      label: value,
      onTap: onTap,
      style: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: tokens.ink,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// Cached `NumberFormat` instances for [cellMoney]. `NumberFormat` is an
/// expensive `intl` object (it parses locale pattern tables on
/// construction) but is safe to reuse across calls — formatting is
/// stateless. Only two shapes exist (2-digit vs whole-unit), so two lazy
/// singletons replace the per-cell allocation that previously cost
/// ~6-8 instances per row × 50 visible rows per scroll frame.
final NumberFormat _moneyCentsFormat = NumberFormat.decimalPattern()
  ..minimumFractionDigits = 2
  ..maximumFractionDigits = 2;
final NumberFormat _moneyWholeFormat = NumberFormat.decimalPattern()
  ..minimumFractionDigits = 0
  ..maximumFractionDigits = 0;

/// Cached medium-date `DateFormat` per locale string. Keyed by locale
/// because the pattern is locale-dependent; in practice the app runs one
/// active locale so this map holds a single entry. Same reuse rationale
/// as the money formatters above.
final Map<String, DateFormat> _dateFormatCache = {};

/// Decimal money cell. Zero renders as an em-dash so the column reads as
/// "no activity" rather than a wall of zeros (cell convention — kept even
/// though `Formatter.money` would emit `''`).
///
/// When a [FormatterScope] is present the value is formatted through the
/// company [Formatter] (currency symbol/code + the currency's own
/// precision + the per-client→company cascade). Callers pass the row's
/// currency through the cascade slot that matches the entity, exactly as
/// the mobile tiles do: [clientCurrencyId] for client-owned rows,
/// [vendorCurrencyId] for vendor-owned, [currencyId] for rows that carry
/// an explicit currency (payment/expense/bank-transaction); billing docs
/// pass none and format with the company default.
///
/// Without a scope it falls back to the cached locale-only `NumberFormat`
/// — [cents] then controls fraction digits (true = always 2;
/// false = whole-unit, dropping trailing zeros to match the legacy
/// admin-portal). With a scope the currency's precision governs and
/// [cents] is moot.
Widget cellMoney(
  Decimal value,
  BuildContext context, {
  bool cents = true,
  String? clientCurrencyId,
  String? vendorCurrencyId,
  String? currencyId,
}) {
  if (value == Decimal.zero) {
    return const MoneyCellText(text: '—', isZero: true);
  }
  final formatter = FormatterScope.maybeOf(context);
  final text = formatter?.money(
    value,
    clientCurrencyId: clientCurrencyId,
    vendorCurrencyId: vendorCurrencyId,
    currencyId: currencyId,
  );
  return MoneyCellText(
    text: (text != null && text.isNotEmpty)
        ? text
        : (cents ? _moneyCentsFormat : _moneyWholeFormat).format(
            value.toDouble(),
          ),
    isZero: false,
  );
}

/// Date cell. Honors the company `date_format_id` via the ambient
/// [FormatterScope] (same seam [cellMoney] uses) — rendering `DateFormat`
/// directly here ignored the user's configured format on every list table
/// while detail/edit screens honored it. Falls back to the locale's medium
/// pattern (`Jan 5, 2026`) when no formatter is in scope. Caller decides
/// whether to render `cellEmpty()` for a null/missing date.
///
/// [overdue] draws the date in the `overdue` ink — a due date the row is past
/// (the column's own caller decides, through the entity's past-due predicate).
/// The cell still shows only the date; whatever says how late belongs in a
/// tooltip around it, never in the cell.
Widget cellDate(DateTime value, BuildContext context, {bool overdue = false}) {
  final local = value.toLocal();
  final formatted = FormatterScope.maybeOf(context)?.date(
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}',
  );
  if (formatted != null && formatted.isNotEmpty) {
    return CellText(value: formatted, overdue: overdue);
  }
  final localeKey = Localizations.localeOf(context).toString();
  final fallback = _dateFormatCache[localeKey] ??= DateFormat.yMMMd(localeKey);
  return CellText(value: fallback.format(local), overdue: overdue);
}

/// Colour cell — a small swatch plus the stored hex. Parses through the
/// canonical [parseHexColor] (never a second inline parser); an empty or
/// malformed value renders as [cellEmpty] rather than an invisible swatch.
Widget cellColor(String hex) {
  if (hex.isEmpty) return cellEmpty();
  final color = parseHexColor(hex);
  if (color == null) return cellEmpty();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(InRadii.r1),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(child: CellText(value: hex)),
    ],
  );
}

/// Canonical string for a money cell, used by `valueBuilder` to drive the
/// hover-copy affordance. Zero collapses to null so copy is suppressed.
String? cellMoneyValue(Decimal v) => v == Decimal.zero ? null : v.toString();

/// Canonical string for a plain-text cell, used by `valueBuilder` to drive
/// the hover-copy affordance. Empty strings collapse to null.
String? cellNonZeroString(String s) => s.isEmpty ? null : s;

/// Plain text widget tuned for table cells: 13px / 1.2 line-height /
/// elided, with muted-ink support for the em-dash placeholder. Laid out
/// left-to-right unless it holds Arabic or Hebrew — dates, numbers, phone
/// numbers and document numbers read the same in every language ([LtrText]).
class CellText extends StatelessWidget {
  const CellText({
    required this.value,
    this.bold = false,
    this.muted = false,
    this.overdue = false,
    super.key,
  });

  final String value;
  final bool bold;
  final bool muted;

  /// The `overdue` ink — see [cellDate].
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return LtrText(
      value,
      keepRtlScript: true,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: muted
            ? tokens.ink4
            : overdue
            ? tokens.overdue
            : tokens.ink,
      ),
    );
  }
}

/// Money widget tuned for table cells: tabular figures ([moneyTextStyle]) so
/// digits align vertically across rows, left-to-right in every language.
class MoneyCellText extends StatelessWidget {
  const MoneyCellText({
    required this.text,
    required this.isZero,
    this.strong = false,
    this.overdue = false,
    super.key,
  });

  final String text;
  final bool isZero;

  /// The `overdue` red — a client balance with a past-due invoice behind it
  /// (`clientBalanceCell`). Set by a column's `cellBuilder`, never by
  /// [cellMoney].
  final bool overdue;

  /// Weight 600 — a column's one figure that asks for attention (the Clients
  /// list's balance owed). Set by a column's `cellBuilder`, never by
  /// [cellMoney], so every other money column keeps its weight.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return LtrText(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: moneyTextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: strong && !isZero ? FontWeight.w600 : null,
        color: isZero
            ? tokens.ink3
            : overdue
            ? tokens.overdue
            : tokens.ink,
      ),
    );
  }
}
