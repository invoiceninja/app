import 'package:flutter/foundation.dart';

import 'package:admin/data/models/domain/billing/line_item_custom_fields.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/domain/product_tax_categories.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_columns.dart';

/// Which optional columns the [LineItemEditor] shows. Driven from the
/// active company's settings; built once per edit-screen mount.
///
/// The custom-field columns come from the company's `product1..4` — or
/// `task1..4` on a task table — see [customFields]. The discount column hides
/// when the company has product discounts disabled. Tax columns count is
/// 0..3 — the company's tax-rate enablement bitmask drives this.
///
/// Those flags are what a line can hold, and the phone cards and the line
/// edit dialog show all of it. The desktop table shows only
/// [desktopColumns]: the company's Invoice Design columns, as React's editor
/// does (docs/line-item-columns.md).
class LineItemColumnConfig {
  const LineItemColumnConfig({
    this.customFields = const [],
    this.taxColumnCount = 1,
    this.showDiscount = false,
    this.useTaxCategories = false,
    this.isTaskTable = false,
    this.isQuote = false,
    this.tableColumns,
    this.columnsSection,
  });

  /// The company's configured custom fields for this table, in slot order —
  /// one column on the desktop table and one field in the edit dialog each.
  /// Empty until [forCompany] resolves them, and empty for a company that
  /// defines none.
  ///
  /// The line item stored `customValue1..4` all along — a product picked
  /// from the phone picker copied its values in — but nothing ever turned a
  /// slot on, so no surface showed or edited them.
  final List<LineItemCustomField> customFields;

  /// How many of the three tax-rate slots to surface. 0 hides taxes
  /// entirely; 1..3 progressively shows tax_name1/rate1 through 3.
  final int taxColumnCount;

  /// Show the per-line discount column.
  final bool showDiscount;

  /// The company calculates line taxes itself (`company.calculate_taxes`),
  /// so a line is given a tax category (`tax_id`) rather than rates.
  ///
  /// With it on, `InvoiceItemSum::calcTaxesAutomatically` replaces every
  /// line's `tax_name1..3` / `tax_rate1..3` on save with what the line's
  /// category and the client's location call for — rates typed on the line
  /// are thrown away, which read as "saving erases my taxes". Only an
  /// Override line keeps its own ([taxCategoryKeepsManualRates]). So a line
  /// in any other category shows a category picker in the first tax slot and
  /// nothing in the others, and an Override one keeps the rate pickers
  /// (React's `useResolveInputField`, admin-portal's item editor). A blank
  /// category reads as the one the server will save — Services on an hourly
  /// line, else Physical Goods (`taxCategoryAsSaved`) — never as Override.
  /// The slots are still [taxColumnCount] wide: the server fills all three.
  ///
  /// Like React, this follows the switch alone: the server also skips the
  /// calculation for a free hosted account, a paid or cancelled invoice and
  /// a region it has no rules for, and there Override is the way to rates.
  ///
  /// A host *asks* for this; [forCompany] grants it only when the company has
  /// the switch on. A purchase order never asks — the server skips the
  /// calculation on a document without a client.
  final bool useTaxCategories;

  /// The table holds hourly (`type_id` 2) lines — the Tasks tab of
  /// `BillingDocItemsTabs`. Only the words change: [labelKey] renames Item /
  /// Unit Cost / Quantity to Service / Rate / Hours, the columns admin-portal
  /// and the server's PDF task table use for the same three fields.
  final bool isTaskTable;

  /// The table edits a quote's lines, so its product columns are the
  /// company's Quote Product Columns unless those are synced with the
  /// invoice's — see [lineItemColumnsSection]. A host declares it.
  final bool isQuote;

  /// The desktop table's columns, resolved by [forCompany] from the
  /// company's Invoice Design list ([resolveLineItemColumnVariables]). Null
  /// until a company is known — [desktopColumns] then derives them from the
  /// flags above, the full set.
  final List<LineItemTableColumn>? tableColumns;

  /// The Invoice Design tab [tableColumns] came from
  /// (`PdfVariableSection.*`), which the table's "Edit Columns" opens. Null
  /// until a company is known, and the table offers no link then.
  final String? columnsSection;

  /// The columns the desktop table draws, in order.
  ///
  /// Without a company ([tableColumns] null) this is every field a line can
  /// hold, in the table's long-standing order: Item, Description, the custom
  /// fields, Unit Cost, Quantity, Discount, the taxes, Line Total.
  List<LineItemTableColumn> get desktopColumns =>
      tableColumns ??
      [
        LineItemTableColumn.item,
        LineItemTableColumn.description,
        for (final custom in customFields)
          LineItemTableColumn.custom(custom.slot),
        LineItemTableColumn.unitCost,
        LineItemTableColumn.quantity,
        if (showDiscount) LineItemTableColumn.discount,
        for (var slot = 1; slot <= taxColumnCount.clamp(0, 3); slot++)
          LineItemTableColumn.tax(slot),
        LineItemTableColumn.lineTotal,
      ];

  /// The custom field in [slot], or null when the company defines none
  /// there.
  LineItemCustomField? customFieldAt(int slot) {
    for (final custom in customFields) {
      if (custom.slot == slot) return custom;
    }
    return null;
  }

