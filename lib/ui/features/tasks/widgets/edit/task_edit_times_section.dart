import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/time_entry.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/edit/task_edit_timer_card.dart';
import 'package:admin/ui/features/tasks/widgets/edit/time_entry_editor_sheet.dart';
import 'package:admin/ui/features/tasks/widgets/edit/time_entry_row.dart';
import 'package:admin/ui/features/tasks/widgets/edit/time_entry_table.dart';
import 'package:admin/ui/features/tasks/widgets/edit/time_log_empty_state.dart';
import 'package:admin/ui/features/tasks/widgets/time_log_problem_message.dart';
import 'package:admin/utils/formatting.dart';

/// The time-log column of the Task edit form: the timer card
/// (`TaskEditTimerCard` — the running clock, Start / Resume / Stop, and the
/// Logged / Billable / Booked / Estimate strip), then the time log itself,
/// whose header holds "+ Add time" and whose body lists the entries
/// newest-first.
class TaskEditTimesSection extends StatelessWidget {
  const TaskEditTimesSection({
    super.key,
    required this.vm,
    required this.locked,
    this.formatter,
  });

  final TaskEditViewModel vm;
  final bool locked;

  /// Resolved company `Formatter` for date rendering inside each row.
  /// Null in test contexts; falls back to ISO inside `TimeEntryRow`.
  final Formatter? formatter;

  /// The desktop time-log table's intrinsic minimum width (six fixed
  /// columns + gaps + card padding ≈ 792px, rounded up). Below this width
  /// the mobile `TimeEntryRow` list renders instead so the table never
  /// overflows its constraints (the generic 600px `Breakpoints.isWide`
  /// used to leave a 600–792px band — tablet / iPad portrait — that did).
  static const double _kTableMinWidth = 800;

  Future<void> _openEditor(
    BuildContext context,
    int displayIndex, {
    required bool allowBillable,
    required bool showEndDate,
    required bool showItemDescription,
  }) async {
    final entries = vm.draft.timeLog;
    final actualIndex = entries.length - 1 - displayIndex;
    final result = await TimeEntryEditorSheet.show(
      context,
      initial: entries[actualIndex],
      formatter: formatter,
      allowBillableToggle: allowBillable,
      showEndDate: showEndDate,
      showItemDescription: showItemDescription,
    );
    if (result == null) return;
    if (TimeEntryEditorSheet.isRemoveSignal(result)) {
      vm.removeEntry(actualIndex);
    } else {
      vm.updateEntry(actualIndex, result);
    }
  }

  /// Mobile: open the editor sheet so the user can edit a fresh entry on
  /// a full-screen surface. Tiny inline cells aren't usable on small
  /// viewports.
  Future<void> _addEntryViaSheet(
    BuildContext context, {
    required bool allowBillable,
    required bool showEndDate,
    required bool showItemDescription,
  }) async {
    final result = await TimeEntryEditorSheet.show(
      context,
      initial: TimeEntry(
        start: DateTime.now().subtract(const Duration(minutes: 30)),
        stop: DateTime.now(),
      ),
      formatter: formatter,
      allowBillableToggle: allowBillable,
      showEndDate: showEndDate,
      showItemDescription: showItemDescription,
    );
    if (result == null) return;
    if (TimeEntryEditorSheet.isRemoveSignal(result)) return;
    vm.addEntry(
      start: result.start,
      stop: result.stop,
      description: result.description,
      billable: result.billable,
    );
  }

  /// Desktop: append a fresh entry inline with the VM's default seed
  /// (30 min back → now). The table watches the VM and surfaces a new
  /// row + focuses its start cell on the next frame.
  void _addEntryInline() {
    vm.addEntry();
  }

  /// The server's own verdict on this draft's `time_log`, rendered where the

  /// rows are.

  ///

  /// `Request::checkTimeLog` rejects the whole payload on an overlap, an

  /// inverted entry, or a running entry that isn't last — and a rejected save

  /// is invisible until the outbox row dies. Save is gated on this too

  /// (`task_edit_screen.dart`), so the message is the explanation for a

  /// disabled button rather than a warning nobody has to act on.

