import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/bank_account.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/record_details_cards.dart';
import 'package:admin/ui/core/detail/record_profile_layout.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/detail_row_columns.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/formatting.dart';

/// A bank account's reference fields, with the one setting worth changing
/// from here: Auto Sync.
///
/// Details — what the account is — and Additional Info — Sync From, created,
/// updated and the Auto Sync switch — as two level cards on a wide window
/// (`RecordProfileLayout`), stacked below it. It was one full-width card
/// running its rows in two columns, with the dates floating in its right
/// half.
///
/// **Auto Sync is a switch, on the record.** It is by far the most-flipped
/// field on a bank account, and a trip through the edit form for one boolean
/// is the reason this screen had a quick-edit row at all. It flips the single
/// field and saves through the outbox like any other edit; while that save is
/// still queued a small spinner beside the label says so.
///
/// [onAutoSyncChanged] null draws the switch inert — a deleted account is
/// read-only, and so is one this user may not edit.
class BankAccountDetailProfile extends StatelessWidget {
  const BankAccountDetailProfile({
    super.key,
    required this.account,
    required this.onAutoSyncChanged,
    this.formatter,
  });

  final BankAccount account;
  final ValueChanged<bool>? onAutoSyncChanged;

  /// For the dates. Null (still loading) leaves them out.
  final Formatter? formatter;

  /// What the account is — provider, type, integration, status, currency.
  /// Blank fields are left out.
  static List<Widget> rowsFor(
    BuildContext context,
    BankAccount account, {
    Formatter? formatter,
  }) {
    return [
      if (account.provider.trim().isNotEmpty)
        DetailInfoRow(
          label: context.tr('provider'),
          value: account.provider.trim(),
          copyable: false,
        ),
      if (account.type.trim().isNotEmpty)
        DetailInfoRow(
          label: context.tr('account_type'),
          value: context.tr(labelKeyForAccountType(account.type.trim())),
          copyable: false,
        ),
      DetailInfoRow(
        label: context.tr('integration_type'),
        value: context.tr(labelKeyForProvider(account.integrationType)),
        copyable: false,
      ),
      if (account.status.trim().isNotEmpty)
        DetailInfoRow(
          label: context.tr('status'),
          value: account.status.trim(),
          copyable: false,
        ),
      if (account.currency.trim().isNotEmpty)
        DetailInfoRow(
          label: context.tr('currency'),
          value: account.currency.trim().toUpperCase(),
          copyable: false,
        ),
    ];
  }

  /// The date transactions are imported from, then created and updated —
  /// the rows of the Additional Info card, above its switch. Created /
  /// updated are left out on a phone, where `RecordTimestampsLine` says them.
  static List<Widget> bookkeepingRows(
    BuildContext context,
    BankAccount account, {
    Formatter? formatter,
  }) {
    final from = account.fromDate;
    return [
      if (from != null && formatter != null)
        DetailInfoRow(
          label: context.tr('sync_from'),
          value: formatter.date(from.toIso()),
          copyable: false,
        ),
      ...recordTimestampRows(
        context,
        createdAt: account.createdAt,
        updatedAt: account.updatedAt,
        formatter: formatter,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = rowsFor(context, account, formatter: formatter);
    final bookkeeping = bookkeepingRows(context, account, formatter: formatter);
    // Two cards, level on a wide window and stacked below it: what the
    // account is, and what is kept about it with the one setting — Auto
    // Sync sits under its Sync From date, and the switch evens the two
    // cards' heights where the dates alone would leave the second half
    // blank. Additional Info always exists: it holds the switch.
    return RecordProfileLayout(
      lead: [
        if (rows.isNotEmpty)
          RecordRowsCard(title: context.tr('details'), rows: rows),
        DashboardCardShell(
          title: context.tr('additional_info'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DetailRowColumns(children: bookkeeping),
              if (bookkeeping.isNotEmpty) const DetailRowDivider(),
              _AutoSyncRow(account: account, onChanged: onAutoSyncChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _AutoSyncRow extends StatelessWidget {
  const _AutoSyncRow({required this.account, required this.onChanged});

  final BankAccount account;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final label = context.tr('auto_sync');
    return Padding(
      padding: const EdgeInsets.only(top: InSpacing.xs),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // An outbox row is pending — the change is queued, not
                      // yet on the server.
                      if (account.isDirty) ...[
                        const SizedBox(width: InSpacing.sm),
                        SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: tokens.ink3,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('auto_sync_help'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.ink2,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: InSpacing.sm),
            Switch(value: account.autoSync, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