  /// The label key to show for the column / field named [key]. A task table
  /// swaps the three product words for their hourly counterparts; every other
  /// key passes through. Resolve the result through `context.tr`, so a
  /// company's Custom Label for `service` / `rate` / `hours` wins, as it does
  /// on the PDF (`CompanyLabelsScope`).
  String labelKey(String key) {
    if (!isTaskTable) return key;
    return switch (key) {
      'item' || 'product' => 'service',
      'unit_cost' => 'rate',
      'quantity' => 'hours',
      _ => key,
    };
  }

  /// Default minimal config — qty/cost/total only, one tax column hidden.
  /// Used as a safe fallback when company settings haven't loaded yet.
  static const minimal = LineItemColumnConfig(
    taxColumnCount: 0,
    showDiscount: false,
  );

  /// What a vendor document's (purchase order's) editor wants to show. It
  /// was [minimal], which kept the per-line discount off a purchase order at
  /// every width; React's purchase-order editor shows it whenever the
  /// company enables product discounts (`useProductColumns`), and the server
  /// applies it there as on any document.
  static const vendorDocument = LineItemColumnConfig(
    taxColumnCount: 0,
    showDiscount: true,
  );

  /// This config narrowed by what [company] actually enables — the host
  /// declares what it *wants* to show, the company decides what it *may*.
  ///
  /// A null company means "not loaded yet", and keeps the host's config
  /// rather than guessing: a first frame that guessed would reflow the table
  /// the moment the row landed. The tax count was hard-coded to 1 by all five
  /// edit layouts before this existed, so a company with line-item taxes off
  /// still got Tax Name 1 / Tax Rate 1 on every row
  /// (invoiceninja/flutter#85). Clamped to the three slots the editor renders.
  ///
  /// And where the custom fields arrive: `product1..4`, or `task1..4` for a
  /// task table, the labels React and admin-portal use for the same columns.
  ///
  /// The one guess the null branch does make is [useTaxCategories] off: the
  /// common case, and the one that leaves a line's rates where they were.
  ///
  /// And where the desktop table's [tableColumns] are resolved, from the
  /// narrowed flags — so a column the company switches off never comes back
  /// through the Invoice Design list.
  LineItemColumnConfig forCompany(Company? company) {
    if (company == null) {
      return useTaxCategories ? copyWith(useTaxCategories: false) : this;
    }
    final narrowed = copyWith(
      showDiscount: showDiscount && company.enableProductDiscount,
      taxColumnCount: company.enabledItemTaxRates.clamp(0, 3),
      useTaxCategories: useTaxCategories && company.calculateTaxes,
      customFields: lineItemCustomFields(
        company.customFields,
        task: isTaskTable,
      ),
    );
    final section = lineItemColumnsSection(
      company,
      task: isTaskTable,
      quote: isQuote,
    );
    final variables = resolveLineItemColumnVariables(
      section: section,
      saved: company.settings.pdfVariables?[section],
      enabledItemTaxRates: narrowed.taxColumnCount,
      enableProductDiscount: narrowed.showDiscount,
      enableProductQuantity: company.enableProductQuantity,
      definedCustomSlots: {for (final c in narrowed.customFields) c.slot},
    );
    return narrowed.copyWith(
      tableColumns: lineItemTableColumnsFromVariables(variables),
      columnsSection: section,
    );
  }

  // Value equality: [forCompany] builds a new config on every editor build,
  // and the desktop table reuses a row's widget only while its config is
  // unchanged — by identity, no row could ever be reused.
  @override
  bool operator ==(Object other) =>
      other is LineItemColumnConfig &&
      listEquals(other.customFields, customFields) &&
      other.taxColumnCount == taxColumnCount &&
      other.showDiscount == showDiscount &&
      other.useTaxCategories == useTaxCategories &&
      other.isTaskTable == isTaskTable &&
      other.isQuote == isQuote &&
      listEquals(other.tableColumns, tableColumns) &&
      other.columnsSection == columnsSection;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(customFields),
    taxColumnCount,
    showDiscount,
    useTaxCategories,
    isTaskTable,
    isQuote,
    tableColumns == null ? null : Object.hashAll(tableColumns!),
    columnsSection,
  );

  LineItemColumnConfig copyWith({
    List<LineItemCustomField>? customFields,
    int? taxColumnCount,
    bool? showDiscount,
    bool? useTaxCategories,
    bool? isTaskTable,
    bool? isQuote,
    List<LineItemTableColumn>? tableColumns,
    String? columnsSection,
  }) => LineItemColumnConfig(
    customFields: customFields ?? this.customFields,
    taxColumnCount: taxColumnCount ?? this.taxColumnCount,
    showDiscount: showDiscount ?? this.showDiscount,
    useTaxCategories: useTaxCategories ?? this.useTaxCategories,
    isTaskTable: isTaskTable ?? this.isTaskTable,
    isQuote: isQuote ?? this.isQuote,
    tableColumns: tableColumns ?? this.tableColumns,
    columnsSection: columnsSection ?? this.columnsSection,
  );
}
