import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/product.dart';
import 'package:admin/domain/product_tax_categories.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/custom_field_detail_rows.dart';
import 'package:admin/ui/core/detail/record_details_cards.dart';
import 'package:admin/ui/core/detail/record_profile_layout.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/utils/external_url.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/detail_row_columns.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/formatting.dart';

/// A product's reference fields. Always shown, above the tabs.
///
/// Details and Taxes side by side as equal cards on a wide window and
/// stacked below it. A product with no taxes splits Details in two instead —
/// Details and Additional Info (`recordDetailsCards`) — so it is not one
/// full-width card running its rows in two columns. What the product sells for, what it costs
/// and how much is in stock are on the standing card; its description is the
/// line under its name.
///
/// **A card exists only when it has a row.** Each is built from the list it
/// draws ([detailsRows], [taxRows]), so there is no second predicate to drift
/// from it: the grid this replaced kept `hasInventory`, `hasTaxes` and
/// `_hasAnyCustomValue` beside the cards they guarded, and the last counted a
/// custom value with no configured label — a titled card with nothing in it.
class ProductDetailProfile extends StatelessWidget {
  const ProductDetailProfile({
    super.key,
    required this.product,
    required this.company,
    this.formatter,
  });

  final Product product;

  /// For the custom-field labels, the tax slots the company uses and whether
  /// it tracks inventory. Null while it loads.
  final Company? company;

  /// For dates and date-typed custom fields. Null (still loading) leaves the
  /// created / updated rows out.
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    final facts = factRows(context, product, company);
    final bookkeeping = bookkeepingRows(context, product, company, formatter);
    final taxes = taxRows(context, product);
    return RecordProfileLayout(
      lead: [
        // Beside Taxes, Details keeps every row; alone, it splits in two
        // rather than run one card's rows in two columns.
        ...recordDetailsCards(
          context,
          facts: facts,
          bookkeeping: bookkeeping,
          split: taxes.isEmpty,
        ),
        if (taxes.isNotEmpty)
          DashboardCardShell(
            title: context.tr('taxes'),
            child: DetailRowColumns(children: taxes),
          ),
      ],
    );
  }

  /// The Details rows, in the edit form's order: [factRows] then
  /// [bookkeepingRows]. Every field the form can set and the standing card
  /// does not already show has a row here, when it is set.
  @visibleForTesting
  static List<Widget> detailsRows(
    BuildContext context,
    Product p,
    Company? company,
    Formatter? formatter,
  ) => [
    ...factRows(context, p, company),
    ...bookkeepingRows(context, p, company, formatter),
  ];

  /// What the product is: the quantities a line starts with, its image, its
  /// stock settings.
  @visibleForTesting
  static List<Widget> factRows(
    BuildContext context,
    Product p,
    Company? company,
  ) {
    final imageUri = _parseUrl(p.productImage);
    final tracksInventory = company?.trackInventory ?? false;
    return [
      // The quantity a new line item starts with. One is what every product
      // starts at and what a line gets anyway, so only another value is news.
      if (p.quantity != Decimal.zero && p.quantity != Decimal.one)
        DetailInfoRow(
          // "Default Quantity", not the edit form's bare "Quantity": here it
          // sits on a screen that also shows how many are in stock.
          label: context.tr('default_quantity'),
          value: '${p.quantity}',
          monospace: true,
        ),
      if (p.maxQuantity != Decimal.zero)
        DetailInfoRow(
          label: context.tr('max_quantity'),
          value: '${p.maxQuantity}',
          monospace: true,
        ),
      if (p.productImage.isNotEmpty)
        DetailInfoRow(
          label: context.tr('product_image'),
          value: p.productImage,
          onTap: imageUri == null
              ? null
              : () => openExternalUrl(context, imageUri.toString()),
        ),
      // The stock *settings*; the stock itself is on the standing card. Yes
      // or No where the company tracks inventory — there "No" is an answer —
      // and otherwise only a setting somebody turned on.
      if (tracksInventory || p.stockNotification)
        DetailInfoRow(
          label: context.tr('stock_notifications'),
          value: context.tr(p.stockNotification ? 'yes' : 'no'),
          copyable: false,
        ),
      if (p.stockNotificationThreshold != Decimal.zero)
        DetailInfoRow(
          label: context.tr('notification_threshold'),
          value: '${p.stockNotificationThreshold}',
          monospace: true,
        ),
    ];
  }

  /// What is kept about the product: who it is assigned to, the custom
  /// fields, created and updated.
  @visibleForTesting
  static List<Widget> bookkeepingRows(
    BuildContext context,
    Product p,
    Company? company,
    Formatter? formatter,
  ) => [
    if (p.assignedUserId.isNotEmpty)
      DetailInfoRow(
        label: context.tr('assigned_user'),
        value: '',
        copyable: false,
        child: UserNameLabel(userId: p.assignedUserId),
      ),
    ..._customRows(context, p, company, formatter),
    ...recordTimestampRows(
      context,
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      formatter: formatter,
    ),
  ];

  /// The Taxes rows: the tax category, then each tax that is set.
  ///
  /// A slot the company has enabled but this product leaves blank has no
  /// row — it used to print a dash, on a screen that omits every other blank.
  @visibleForTesting
  static List<Widget> taxRows(BuildContext context, Product p) {
    final categoryKey = kProductTaxCategories[p.taxId];
    final slots = [
      (name: p.taxName1, rate: p.taxRate1),
      (name: p.taxName2, rate: p.taxRate2),
      (name: p.taxName3, rate: p.taxRate3),
    ];
    return [
      if (p.taxId.isNotEmpty)
        DetailInfoRow(
          label: context.tr('tax_category'),
          value: categoryKey == null ? p.taxId : context.tr(categoryKey),
          copyable: false,
        ),
      // Labelled by the tax's own name — "VAT  20%" — as an expense's Taxes
      // card labels its lines; an unnamed one falls back to its slot.
      for (var i = 0; i < slots.length; i++)
        if (slots[i].name.isNotEmpty || slots[i].rate != Decimal.zero)
          DetailInfoRow(
            label: slots[i].name.isEmpty
                ? context.tr(_kTaxRateKeys[i])
                : slots[i].name,
            value: '${slots[i].rate}%',
            monospace: true,
            copyable: false,
          ),
    ];
  }

  /// The configured, type-formatted custom-field rows. A slot renders only
  /// when the company has a label for it AND the product has a value.
  static List<Widget> _customRows(
    BuildContext context,
    Product p,
    Company? company,
    Formatter? formatter,
  ) {
    final values = [
      p.customValue1,
      p.customValue2,
      p.customValue3,
      p.customValue4,
    ];
    if (company == null || values.every((v) => v.isEmpty)) return const [];
    final rows = customFieldDetailRows(
      company: company,
      prefix: 'product',
      values: values,
      formatter: formatter,
      yes: context.tr('yes'),
      no: context.tr('no'),
    );
    return [
      for (final r in rows) DetailInfoRow(label: r.label, value: r.value),
    ];
  }
}

/// The label for a tax with no name of its own, by slot.
const List<String> _kTaxRateKeys = ['tax_rate1', 'tax_rate2', 'tax_rate3'];

/// A user-entered image address as a launchable URI, or null when it is not
/// an http(s) one — the row then shows it as plain, copyable text.
Uri? _parseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri;
}
