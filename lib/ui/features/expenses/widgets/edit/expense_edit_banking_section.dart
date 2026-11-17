import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/expenses/view_models/expense_edit_view_model.dart';
import 'package:admin/ui/features/expenses/widgets/detail/expense_linked_names.dart';
import 'package:admin/ui/features/expenses/widgets/detail/expense_profile_cards.dart';

/// The Banking card: which bank transaction the expense is linked to, read
/// only, with a View link to it. Drawn only for a linked expense
/// ([isLinked]) — the link is made from the transaction (Transactions →
/// Convert / Link), never typed here, so the raw bank and transaction ids
/// were boxes nobody could usefully fill. The transaction reference is
/// edited once, in the Mark paid card.
class ExpenseEditBankingSection extends StatelessWidget {
  const ExpenseEditBankingSection({super.key, required this.vm});
  final ExpenseEditViewModel vm;

  /// Whether the card is drawn at all.
  static bool isLinked(ExpenseEditViewModel vm) =>
      vm.draft.transactionId.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final transactionId = vm.draft.transactionId;
    if (transactionId.isEmpty) return const SizedBox.shrink();
    final tokens = context.inTheme;
    final open = LinkedRecordOpener(context).to(
      EntityType.transaction,
      'view_bank_transaction',
      '/transactions',
      transactionId,
    );
    return DashboardCardShell(
      title: context.tr('banking'),
      child: ExpenseLinkedNamesBuilder(
        companyId: vm.companyId,
        transactionId: transactionId,
        builder: (context, names) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('transaction'),
              style: TextStyle(color: tokens.ink3, fontSize: 12),
            ),
            const SizedBox(height: InSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    // A dash until the transaction resolves (not cached, or
                    // not this user's to fetch) — never the raw id.
                    names.transaction.isEmpty ? '—' : names.transaction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.ink),
                  ),
                ),
                if (open != null) ...[
                  const SizedBox(width: InSpacing.sm),
                  // A button, not inline link text: a 44 px target on touch.
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.accentInk,
                      minimumSize: Env.isTouchPrimary
                          ? const Size(64, InSizes.touchTarget)
                          : null,
                    ),
                    onPressed: open,
                    child: Text(context.tr('view')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
