import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/domain/tasks/task_rate.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:admin/ui/core/widgets/form_group_heading.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/core/widgets/in_date_field.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/entity_custom_fields_section.dart';
import 'package:admin/ui/core/widgets/assigned_user_picker_field.dart';
import 'package:admin/ui/core/widgets/entity_picker_field.dart';
import 'package:admin/ui/core/widgets/entity_tags_field.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/locked_entity_field_row.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/clients/widgets/client_picker_field_with_create.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/tasks/view_models/task_edit_view_model.dart';
import 'package:admin/ui/features/tasks/widgets/detail/task_rate_context.dart';
import 'package:admin/ui/features/tasks/widgets/edit/task_edit_times_section.dart';
import 'package:admin/ui/features/tasks/widgets/task_status_picker_field.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/edit/create_form_documents.dart';
import 'package:admin/ui/core/widgets/example_hint.dart';

/// Form body for the Task edit / create screen. Composes the identity
/// fields, the time-log section (`TaskEditTimesSection`), and the custom
/// fields panel. Renders the invoiced-lockout banner at the top when
/// `vm.draft.isInvoiced`.
///
/// Layout:
/// - **≥1100 px**: two columns. Left (`Expanded`) carries the lockout
///   banner + the time-log section — the time log is the dominant content
///   and earns the wider column. Right (`_sidebarWidth` 360 px) holds the
///   identity fields. Mirror of the task detail layout split.
/// - **<1100 px**: single 800 px-capped centered column, today's shape.
///   Don't widen — the time-entry table's columns are fixed and would look
///   hollow in a wider container.
class TaskEditLayout extends StatelessWidget {
  const TaskEditLayout({super.key, required this.vm, this.formatter});

  final TaskEditViewModel vm;

  /// Threaded down to `TaskEditTimesSection` → `TimeEntryRow` /
  /// `TimeEntryEditorSheet` so the date portions of time-log entries
  /// honor `company.settings.date_format_id`. Null in tests; widgets
  /// fall back to ISO `YYYY-MM-DD`.
  final Formatter? formatter;

  static const double _twoColumnBreakpoint = 1100;
  static const double _sidebarWidth = 360;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final locked = vm.draft.isInvoiced;
        return LayoutBuilder(
          builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= _twoColumnBreakpoint;
            return SingleChildScrollView(
              padding: EdgeInsets.all(InSpacing.lg(context)),
              child: twoCol ? _wide(context, locked) : _narrow(context, locked),
            );
          },
        );
      },
    );
  }

  Widget _wide(BuildContext context, bool locked) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (locked) ...[
                _LockoutBanner(),
                SizedBox(height: InSpacing.lg(context)),
              ],
              TaskEditTimesSection(
                vm: vm,
                locked: locked,
                formatter: formatter,
              ),
            ],
          ),
        ),
        SizedBox(width: InSpacing.md(context)),
        SizedBox(
          width: _sidebarWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IdentitySection(vm: vm, locked: locked, formatter: formatter),
              if (vm.offersDocuments) ...[
                SizedBox(height: InSpacing.lg(context)),
                CreateFormDocumentsCard(vm: vm),
              ],
              SizedBox(height: InSpacing.lg(context)),
              _CustomFieldsSection(
                vm: vm,
                formatter: formatter,
                locked: locked,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context, bool locked) {
    return Center(
      child: ConstrainedBox(
        // 820 (not 800) so the time-log table — which renders at ≥800px and
        // needs ~792 — has margin instead of butting against the cap.
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (locked) ...[
              _LockoutBanner(),
              SizedBox(height: InSpacing.lg(context)),
            ],
            _IdentitySection(vm: vm, locked: locked, formatter: formatter),
            SizedBox(height: InSpacing.lg(context)),
            _CustomFieldsSection(vm: vm, formatter: formatter, locked: locked),
            SizedBox(height: InSpacing.lg(context)),
            TaskEditTimesSection(vm: vm, locked: locked, formatter: formatter),
            if (vm.offersDocuments) ...[
              SizedBox(height: InSpacing.lg(context)),
              CreateFormDocumentsCard(vm: vm),
            ],
          ],
        ),
      ),
    );
  }
}

