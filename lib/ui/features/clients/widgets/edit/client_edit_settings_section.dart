import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/industry.dart';
import 'package:admin/data/models/value/language.dart';
import 'package:admin/data/models/value/size.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/assigned_user_picker_field.dart';
import 'package:admin/ui/core/widgets/form_group_heading.dart';
import 'package:admin/ui/core/widgets/labeled_switch_group.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_field_pair.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_inherited_settings.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_verification_checks.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';

/// Per-client "Settings" card on the edit screen — the cascade overrides
/// (currency / language / payment terms / task rate) plus classification,
/// company size, industry, e-invoice routing, and the tax flags. Mirrors the
/// React edit "Additional Info → Settings / Classify" sub-tabs.
///
/// Currency / language / payment_terms live in the `settings` cascade (see
/// `Client.toApiJson`): clearing a picker removes the override so the client
/// inherits the company/group value. The pickers are type-to-search because
/// the currency / language lists run past ~20 entries (Forms rule).
class ClientEditSettingsSection extends StatelessWidget {
  const ClientEditSettingsSection({super.key, required this.vm});

  final ClientEditViewModel vm;

  /// Server `classification` enum (React parity). Labels resolve via `tr`.
  static const List<String> _classifications = [
    'individual',
    'business',
    'company',
    'partnership',
    'trust',
    'charity',
    'government',
    'other',
  ];

