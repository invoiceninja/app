import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/color_hex.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/domain/tasks/task_rate.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/custom_field_detail_rows.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/utils/task_status_colors.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/detail_row_columns.dart';
import 'package:admin/ui/core/widgets/party_money_cell.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart'
    show emptyTask;
import 'package:admin/ui/features/tasks/widgets/detail/task_rate_context.dart';
import 'package:admin/utils/formatting.dart';

/// "Details" card on the project screen — what the edit form can set and
/// nothing else on the screen already says. Blank rows are omitted (no dash
/// placeholder), and a card with no rows builds nothing.
///
/// Not here, because each has a better home: the client and the number are
/// the header's subtitle, tags sit under the name, budgeted hours is a figure
/// on the standing card, and the notes have a card of their own.
///
/// [company] supplies the custom-field labels. It is handed in rather than
/// watched here because the profile needs the same answer twice — this card
/// draws the rows, and the profile has to know whether there are any before
/// it gives the card a column.
class ProjectDetailDetailsCard extends StatelessWidget {
  const ProjectDetailDetailsCard({
    super.key,
    required this.project,
    this.company,
    this.formatter,
    this.rates,
  });

  final Project project;

  /// The task-rate cascade above the project, watched by the profile only
  /// when the project has no rate of its own. With it, Task rate shows what
  /// the tasks inherit and from where (`projectInheritedTaskRate`); null, a
  /// project without a rate has no Task rate row.
  final TaskRateContext? rates;

  /// Null while the company row is still loading — custom fields wait for it.
  final Company? company;

  /// Null (still loading) leaves the dates out and prints money as a bare
  /// number, which is still the right number.
  final Formatter? formatter;

  /// Whether the card draws anything. **Derived from [rowsFor]**, the list
  /// [build] renders, so the two cannot drift.
  static bool hasContent(
    BuildContext context,
    Project project,
    Company? company, {
    Formatter? formatter,
    TaskRateContext? rates,
  }) => rowsFor(
    context,
    project,
    company,
    formatter: formatter,
    rates: rates,
  ).isNotEmpty;

  /// The rows, in display order.
  static List<Widget> rowsFor(
    BuildContext context,
    Project project,
    Company? company, {
    Formatter? formatter,
    TaskRateContext? rates,
  }) {
    final p = project;
    final due = p.dueDate;
    final inherited = p.taskRate == Decimal.zero && rates != null
        ? projectInheritedTaskRate(rates)
        : null;
    return [
      // Not until the formatter is here: a raw ISO date is not how this
      // company reads dates, and the row arrives with the rest a frame later.
      if (due != null && formatter != null)
        DetailInfoRow(
          label: context.tr('due_date'),
          value: formatter.date(due.toIso()),
          copyable: false,
        ),
      if (p.assignedUserId.isNotEmpty)
        DetailInfoRow(
          label: context.tr('assigned_user'),
          value: '',
          copyable: false,
          child: UserNameLabel(userId: p.assignedUserId),
        ),
      if (p.taskRate != Decimal.zero)
        _MoneyRow(
          labelKey: 'task_rate',
          amount: p.taskRate,
          clientId: p.clientId,
          formatter: formatter,
        )
      // A stored zero is "no rate of its own": the tasks bill at what the
      // project inherits, so that is the rate — said with where it comes
      // from, so it is not mistaken for one set here. Nothing anywhere in the
      // cascade, no row.
      else if (inherited != null)
        _MoneyRow(
          labelKey: 'task_rate',
          amount: inherited.rate,
          clientId: p.clientId,
          formatter: formatter,
          note: switch (inherited.source) {
            TaskRateSource.group => context.tr('inherited_from_group', {
              'name': inherited.groupName,
            }),
            TaskRateSource.company => context.tr('inherited_from_company'),
            // Client — the only other level a project-less, rate-less walk
            // can answer from.
            _ => context.tr('inherited_from_client'),
          },
        ),
      // Likewise optional: blank means "budgeted hours × task rate".
      if (p.budgetedAmount != Decimal.zero)
        _MoneyRow(
          labelKey: 'budgeted_amount',
          amount: p.budgetedAmount,
          clientId: p.clientId,
          formatter: formatter,
        ),
      // `#fff` is the server's default, not a choice: see [isUnsetColor].
      if (!isUnsetColor(p.color))
        DetailInfoRow(
          label: context.tr('color'),
          value: p.color,
          monospace: true,
          trailing: Padding(
            // 2 down: the row is top-aligned and the swatch is shorter than
            // the line of text it sits beside.
            padding: const EdgeInsetsDirectional.only(
              start: InSpacing.sm,
              top: 2,
            ),
            child: _ColorSwatch(hex: p.color),
          ),
        ),
      ..._customRows(context, p, company, formatter),
      ...recordTimestampRows(
        context,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
        formatter: formatter,
      ),
    ];
  }