/// Task custom fields (`task1..4`) — type-aware, gated by the company's
/// configured labels (self-collapses when none). Disabled when the task is
/// invoice-locked, matching the rest of the form.
class _CustomFieldsSection extends StatelessWidget {
  const _CustomFieldsSection({
    required this.vm,
    required this.formatter,
    required this.locked,
  });

  final TaskEditViewModel vm;
  final Formatter? formatter;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final section = EntityCustomFieldsSection(
      keyPrefix: 'task',
      companyStream: context.read<Services>().company.watchCompany(
        vm.companyId,
      ),
      formatter: formatter,
      cardTitle: context.tr('custom_fields'),
      values: [
        vm.draft.customValue1,
        vm.draft.customValue2,
        vm.draft.customValue3,
        vm.draft.customValue4,
      ],
      onChanged: [
        vm.setCustomValue1,
        vm.setCustomValue2,
        vm.setCustomValue3,
        vm.setCustomValue4,
      ],
    );
    return _Lockable(locked: locked, child: section);
  }
}

class _LockoutBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Container(
      padding: EdgeInsets.all(InSpacing.md(context)),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: tokens.ink),
          const SizedBox(width: InSpacing.sm),
          Expanded(
            child: Text(
              context.tr('task_invoiced_locked'),
              style: TextStyle(color: tokens.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({
    required this.vm,
    required this.locked,
    this.formatter,
  });
  final TaskEditViewModel vm;
  final bool locked;
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    // EntityEditScaffold wraps the body in a FormSaveScope already; we
    // pull it off the inherited widget and have each single-line field
    // submit through it on Enter. Multi-line fields (description) leave
    // Enter alone so it inserts a newline.
    final scope = FormSaveScope.maybeOf(context);
    void submit(String _) => scope?.trySubmit();
    // A titled card like every other edit form's, so the sidebar reads as the
    // task's details rather than a loose stack of fields.
    return DashboardCardShell(
      title: context.tr('details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LabeledField(
            label: context.tr('description'),
            child: TextFormField(
              initialValue: vm.draft.description,
              enabled: !locked,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(labelText: context.tr('description')),
              onChanged: vm.setDescription,
            ),
          ),
          SizedBox(height: InSpacing.md(context)),
          // The task's state beside its id where the card is wide enough
          // (the narrow single-column form); stacked in the 360 px sidebar,
          // where a status name beside the number was cut to a word.
          _NumberAndStatus(
            number: LabeledField(
              label: context.tr('number'),
              child: TextFormField(
                // Server auto-assigns when left blank on create; editable to
                // match admin-portal / React.
                initialValue: vm.draft.number,
                enabled: !locked,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: context.tr('number')),
                onChanged: vm.setNumber,
                onFieldSubmitted: submit,
                autocorrect: false,
              ),
            ),
            status: _Lockable(
              locked: locked,
              child: TaskStatusPickerField(
                companyId: vm.companyId,
                selectedId: vm.draft.statusId,
                onChanged: vm.setStatusId,
              ),
            ),
          ),
          SizedBox(height: InSpacing.md(context)),
          EntityTagsField(
            entityType: 'task',
            selectedIds: vm.draft.tagIds,
            onChanged: vm.setTagIds,
            enabled: !locked,
          ),
          // Who the work is for and who does it.
          FormGroupHeading(context.tr('assignment')),
          _ClientPicker(vm: vm, locked: locked),
          SizedBox(height: InSpacing.md(context)),
          _ProjectPicker(vm: vm, locked: locked),
          SizedBox(height: InSpacing.md(context)),
          _Lockable(
            locked: locked,
            child: AssignedUserPickerField(
              companyId: vm.companyId,
              selectedId: vm.draft.assignedUserId,
              onChanged: vm.setAssignedUserId,
            ),
          ),
          // What the work bills at, and when it is promised for.
          FormGroupHeading(context.tr('billing_and_schedule')),
          // A blank rate bills at the cascade's answer — the project, the
          // client, its group, then the company (React ui#3427) — so the
          // empty field says what that is and which level sets it, the way a
          // client's blank cascade settings do ("Default (€75.00)", "From
          // project"; docs/form-fields.md).
          TaskRateContextBuilder(
            companyId: vm.companyId,
            clientId: vm.draft.clientId,
            projectId: vm.draft.projectId,
            builder: (context, rates) {
              final inherited = resolveTaskRateWithSource(
                task: vm.draft.copyWith(rate: Decimal.zero),
                project: rates.project,
                client: rates.client,
                group: rates.group,
                company: rates.company,
              );
              final showInherited =
                  vm.draft.rate == Decimal.zero &&
                  inherited.rate > Decimal.zero;
              final currencyId = rates.client?.currencyId;
              final f = formatter;
              final symbol = f?.currencySymbolFor(currencyId: currencyId) ?? '';
              return LabeledField(
                label: context.tr('rate'),
                child: TextFormField(
                  initialValue: decimalInputText(vm.draft.rate),
                  enabled: !locked,
                  textInputAction: TextInputAction.done,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.tr('rate'),
                    // The client's currency, from the Formatter — never a
                    // hard-coded `$`. Only once the task has a rate of its
                    // own: a blank field's hint already names the currency
                    // ("Default ($75.00)"), and the prefix would say it twice.
                    prefixText: symbol.isEmpty || vm.draft.rate == Decimal.zero
                        ? null
                        : '$symbol ',
                    suffixText: context.tr('rate_per_hour_suffix'),
                    hintText: showInherited
                        ? context.tr('default_with_value', {
                            'value':
                                f?.money(
                                  inherited.rate,
                                  clientCurrencyId: currencyId,
                                ) ??
                                '${inherited.rate}',
                          })
                        : null,
                    helperText: showInherited
                        ? _rateSourceText(context, inherited.source, rates)
                        : null,
                  ),
                  onChanged: vm.setRate,
                  onFieldSubmitted: submit,
                ),
              );
            },
          ),
          SizedBox(height: InSpacing.md(context)),
          // The plan, beside the rate that prices it. `due_date` is the day
          // the work is promised for and `estimated_duration` the time
          // allocated to it (both 2026-08-31 server fields); together they are
          // what survives a booking being claimed, since claiming rewrites the
          // booked block's start to now. See `task_schedule.dart`.
          Row(
            children: [
              Expanded(
                child: InDateField(
                  value: vm.draft.dueDate?.toDateTime(),
                  onChanged: vm.setDueDate,
                  formatter: formatter,
                  enabled: !locked,
                  // Clearable, like every other optional date in the app — and
                  // more than usually load-bearing here: this field is the only
                  // input to the booking anchor, so a date set by accident must
                  // be removable from the form that set it.
                  clearable: true,
                  labelText: context.tr('due_date'),
                ),
              ),
              const SizedBox(width: InSpacing.sm),
              Expanded(
                child: LabeledField(
                  label: context.tr('estimated_duration'),
                  child: TextFormField(
                    initialValue: vm.draft.estimatedSeconds <= 0
                        ? ''
                        : formatDuration(
                            Duration(seconds: vm.draft.estimatedSeconds),
                            compactDays: true,
                            showSeconds: false,
                          ),
                    enabled: !locked,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: context.tr('estimated_duration'),
                      hintText: exampleHint(context, kDurationExample),
                    ),
                    onChanged: vm.setEstimatedDuration,
                    onFieldSubmitted: submit,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Number and Status: one row where the card has room for both, as
/// [FormFieldPair] decides it, and stacked with the form's usual gap where it
/// does not — [FormFieldPair]'s own stack puts its two fields closer together
/// than every other pair of fields on this card.
class _NumberAndStatus extends StatelessWidget {
  const _NumberAndStatus({required this.number, required this.status});

  final Widget number;
  final Widget status;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= Breakpoints.wide) {
          return FormFieldPair(left: number, right: status);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            number,
            SizedBox(height: InSpacing.md(context)),
            status,
          ],
        );
      },
    );
  }
}

/// Which level of the task-rate cascade a blank Rate field inherits from.
String? _rateSourceText(
  BuildContext context,
  TaskRateSource source,
  TaskRateContext rates,
) => switch (source) {
  TaskRateSource.project => context.tr('inherited_from_project'),
  TaskRateSource.client => context.tr('inherited_from_client'),
  TaskRateSource.group => context.tr('inherited_from_group', {
    'name': (rates.group?.name.isNotEmpty ?? false)
        ? rates.group!.name
        : (rates.group?.id ?? ''),
  }),
  TaskRateSource.company => context.tr('inherited_from_company'),
  TaskRateSource.task || TaskRateSource.none => null,
};

/// Searchable client picker. Pulls the first 5000 active clients from
/// Drift; type to filter. Mirrors the React app's "Client" combobox on
/// Task edit.
///
/// Two locked-out states:
///   * [locked] true (invoiced task) — the whole form is read-only; keep
///     the dropdown but disable it via IgnorePointer + Opacity.
///   * Project selected (`vm.draft.projectId.isNotEmpty`) — picking a
///     project derives the client; render a clearly-locked read-only
///     row with a lock icon + helper text instead of a dropdown so the
///     user understands WHY they can't edit the client.
class _ClientPicker extends StatelessWidget {
  const _ClientPicker({required this.vm, required this.locked});

  final TaskEditViewModel vm;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    // The view model's company, not the session's: it is the company this form
    // is bound to, and all four pickers here read the same field. Locality
    // rather than a bug fix — no divergence between the two has been observed.
    final companyId = vm.companyId;
    final lockedByProject = vm.draft.projectId.isNotEmpty;

    if (lockedByProject) {
      // `tappable: false` — unlike the billing-doc and project locks, this one
      // is not a server freeze and the client is not a destination the user
      // should be sent to. They unlock it by clearing the Project, which is
      // what the helper text says. (The branch also sits deliberately OUTSIDE
      // `_Lockable`, so making it navigable would hand an invoiced task a live
      // tap target it does not have today.)
      return LockedClientFieldRow(
        clientId: vm.draft.clientId,
        helperText: context.tr('project_drives_client'),
        tappable: false,
      );
    }

    return _Lockable(
      locked: locked,
      // `ClientPickerField`: it searches the server before offering
      // "Create «x»", so a client outside this device's cache is found rather
      // than duplicated.
      child: ClientPickerFieldWithCreate(
        companyId: companyId,
        selectedClientId: vm.draft.clientId,
        label: context.tr('client'),
        enabled: !locked,
        onSelected: (c) => vm.setClientId(c?.id ?? ''),
      ),
    );
  }
}

