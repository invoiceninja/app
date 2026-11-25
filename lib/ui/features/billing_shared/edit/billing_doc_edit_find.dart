import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/billing/billing_doc_fields.dart';
import 'package:admin/data/models/domain/billing/line_item.dart';
import 'package:admin/data/models/domain/billing/line_item_custom_fields.dart';
import 'package:admin/domain/billing/line_item_find.dart';
import 'package:admin/domain/tasks/line_item_notes_display.dart';
import 'package:admin/ui/core/widgets/party_money_cell.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/ui/features/billing_shared/line_item_find.dart';
import 'package:admin/ui/features/billing_shared/view_models/billing_doc_edit_view_model.dart';
import 'package:admin/utils/formatting.dart';

/// The texts find in line items searches on the editor
/// (`docs/find-in-line-items.md` § The editor tints the matching lines): one
/// row per line of the draft, blank lines included, so a row's index is the
/// line's index in the draft and every editor table can name its rows.
///
/// What each field shows: the item, the description as text (a
/// task-generated note's markup dropped), the custom values, the figures as
/// they sit in their fields (no zero), the taxes, and the line total as the
/// table draws it. A blank line has no texts, so it never matches.
List<Map<LineFindSegment, String>> editorLineFindTexts(
  List<LineItem> lines, {
  Formatter? formatter,
  String? currencyId,
}) => [for (final line in lines) _texts(line, formatter, currencyId)];

Map<LineFindSegment, String> _texts(
  LineItem it,
  Formatter? formatter,
  String? currencyId,
) {
  if (it.isBlank) return const {};
  String field(Decimal v) => v == Decimal.zero ? '' : v.toString();
  String tax(String name, Decimal rate) =>
      name.trim().isEmpty ? '' : '${name.trim()} ${field(rate)}%';
  final gross = it.gross;
  return {
    LineFindSegment.name: it.productKey,
    LineFindSegment.notes: lineItemNotesPlainText(it.notes),
    LineFindSegment.custom: [
      for (var slot = 1; slot <= 4; slot++)
        if (lineItemCustomValue(it, slot).trim().isNotEmpty)
          lineItemCustomValue(it, slot).trim(),
    ].join('\n'),
    LineFindSegment.quantity: field(it.quantity),
    LineFindSegment.cost: field(it.cost),
    LineFindSegment.discount: field(it.discount),
    LineFindSegment.tax: [
      tax(it.taxName1, it.taxRate1),
      tax(it.taxName2, it.taxRate2),
      tax(it.taxName3, it.taxRate3),
    ].where((t) => t.isNotEmpty).join('\n'),
    LineFindSegment.total: gross == Decimal.zero
        ? ''
        : (formatter?.money(gross, currencyId: currencyId) ?? gross.toString()),
  };
}

/// Hands the draft's lines to [find] on every build of the editor (each
/// change of the view model), in the document's currency — and lays out
/// [child], the editor, exactly as if it were not here.
///
/// The currency comes from a [PartyCurrencyBuilder], which changes its own
/// shape when the party does (it adds a keyed `StreamBuilder` once there is a
/// client). So it is a zero-size sibling of [child], never its parent: as a
/// parent it remounted the whole editor — the client picker under the user's
/// finger included — the moment a client was picked (`docs/form-fields.md`
/// § A focused field never changes its place in the tree on state).
///
/// The editor's tables cannot be the source, as the record's read-only table
/// is: a client document draws its lines in three tabs (Products / Tasks /
/// Expenses), each table only its own kind, and find counts across all three.
class BillingDocEditFindRows extends StatelessWidget {
  const BillingDocEditFindRows({
    super.key,
    required this.find,
    required this.vm,
    required this.party,
    required this.child,
  });

  final LineItemFindController find;
  final BillingDocEditViewModel<BillingDocFields> vm;
  final BillingDocParty party;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final draft = vm.draft;
    final client = party == BillingDocParty.client;
    return Stack(
      // The editor gets the constraints it would get alone, and sizes this.
      fit: StackFit.passthrough,
      children: [
        child,
        PositionedDirectional(
          start: 0,
          top: 0,
          width: 0,
          height: 0,
          child: PartyCurrencyBuilder(
            clientId: client ? draft.clientId : null,
            vendorId: client ? null : draft.vendorId,
            builder: (context, currencyId) {
              find.updateRows(
                editorLineFindTexts(
                  draft.lineItems,
                  formatter: context.read<Services?>()?.formatterIfReady(
                    vm.companyId,
                  ),
                  currencyId: currencyId,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}
