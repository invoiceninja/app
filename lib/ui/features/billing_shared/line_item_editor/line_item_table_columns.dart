import 'package:flutter/foundation.dart';

import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/static/pdf_catalogs.dart';

/// What one column of the desktop line-item table edits or shows.
enum LineItemTableColumnKind {
  item,
  description,
  unitCost,
  quantity,
  discount,

  /// One of the three tax slots ([LineItemTableColumn.slot] 1..3).
  tax,
  taxAmount,
  grossLineTotal,
  lineTotal,

  /// One of the four custom-field slots ([LineItemTableColumn.slot] 1..4).
  custom,
}

/// One column of the desktop line-item table, in the order the table draws
/// them (`LineItemColumnConfig.desktopColumns`).
@immutable
class LineItemTableColumn {
  const LineItemTableColumn._(this.kind, [this.slot = 0]);

  const LineItemTableColumn.tax(int slot)
    : this._(LineItemTableColumnKind.tax, slot);

  const LineItemTableColumn.custom(int slot)
    : this._(LineItemTableColumnKind.custom, slot);

  static const item = LineItemTableColumn._(LineItemTableColumnKind.item);
  static const description = LineItemTableColumn._(
    LineItemTableColumnKind.description,
  );
  static const unitCost = LineItemTableColumn._(
    LineItemTableColumnKind.unitCost,
  );
  static const quantity = LineItemTableColumn._(
    LineItemTableColumnKind.quantity,
  );
  static const discount = LineItemTableColumn._(
    LineItemTableColumnKind.discount,
  );
  static const taxAmount = LineItemTableColumn._(
    LineItemTableColumnKind.taxAmount,
  );
  static const grossLineTotal = LineItemTableColumn._(
    LineItemTableColumnKind.grossLineTotal,
  );
  static const lineTotal = LineItemTableColumn._(
    LineItemTableColumnKind.lineTotal,
  );

  final LineItemTableColumnKind kind;

  /// 1-based tax or custom-field slot; 0 for every other kind.
  final int slot;

  /// A stable id for the column's widgets — the table keys each cell on it,
  /// so a column moving (the company row landing, a settings change) moves
  /// its cell's state with it instead of re-pairing cells by position.
  String get id => switch (kind) {
    LineItemTableColumnKind.tax => 'tax_$slot',
    LineItemTableColumnKind.custom => 'custom_$slot',
    _ => kind.name,
  };

  @override
  bool operator ==(Object other) =>
      other is LineItemTableColumn && other.kind == kind && other.slot == slot;

  @override
  int get hashCode => Object.hash(kind, slot);

  @override
  String toString() => 'LineItemTableColumn($id)';
}

/// Which Invoice Design list a table's columns come from — the settings tab
/// (`/settings/invoice_design/<section>`) "Edit Columns" opens.
///
/// A task table reads Task Columns; a quote's product table reads Quote
/// Product Columns unless the company keeps them in sync with the invoice's
/// (`sync_invoice_quote_columns`, on unless set off — the server's default);
/// everything else reads Product Columns. React's editors pick the same way
/// (`quotes/edit/Edit.tsx`).
String lineItemColumnsSection(
  Company? company, {
  required bool task,
  required bool quote,
}) {
  if (task) return PdfVariableSection.taskColumns;
  if (quote && !(company?.settings.syncInvoiceQuoteColumns ?? true)) {
    return PdfVariableSection.productQuoteColumns;
  }
  return PdfVariableSection.productColumns;
}