/// Searchable project picker. Offers every active project until a client is
/// picked, then only that client's; picking a project sets the client (which
/// then locks — `project_drives_client`) and auto-fills the rate when it is
/// zero, via [TaskEditViewModel.selectProject].
///
/// Project first is the old app's order and the one users reach for (beta
/// feedback): this used to stay disabled behind "Select a client first", and
/// a client with no projects said "Loading" forever, because the empty list
/// fell through to [SearchableDropdownField]'s default hint. Same shape as the
/// expense form's project picker.
class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({required this.vm, required this.locked});

  final TaskEditViewModel vm;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    final companyId = vm.companyId;
    final clientId = vm.draft.clientId;
    return _Lockable(
      locked: locked,
      child: EntityPickerField<Project>(
        label: context.tr('project'),
        // The list narrows to the picked client, so the client id is part of
        // what invalidates the stream.
        cacheKey: (companyId, clientId),
        selectedId: vm.draft.projectId,
        itemsStream: () => clientId.isEmpty
            ? services.projects.watchPage(
                companyId: companyId,
                loadedPages: 100,
              )
            : services.projects.watchForClient(
                companyId: companyId,
                clientId: clientId,
              ),
        watchById: (id) =>
            services.projects.watch(companyId: companyId, id: id),
        displayString: (p) => p.name.isEmpty ? p.id : p.name,
        idOf: (p) => p.id,
        emptyHintKey: 'no_records_found',
        onChanged: vm.selectProject,
      ),
    );
  }
}

/// Greys out and disables a field on an invoiced (or not-yet-applicable) task.
///
/// `IgnorePointer` alone isn't enough: it only overrides hit testing, so Tab
/// still reaches the widget, and a picker that has focus can be driven entirely
/// from the keyboard — arrow to another option, Enter, and the draft is edited
/// on a record the server will reject.
class _Lockable extends StatelessWidget {
  const _Lockable({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return ExcludeFocus(
      child: IgnorePointer(child: Opacity(opacity: 0.5, child: child)),
    );
  }
}