  /// The configured, type-formatted custom-field rows. A slot renders only
  /// when the company has a label for it AND the project has a value.
  static List<Widget> _customRows(
    BuildContext context,
    Project p,
    Company? company,
    Formatter? formatter,
  ) {
    final rows = customFieldDetailRows(
      company: company,
      prefix: 'project',
      values: [p.customValue1, p.customValue2, p.customValue3, p.customValue4],
      formatter: formatter,
      yes: context.tr('yes'),
      no: context.tr('no'),
    );
    return [
      for (final r in rows) DetailInfoRow(label: r.label, value: r.value),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = rowsFor(
      context,
      project,
      company,
      formatter: formatter,
      rates: rates,
    );
    if (rows.isEmpty) return const SizedBox.shrink();
    return DashboardCardShell(
      title: context.tr('details'),
      child: DetailRowColumns(children: rows),
    );
  }
}

/// An amount in the currency the project's client is billed in — through
/// `PartyCurrencyBuilder`, the client → group → company cascade, like the
/// standing card above it. A project with no client is in the company's.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.labelKey,
    required this.amount,
    required this.clientId,
    required this.formatter,
    this.note,
  });

  final String labelKey;
  final Decimal amount;
  final String clientId;
  final Formatter? formatter;

  /// Dimmed context after the amount — where an inherited rate comes from.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final f = formatter;
    final note = this.note;
    final trailing = note == null
        ? null
        : Text(
            ' · $note',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.inTheme.ink2,
              fontSize: 12.5,
            ),
          );
    if (f == null) {
      return DetailInfoRow(
        label: context.tr(labelKey),
        value: amount.toString(),
        monospace: true,
        copyable: false,
        trailing: trailing,
      );
    }
    return PartyCurrencyBuilder(
      clientId: clientId,
      builder: (context, currencyId) => DetailInfoRow(
        label: context.tr(labelKey),
        value: f.money(amount, clientCurrencyId: currencyId),
        monospace: true,
        copyable: false,
        trailing: trailing,
      ),
    );
  }
}

/// The rate a project with no task rate of its own hands its tasks, the
/// level it comes from (client, group or company) and that group's name — or
/// null when nothing in the cascade sets one.
///
/// Answered by `resolveTaskRateWithSource` with a rate-less task and no
/// project, so it is the rate an invoice line from this project's task is
/// priced at, from the same one walk of the cascade the task edit form uses.
({Decimal rate, TaskRateSource source, String groupName})?
projectInheritedTaskRate(TaskRateContext rates) {
  final resolved = resolveTaskRateWithSource(
    task: emptyTask(),
    client: rates.client,
    group: rates.group,
    company: rates.company,
  );
  if (resolved.source == TaskRateSource.none || resolved.rate <= Decimal.zero) {
    return null;
  }
  return (
    rate: resolved.rate,
    source: resolved.source,
    groupName: rates.group?.name ?? '',
  );
}

/// The project's colour, as the kanban and the calendar draw it.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.hex});

  final String hex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: parseHexColor(hex) ?? Colors.transparent,
        borderRadius: BorderRadius.circular(InRadii.r1 / 2),
        border: Border.all(color: context.inTheme.border),
      ),
    );
  }
}