/// The editor's column variables (`$product.item`, `$task.rate`, …) for a
/// company's saved Invoice Design list [section] ([lineItemColumnsSection]) — a port of React's
/// `useProductColumns` / `useTaskColumns` (`invoices/common/hooks/`), which
/// decide what React's invoice editor shows. The PDF's list is the starting
/// point and its order is kept; the editor then forces in what a line needs
/// to be edited at all:
///
/// 1. Item (Service) leads unless the list places it.
/// 2. An empty list also gets Description.
/// 3. Unit Cost (Rate) and Quantity (Hours) are appended when missing.
/// 4. `tax` becomes one column per enabled item tax rate, at its place — or
///    at the end when the list doesn't name it.
/// 5. Discount is dropped when product discounts are off, appended when on.
/// 6. Every custom field the company defines is shown — appended when the
///    list doesn't place it — and one it doesn't define is dropped.
/// 7. A product table drops Quantity when the company's "Show Product
///    Quantity" (`enable_product_quantity`) is off; a task table keeps Hours.
/// 8. Tax Amount, Gross Line Total and Line Total, when listed, move to the
///    end in that order.
/// 9. Net Cost is a PDF-only column.
///
/// [saved] null — the section absent from the settings — reads as the
/// catalog default, as the settings screen shows it and the server's PDF
/// fills it (`PdfConfiguration::setPdfVariables`); an empty list is the user
/// having cleared it, and takes React's empty-list path.
///
/// Two departures from React: a variable listed twice is kept once (two
/// cells cannot share one field's controller), and a variable with no line
/// field behind it (`tags`) is left to the PDF — React draws an input that
/// writes a property no line item has.
List<String> resolveLineItemColumnVariables({
  required String section,
  required List<String>? saved,
  required int enabledItemTaxRates,
  required bool enableProductDiscount,
  required bool enableProductQuantity,
  required Set<int> definedCustomSlots,
}) {
  final task = section == PdfVariableSection.taskColumns;
  final ns = task ? r'$task' : r'$product';
  String v(String field) => '$ns.$field';
  final source =
      saved ?? kPdfVariableSections[section]?.defaultSelected ?? const [];

  final columns = <String>[];
  for (final variable in source) {
    if (!columns.contains(variable)) columns.add(variable);
  }
  final listedCount = columns.length;

  final item = v(task ? 'service' : 'item');
  final unitCost = v(task ? 'rate' : 'unit_cost');
  final quantity = v(task ? 'hours' : 'quantity');

  if (!columns.contains(item)) columns.insert(0, item);
  if (listedCount == 0) columns.add(v('description'));
  if (!columns.contains(unitCost)) columns.add(unitCost);
  if (!columns.contains(quantity)) columns.add(quantity);

  final taxCount = enabledItemTaxRates.clamp(0, 3);
  final taxAt = columns.indexOf(v('tax'));
  columns.insertAll(taxAt < 0 ? columns.length : taxAt, [
    for (var slot = 1; slot <= taxCount; slot++) v('tax_rate$slot'),
  ]);
  columns.remove(v('tax'));

  if (!enableProductDiscount) {
    columns.remove(v('discount'));
  } else if (!columns.contains(v('discount'))) {
    columns.add(v('discount'));
  }

  final customPrefix = task ? 'task' : 'product';
  for (var slot = 1; slot <= 4; slot++) {
    final custom = v('$customPrefix$slot');
    final defined = definedCustomSlots.contains(slot);
    if (defined && !columns.contains(custom)) columns.add(custom);
    if (!defined) columns.remove(custom);
  }

  if (!task && !enableProductQuantity) columns.remove(quantity);

  for (final last in ['tax_amount', 'gross_line_total', 'line_total']) {
    if (columns.remove(v(last))) columns.add(v(last));
  }

  if (!task) columns.remove(v('net_cost'));
  return columns;
}

/// The table columns for [variables] (from [resolveLineItemColumnVariables]),
/// in their order. A variable the table has no cell for is skipped.
List<LineItemTableColumn> lineItemTableColumnsFromVariables(
  List<String> variables,
) {
  final out = <LineItemTableColumn>[];
  for (final variable in variables) {
    final dot = variable.indexOf('.');
    if (dot < 0) continue;
    final field = variable.substring(dot + 1);
    final column = switch (field) {
      'item' || 'service' => LineItemTableColumn.item,
      'description' => LineItemTableColumn.description,
      'unit_cost' || 'rate' => LineItemTableColumn.unitCost,
      'quantity' || 'hours' => LineItemTableColumn.quantity,
      'discount' => LineItemTableColumn.discount,
      'tax_rate1' => const LineItemTableColumn.tax(1),
      'tax_rate2' => const LineItemTableColumn.tax(2),
      'tax_rate3' => const LineItemTableColumn.tax(3),
      'tax_amount' => LineItemTableColumn.taxAmount,
      'gross_line_total' => LineItemTableColumn.grossLineTotal,
      'line_total' => LineItemTableColumn.lineTotal,
      'product1' || 'task1' => const LineItemTableColumn.custom(1),
      'product2' || 'task2' => const LineItemTableColumn.custom(2),
      'product3' || 'task3' => const LineItemTableColumn.custom(3),
      'product4' || 'task4' => const LineItemTableColumn.custom(4),
      _ => null,
    };
    if (column != null && !out.contains(column)) out.add(column);
  }
  return out;
}
