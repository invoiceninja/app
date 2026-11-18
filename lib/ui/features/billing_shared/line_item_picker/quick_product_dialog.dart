import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/product.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/fold_geometry.dart';

/// The few fields a product needs to be added to a document straight from the
/// Add-items picker (invoiceninja/ui#3384): its key — prefilled with what the
/// user searched for — a price and a description. Anything more belongs on
/// the product screen. Returns the draft to create, or null on cancel.
///
/// A key-only create (what the desktop line-item cell does) would land a $0
/// line on the document and a priceless entry in the catalog, which is why
/// this asks for the price up front.
///
/// On a [vendorDoc] (a purchase order) the amount is what the product costs
/// to buy, so the field reads Cost and is saved as the product's cost — the
/// figure a purchase order fills — leaving the sale price for the user to set.
///
/// The other figure is offered beside it, so the product needn't be opened
/// again afterwards (beta feedback): on a sales document the purchase Cost,
/// when the company tracks product cost (`enable_product_cost`, the same gate
/// as the product form); on a purchase order the sale Price, always.
Future<Product?> showQuickProductDialog(
  BuildContext context, {
  required String initialKey,
  String? companyId,
  bool useCommaAsDecimalPlace = false,
  bool vendorDoc = false,
}) async {
  var offerSecondary = vendorDoc;
  if (!vendorDoc && companyId != null) {
    final company = await context.read<Services>().company.get(companyId);
    offerSecondary = company?.enableProductCost ?? false;
  }
  if (!context.mounted) return null;
  return showDialog<Product>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    builder: (_) => _QuickProductDialog(
      initialKey: initialKey,
      useCommaAsDecimalPlace: useCommaAsDecimalPlace,
      vendorDoc: vendorDoc,
      offerSecondary: offerSecondary,
    ),
  );
}

class _QuickProductDialog extends StatefulWidget {
  const _QuickProductDialog({
    required this.initialKey,
    required this.useCommaAsDecimalPlace,
    required this.vendorDoc,
    required this.offerSecondary,
  });

  final String initialKey;
  final bool useCommaAsDecimalPlace;
  final bool vendorDoc;

  /// Whether the other amount (Cost on a sales document, Price on a purchase
  /// order) is asked for too.
  final bool offerSecondary;

  @override
  State<_QuickProductDialog> createState() => _QuickProductDialogState();
}

class _QuickProductDialogState extends State<_QuickProductDialog> {
  late final TextEditingController _key = TextEditingController(
    text: widget.initialKey,
  );
  final TextEditingController _price = TextEditingController();
  final TextEditingController _secondary = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  bool get _canSave => _key.text.trim().isNotEmpty;

  @override
  void dispose() {
    _key.dispose();
    _price.dispose();
    _secondary.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSave) return;
    final blank = emptyProductWithKey(_key.text.trim());
    final amount = parseDecimal(
      _price.text,
      useCommaAsDecimalPlace: widget.useCommaAsDecimalPlace,
    );
    final other = widget.offerSecondary
        ? parseDecimal(
            _secondary.text,
            useCommaAsDecimalPlace: widget.useCommaAsDecimalPlace,
          )
        : null;
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      widget.vendorDoc
          ? blank.copyWith(
              cost: amount ?? blank.cost,
              price: other ?? blank.price,
              notes: notes,
            )
          : blank.copyWith(
              price: amount ?? blank.price,
              cost: other ?? blank.cost,
              notes: notes,
            ),
    );
  }

  Widget _amountField(
    BuildContext context, {
    required TextEditingController controller,
    required String labelKey,
    required bool autofocus,
  }) => LabeledField(
    label: context.tr(labelKey),
    child: TextField(
      controller: controller,
      // The first amount's own focus: the key is usually right already — it
      // is what the user just searched for.
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      // Enter in either amount saves (as 5.1.30's one amount did); Tab moves
      // between them. `next` on the first sent Enter to the second instead.
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: context.tr(labelKey)),
      onSubmitted: (_) => _submit(),
    ),
  );

  /// The document's own amount first (Price, or Cost on a purchase order),
  /// and the other one beside it when it is offered.
  Widget _amountRow(BuildContext context) {
    final primary = _amountField(
      context,
      controller: _price,
      labelKey: widget.vendorDoc ? 'cost' : 'price',
      autofocus: true,
    );
    if (!widget.offerSecondary) return primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: primary),
        const SizedBox(width: 12),
        Expanded(
          child: _amountField(
            context,
            controller: _secondary,
            labelKey: widget.vendorDoc ? 'price' : 'cost',
            autofocus: false,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormSaveScope(
      onSubmit: _submit,
      enabled: _canSave,
      child: AlertDialog(
        title: Text(context.tr('new_product')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LabeledField(
                label: context.tr('item'),
                child: TextField(
                  controller: _key,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: context.tr('item')),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 12),
              _amountRow(context),
              const SizedBox(height: 12),
              LabeledField(
                label: context.tr('description'),
                child: TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: context.tr('description'),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('cancel')),
          ),
          PrimaryDialogAction(
            label: context.tr('save'),
            autofocus: false,
            enabled: _canSave,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
