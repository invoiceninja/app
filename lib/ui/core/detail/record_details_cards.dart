import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/detail_row_columns.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';

/// A record's Details rows as the profile cards that draw them, for
/// `RecordProfileLayout.lead`.
///
/// [facts] are what the record *is* — a payment's number, date, type and
/// reference; [bookkeeping] is what is kept *about* it — who it is assigned
/// to, the company's custom fields, when it was created and last updated.
///
/// **Split only when the Details card would otherwise have its row to
/// itself** ([split]) **and both halves have rows.** Then it is two cards,
/// Details and Additional Info, which the profile sets side by side and ends
/// level on a wide window and stacks below it — the shape every other record
/// has. One full-width Details card running its rows in two columns read as
/// a single card with a gap down the middle and the dates floating in its
/// right half (the payment record, Nov 2026).
///
/// Otherwise it is one Details card holding both, in that order: a record
/// that already has another lead card (a product with taxes) keeps the cards
/// it had, and a record with nothing but dates is not given a second card
/// titled "Additional" to nothing.
///
/// Empty when there are no rows at all, so the host can spread this straight
/// into `lead` — the profile pays a gap per entry
/// (`docs/detail-screen-layout.md` § A record whose Details card is alone
/// splits it in two).
List<Widget> recordDetailsCards(
  BuildContext context, {
  required List<Widget> facts,
  required List<Widget> bookkeeping,
  bool split = true,
}) {
  if (facts.isEmpty && bookkeeping.isEmpty) return const [];
  if (!split || facts.isEmpty || bookkeeping.isEmpty) {
    return [
      RecordRowsCard(
        title: context.tr('details'),
        rows: [...facts, ...bookkeeping],
      ),
    ];
  }
  return [
    RecordRowsCard(title: context.tr('details'), rows: facts),
    RecordRowsCard(title: context.tr('additional_info'), rows: bookkeeping),
  ];
}

/// A titled card of label / value rows — one of [recordDetailsCards].
///
/// Its rows go through [DetailRowColumns], so a card left alone in its row
/// (`DetailRowColumnsScope`) still runs them in two columns.
class RecordRowsCard extends StatelessWidget {
  const RecordRowsCard({super.key, required this.title, required this.rows});

  /// Already localized.
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return DashboardCardShell(
      title: title,
      child: DetailRowColumns(children: rows),
    );
  }
}