  @override
  Widget build(BuildContext context) {
    final draft = vm.draft;
    final statics = context.read<Services>().statics;

    List<T> sorted<T>(Iterable<T> items, String Function(T) name) =>
        items.toList()..sort(
          (a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()),
        );

    final currencies = sorted<Currency>(
      statics.currencies.values,
      (c) => c.name,
    );
    final languages = sorted<Language>(statics.languages.values, (l) => l.name);
    final industries = sorted<Industry>(
      statics.industries.values,
      (i) => i.name,
    );
    final sizes = sorted<Size>(statics.sizes.values, (s) => s.name);

    // `default_task_rate` is stored as a num (see `setDefaultTaskRate`); show a
    // whole number without a trailing `.0`, and tolerate a legacy string value.
    final taskRateRaw = draft.settings?['default_task_rate'];
    final taskRate = taskRateRaw == null
        ? ''
        : (taskRateRaw is num && taskRateRaw % 1 == 0
              ? taskRateRaw.toInt().toString()
              : taskRateRaw.toString());

    final inherited = context.tr('default');
    final daysSuffix = context.tr('days');
    return DashboardCardShell(
      title: context.tr('settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Four kinds of thing, each under its own heading: twelve fields in
          // one grid made the user read all twelve to find one.
          FormGroupHeading(context.tr('ownership'), first: true),
          // Group + assigned user (repo-backed, so each is a StreamBuilder-fed
          // searchable picker). Clearing either sets the id back to ''.
          ClientEditFieldPair(
            left: _GroupPicker(vm: vm),
            right: AssignedUserPickerField(
              companyId: vm.companyId,
              selectedId: vm.draft.assignedUserId,
              onChanged: vm.setAssignedUserId,
            ),
          ),
          // What this client's invoices and quotes start from. Each is a
          // cascade setting: blank inherits the group's, then the company's,
          // and the empty field says what that is and where it comes from
          // ("Default (Euro)", "From group Wholesale") instead of looking
          // unset.
          FormGroupHeading(context.tr('defaults')),
          _CascadeSources(
            companyId: vm.companyId,
            builder: (context, companySettings, groups) {
              InheritedSetting? inheritedFor(String key) =>
                  inheritedClientSetting(
                    key,
                    groupId: draft.groupSettingsId,
                    groups: groups,
                    companySettings: companySettings,
                  );
              String hint(InheritedSetting? s, String Function(Object) show) =>
                  s == null
                  ? inherited
                  : context.tr('default_with_value', {'value': show(s.value)});
              // The source line shows only while the field is blank: once the
              // client sets its own value, nothing is inherited.
              Widget? source(InheritedSetting? s, {required bool unset}) =>
                  s == null || !unset ? null : _InheritedSourceText(s.source);
              // The field already ends in "days", so the inherited count is
              // the bare number: "Default (30)", not "Default (30 days) days".
              String days(Object v) => '$v';

              final currency = inheritedFor('currency_id');
              final language = inheritedFor('language_id');
              final terms = inheritedFor('payment_terms');
              final validUntil = inheritedFor('valid_until');
              final rate = inheritedFor('default_task_rate');
              final reminders = inheritedFor('send_reminders');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClientEditFieldPair(
                    left: SearchableDropdownField<Currency>(
                      label: context.tr('currency'),
                      hintText: hint(
                        currency,
                        (id) => statics.currency('$id')?.name ?? '$id',
                      ),
                      helper: source(currency, unset: draft.currencyId.isEmpty),
                      items: currencies,
                      initialValue: statics.currency(draft.currencyId),
                      displayString: (c) => c.name,
                      idOf: (c) => c.id,
                      onChanged: (c) => vm.setCurrencyId(c?.id ?? ''),
                    ),
                    right: SearchableDropdownField<Language>(
                      label: context.tr('language'),
                      hintText: hint(
                        language,
                        (id) => statics.language('$id')?.name ?? '$id',
                      ),
                      helper: source(language, unset: draft.languageId.isEmpty),
                      items: languages,
                      initialValue: statics.language(draft.languageId),
                      displayString: (l) => l.name,
                      idOf: (l) => l.id,
                      onChanged: (l) => vm.setLanguageId(l?.id ?? ''),
                    ),
                  ),
                  ClientEditFieldPair(
                    left: EntityEditField(
                      label: context.tr('payment_terms'),
                      hintText: hint(terms, days),
                      helper: source(terms, unset: draft.paymentTerms.isEmpty),
                      suffixText: daysSuffix,
                      initial: draft.paymentTerms,
                      keyboardType: TextInputType.number,
                      onChanged: vm.setPaymentTerms,
                    ),
                    // "Quote valid until", not "Valid until": on a client it
                    // is a number of days for its quotes, not a date of its
                    // own.
                    right: EntityEditField(
                      label: context.tr('quote_valid_until'),
                      hintText: hint(validUntil, days),
                      helper: source(validUntil, unset: vm.validUntil.isEmpty),
                      suffixText: daysSuffix,
                      initial: vm.validUntil,
                      keyboardType: TextInputType.number,
                      onChanged: vm.setValidUntil,
                    ),
                  ),
                  ClientEditFieldPair(
                    left: EntityEditField(
                      label: context.tr('task_rate'),
                      hintText: hint(rate, _plainNumber),
                      helper: source(rate, unset: taskRate.isEmpty),
                      initial: taskRate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: vm.setDefaultTaskRate,
                    ),
                    right: _SendRemindersPicker(
                      vm: vm,
                      inherited: reminders,
                      helper: source(
                        reminders,
                        unset: vm.sendReminders == null,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Who the client is, for reporting and e-invoicing.
          FormGroupHeading(context.tr('profile')),
          ClientEditFieldPair(
            left: SearchableDropdownField<Industry>(
              label: context.tr('industry'),
              items: industries,
              initialValue: statics.industry(draft.industryId),
              displayString: (i) => i.name,
              idOf: (i) => i.id,
              onChanged: (i) => vm.setIndustryId(i?.id ?? ''),
            ),
            right: SearchableDropdownField<Size>(
              label: context.tr('size_id'),
              items: sizes,
              initialValue: statics.size(draft.sizeId),
              displayString: (s) => s.name,
              idOf: (s) => s.id,
              onChanged: (s) => vm.setSizeId(s?.id ?? ''),
            ),
          ),
          ClientEditFieldPair(
            left: SearchableDropdownField<String>(
              label: context.tr('classification'),
              items: _classifications,
              initialValue: draft.classification.isEmpty
                  ? null
                  : draft.classification,
              displayString: (v) => context.tr(v),
              idOf: (v) => v,
              onChanged: (v) => vm.setClassification(v ?? ''),
            ),
            right: EntityEditField(
              label: context.tr('routing_id'),
              initial: draft.routingId,
              onChanged: vm.setRoutingId,
              autocorrect: false,
            ),
          ),
          FormGroupHeading(context.tr('tax')),
          LabeledSwitchGroup(
            items: [
              LabeledSwitchItem(
                label: context.tr('tax_exempt'),
                value: draft.isTaxExempt,
                onChanged: vm.setIsTaxExempt,
              ),
              LabeledSwitchItem(
                label: context.tr('valid_vat_number'),
                value: draft.hasValidVatNumber,
                onChanged: vm.setHasValidVatNumber,
              ),
            ],
          ),
          ClientVerificationChecks(vm: vm),
        ],
      ),
    );
  }
}

/// Group (`group_settings_id`) picker — repo-backed (bundled group settings),
/// so it streams the list and resolves the current selection by id. Clearing
/// sets the override back to none.
class _GroupPicker extends StatelessWidget {
  const _GroupPicker({required this.vm});
  final ClientEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final services = context.read<Services>();
    return StreamBuilder<List<GroupSetting>>(
      stream: services.groupSettings.watchAll(companyId: vm.companyId),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const <GroupSetting>[];
        GroupSetting? selected;
        for (final g in groups) {
          if (g.id == vm.draft.groupSettingsId) {
            selected = g;
            break;
          }
        }
        return SearchableDropdownField<GroupSetting>(
          label: context.tr('group'),
          items: groups,
          initialValue: selected,
          displayString: (g) => g.name.isEmpty ? g.id : g.name,
          idOf: (g) => g.id,
          onChanged: (g) => vm.setGroupSettingsId(g?.id ?? ''),
          // An empty list is "Loading" only until the stream answers; a
          // company with no groups then reads None, not Loading forever.
          emptyHintKey: snapshot.hasData ? 'none' : 'loading',
        );
      },
    );
  }
}

/// Tri-state send-reminders cascade override: Default (inherit company) /
/// Enabled / Disabled. The `__default__` sentinel item maps to a cleared
/// override (no per-client `send_reminders` key).
class _SendRemindersPicker extends StatelessWidget {
  const _SendRemindersPicker({
    required this.vm,
    required this.inherited,
    required this.helper,
  });
  final ClientEditViewModel vm;

  /// What Default resolves to, for "Default (Enabled)"; null says "Default".
  final InheritedSetting? inherited;

  /// Where Default comes from, while Default is chosen.
  final Widget? helper;

  static const String _inheritKey = '__default__';

  @override
  Widget build(BuildContext context) {
    final reminders = vm.sendReminders;
    final current = reminders == null
        ? _inheritKey
        : (reminders ? 'enabled' : 'disabled');
    return SearchableDropdownField<String>(
      label: context.tr('send_reminders'),
      items: const [_inheritKey, 'enabled', 'disabled'],
      initialValue: current,
      helper: helper,
      displayString: (v) => v != _inheritKey
          ? context.tr(v)
          : switch (inherited?.value) {
              final bool on => context.tr('default_with_value', {
                'value': context.tr(on ? 'enabled' : 'disabled'),
              }),
              _ => context.tr('default'),
            },
      idOf: (v) => v,
      onChanged: (v) {
        switch (v) {
          case 'enabled':
            vm.setSendReminders(true);
          case 'disabled':
            vm.setSendReminders(false);
          default:
            vm.setSendReminders(null); // Default / cleared → inherit.
        }
      },
    );
  }
}

/// A whole number without its `.0` ("75", not "75.0"); anything else as is.
String _plainNumber(Object v) {
  if (v is num && v % 1 == 0) return v.toInt().toString();
  return '$v';
}

/// The line under a blank cascade field naming where its value comes from.
class _InheritedSourceText extends StatelessWidget {
  const _InheritedSourceText(this.source);
  final InheritedSource source;

  @override
  Widget build(BuildContext context) {
    final text = switch (source) {
      FromGroup(:final name) => context.tr('inherited_from_group', {
        'name': name,
      }),
      FromCompany() => context.tr('inherited_from_company'),
    };
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: context.inTheme.ink3),
    );
  }
}

/// The company's settings and the company's groups, for resolving what a
/// blank client setting inherits. The streams are opened once, not on every
/// keystroke's rebuild of the form.
class _CascadeSources extends StatefulWidget {
  const _CascadeSources({required this.companyId, required this.builder});

  final String companyId;
  final Widget Function(
    BuildContext context,
    CompanySettings? companySettings,
    List<GroupSetting>? groups,
  )
  builder;

  @override
  State<_CascadeSources> createState() => _CascadeSourcesState();
}

class _CascadeSourcesState extends State<_CascadeSources> {
  late final Stream<Company?> _company;
  // Archived groups too: a client can still belong to one, and the server
  // still cascades through it.
  late final Stream<List<GroupSetting>> _groups;

  @override
  void initState() {
    super.initState();
    final services = context.read<Services>();
    _company = services.company.watchCompany(widget.companyId);
    _groups = services.groupSettings.watchAllIncludingArchived(
      companyId: widget.companyId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Company?>(
      stream: _company,
      builder: (context, company) => StreamBuilder<List<GroupSetting>>(
        stream: _groups,
        builder: (context, groups) =>
            widget.builder(context, company.data?.settings, groups.data),
      ),
    );
  }
}