  Widget _problemBanner(BuildContext context) {
    final problem = vm.draftTimeLogProblem;

    if (problem == null) return const SizedBox.shrink();

    final tokens = context.inTheme;

    // Shared with the weekly grid, which used to roll its own and reported every
    // kind as an overlap — with the `:from` / `:to` placeholders unfilled.
    final message = timeLogProblemMessage(
      context,
      problem,
      formatter: formatter,
    );

    return Padding(
      padding: EdgeInsets.only(top: InSpacing.sm),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: tokens.warning),

          const SizedBox(width: InSpacing.sm),

          Expanded(
            child: Text(
              message,

              style: TextStyle(color: tokens.warning, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    return StreamBuilder<Company?>(
      stream: services.company.watchCompany(vm.companyId),
      builder: (context, companySnap) {
        final company = companySnap.data;
        // `show_task_end_date` defaults false (admin-portal parity: start +
        // duration, no explicit stop date); the others default to showing.
        final allowBillable = company?.settings.allowBillableTaskItems ?? true;
        final showEndDate = company?.showTaskEndDate ?? false;
        final showItemDescription =
            company?.settings.showTaskItemDescription ?? true;
        final tokens = context.inTheme;
        final entries = vm.draft.timeLog.reversed.toList(growable: false);
        // The shared edit-form card; the table and rows bring their own
        // padding.
        final log = DashboardCardShell(
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Gate the desktop table on its real minimum width, not the
              // generic 600px breakpoint — below it the mobile row list renders.
              final wide = constraints.maxWidth >= _kTableMinWidth;
              // Phones: collapse the header actions to icon-only so the title +
              // live total + two buttons don't overflow the header Row.
              final compact = constraints.maxWidth < 480;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header — same on both layouts; only the "add" action's
                  // entry point differs (inline on desktop, modal sheet on
                  // mobile). `InSpacing.lg(context)` matches the canonical card-
                  // interior padding documented in CLAUDE.md § Design
                  // system (v2) — same inset as `FormSection`,
                  // `DashboardCardShell`, and the identity card above.
                  Padding(
                    padding: EdgeInsets.all(InSpacing.lg(context)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            // The title takes what the button leaves. The
                            // total it used to carry is the timer card's
                            // Logged figure now, directly above.
                            Expanded(
                              child: Text(
                                context.tr('time_log').toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.ink3,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            if (!locked) ...[
                              // Per-call minimumSize override: lib/app/theme.dart
                              // sets `Size.fromHeight(40)` on OutlinedButton which
                              // is `Size(double.infinity, 40)` — fine in a column,
                              // fatal in this Row. See CLAUDE.md § Design system
                              // (v2) "Default to side-by-side dialog actions" for
                              // the verbatim rule.
                              if (compact)
                                IconButton(
                                  tooltip: context.tr('add_time'),
                                  icon: const Icon(Icons.add),
                                  onPressed: wide
                                      ? _addEntryInline
                                      : () => _addEntryViaSheet(
                                          context,
                                          allowBillable: allowBillable,
                                          showEndDate: showEndDate,
                                          showItemDescription:
                                              showItemDescription,
                                        ),
                                )
                              else
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(64, 40),
                                  ),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: Text(context.tr('add_time')),
                                  onPressed: wide
                                      ? _addEntryInline
                                      : () => _addEntryViaSheet(
                                          context,
                                          allowBillable: allowBillable,
                                          showEndDate: showEndDate,
                                          showItemDescription:
                                              showItemDescription,
                                        ),
                                ),
                            ],
                          ],
                        ),
                        _problemBanner(context),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.border),
                  // Pick between the desktop table and the mobile card list.
                  if (wide)
                    TimeEntryTable(
                      vm: vm,
                      locked: locked,
                      formatter: formatter,
                      allowBillable: allowBillable,
                      showDescription: showItemDescription,
                    )
                  else if (entries.isEmpty)
                    TimeLogEmptyState(locked: locked)
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < entries.length; i++)
                          TimeEntryRow(
                            dueDate: vm.draft.dueDate,
                            entry: entries[i],
                            enabled: !locked,
                            formatter: formatter,
                            onTap: () => _openEditor(
                              context,
                              i,
                              allowBillable: allowBillable,
                              showEndDate: showEndDate,
                              showItemDescription: showItemDescription,
                            ),
                            onRemove: () =>
                                vm.removeEntry(vm.draft.timeLog.length - 1 - i),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TaskEditTimerCard(
              vm: vm,
              locked: locked,
              allowBillable: allowBillable,
            ),
            SizedBox(height: InSpacing.lg(context)),
            log,
          ],
        );
      },
    );
  }
}
