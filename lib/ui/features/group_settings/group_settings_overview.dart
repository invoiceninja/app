import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company_gateway.dart';
import 'package:admin/data/models/domain/design.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/data/models/domain/payment_term.dart';
import 'package:admin/domain/entity_state.dart';
import 'package:admin/domain/payment_types.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/count_labels.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/detail_row_columns.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/group_settings/group_setting_actions.dart'
    show kGroupSettingsLandingRoute;
import 'package:admin/ui/features/group_settings/group_setting_overrides.dart';
import 'package:admin/ui/features/settings/settings_search_catalog.dart';
import 'package:admin/ui/features/settings/views/advanced/email_settings/email_settings_body.dart'
    show formatSendTimeHour;
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/template_options.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/utils/notes_html.dart';

/// A group's Overview tab: every setting the group overrides, under the
/// settings page it lives on, each with that page's label and the value the
/// page would show — or, when it overrides nothing, a plain line saying the
/// group follows the company and the way to change that.
///
/// [onConfigure] opens the settings editor at group scope on [route]; null
/// (an unsynced or deleted group) draws the buttons disabled.
class GroupSettingsOverview extends StatefulWidget {
  const GroupSettingsOverview({
    super.key,
    required this.group,
    required this.companyId,
    required this.onConfigure,
    this.formatter,
  });

  final GroupSetting group;
  final String companyId;
  final void Function(String route)? onConfigure;
  final Formatter? formatter;

  @override
  State<GroupSettingsOverview> createState() => _GroupSettingsOverviewState();
}

class _GroupSettingsOverviewState extends State<GroupSettingsOverview> {
  // Hoisted out of `build`: a stream made there is a new subscription, and a
  // first frame of nothing, on every rebuild.
  late final Stream<List<Design>> _designs;
  late final Stream<List<PaymentTerm>> _terms;
  late final Stream<List<CompanyGateway>> _gateways;

  @override
  void initState() {
    super.initState();
    final services = context.read<Services>();
    _designs = services.designs.watchAll(companyId: widget.companyId);
    _terms = services.paymentTerms.watchAll(companyId: widget.companyId);
    // Gateways are bundled reference data, a handful of rows: one page
    // holds them all, in every state (a group can still name one archived
    // since).
    _gateways = services.companyGateways.watchPage(
      companyId: widget.companyId,
      states: EntityState.values.toSet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = overriddenSettingKeys(widget.group.settings);
    if (keys.isEmpty) {
      return _NoOverrides(
        onConfigure: widget.onConfigure == null
            ? null
            : () => widget.onConfigure!(kGroupSettingsLandingRoute),
      );
    }
    return StreamBuilder<List<Design>>(
      stream: _designs,
      builder: (context, designs) => StreamBuilder<List<PaymentTerm>>(
        stream: _terms,
        builder: (context, terms) => StreamBuilder<List<CompanyGateway>>(
          stream: _gateways,
          builder: (context, gateways) => _Sections(
            keys: keys,
            settings: widget.group.settings ?? const <String, dynamic>{},
            lookups: SettingOverrideLookups(
              services: context.read<Services>(),
              designs: designs.data,
              terms: terms.data,
              gateways: gateways.data,
              formatter: widget.formatter,
              groupSettings: widget.group.settings,
            ),
            onConfigure: widget.onConfigure,
          ),
        ),
      ),
    );
  }
}

class _NoOverrides extends StatelessWidget {
  const _NoOverrides({required this.onConfigure});

  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    return DashboardCardShell(
      title: context.tr('settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('group_overrides_none'),
            key: const ValueKey('group-overrides-none'),
            style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: InSpacing.xs),
          Text(
            context.tr('group_overrides_none_help'),
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink2),
          ),
          SizedBox(height: InSpacing.md(context)),
          FilledButton.icon(
            key: const ValueKey('group-overview-configure'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: onConfigure,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(context.tr('configure_settings')),
          ),
        ],
      ),
    );
  }
}

/// One card per settings page the group overrides something on, in the
/// settings list's own order; anything no page binds goes last, under Other.
class _Sections extends StatelessWidget {
  const _Sections({
    required this.keys,
    required this.settings,
    required this.lookups,
    required this.onConfigure,
  });

  final List<String> keys;
  final Map<String, dynamic> settings;
  final SettingOverrideLookups lookups;
  final void Function(String route)? onConfigure;

  @override
  Widget build(BuildContext context) {
    final bySection = <String, List<String>>{};
    for (final k in keys) {
      bySection.putIfAbsent(settingOverrideSection(k), () => []).add(k);
    }
    final ordered = <(String, String?, List<String>)>[
      for (final s in kSettingsSections)
        if (bySection.containsKey(s.slug))
          (s.titleKey, s.route, bySection.remove(s.slug)!),
      // A slug with no section def (`other`) and anything left over.
      for (final e in bySection.entries) ('other', null, e.value),
    ];
    final gap = SizedBox(height: InSpacing.lg(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (titleKey, route, sectionKeys)) in ordered.indexed) ...[
          if (i > 0) gap,
          DashboardCardShell(
            key: ValueKey('group-overview-section-$titleKey'),
            title: context.tr(titleKey),
            trailing: route == null
                ? null
                : TextButton(
                    onPressed: onConfigure == null
                        ? null
                        : () => onConfigure!(route),
                    child: Text(context.tr('configure')),
                  ),
            child: DetailRowColumns(
              children: [
                for (final k in sectionKeys)
                  _row(context, k, settings[k], lookups),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Widget _row(
  BuildContext context,
  String key,
  Object? raw,
  SettingOverrideLookups l,
) {
  final label = settingOverrideLabel(context, key);
  final kind = settingOverrideKind(key);
  if (kind == OverrideValueKind.user && raw is String && raw.isNotEmpty) {
    return DetailInfoRow(
      label: label,
      value: '',
      copyable: false,
      child: UserNameLabel(userId: raw),
    );
  }
  return DetailInfoRow(
    label: label,
    value: settingOverrideValueText(context, key, raw, l),
    copyable: false,
  );
}

/// [key]'s label: the keys [settingOverrideLabelKeys] names, joined with
/// ` · `; else the bundle's word for the key (or the key less its `_id`);
/// else the key worded — never the raw key.
String settingOverrideLabel(BuildContext context, String key) {
  final keys = settingOverrideLabelKeys(key);
  if (keys != null) return keys.map(context.tr).join(' · ');
  final stem = key.endsWith('_id') ? key.substring(0, key.length - 3) : key;
  return context.trIfDefined(key) ?? context.trIfDefined(stem) ?? _worded(stem);
}

/// `client_portal_foo` → "Client portal foo": a key no page and no bundle
/// names, said in words rather than shown as a key.
String _worded(String key) {
  final words = key.split('_').where((w) => w.isNotEmpty).join(' ');
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1);
}

/// What the Overview's rows look values up in. [services] supplies the
/// statics; the lists are null until their watch first emits.
class SettingOverrideLookups {
  const SettingOverrideLookups({
    required this.services,
    required this.designs,
    required this.terms,
    required this.gateways,
    required this.formatter,
    required this.groupSettings,
  });

  final Services services;
  final List<Design>? designs;
  final List<PaymentTerm>? terms;
  final List<CompanyGateway>? gateways;
  final Formatter? formatter;
  final Map<String, dynamic>? groupSettings;
}

/// [raw] as the settings page shows it. A lookup that cannot be answered
/// (the statics or the designs are not loaded yet, or name a record this
/// device has never seen) reads "Unknown" — never the id.
String settingOverrideValueText(
  BuildContext context,
  String key,
  Object? raw,
  SettingOverrideLookups? l,
) {
  final kind = settingOverrideKind(key);
  if (raw == null) return '—';
  switch (kind) {
    case OverrideValueKind.secret:
      return '••••••••';
    case OverrideValueKind.code:
    case OverrideValueKind.custom:
      return context.tr('custom');
    default:
      break;
  }
  if (raw is Map || raw is List) return context.tr('custom');
  if (raw is bool) {
    return switch (kind) {
      OverrideValueKind.currencyFormat => context.tr(raw ? 'code' : 'symbol'),
      OverrideValueKind.roundDirection => context.tr(
        raw ? 'round_up' : 'round_down',
      ),
      OverrideValueKind.emailRecipients => context.tr(
        raw ? 'all_contacts' : 'primary_contact',
      ),
      _ => context.tr(raw ? 'enabled' : 'disabled'),
    };
  }
  final s = raw is double && raw == raw.truncateToDouble()
      ? '${raw.toInt()}'
      : '$raw'.trim();
  // Overridden to blank: the group sets the field to nothing on purpose.
  if (s.isEmpty) return '—';
  final unknown = context.tr('unknown');
  final statics = l?.services.statics;
  switch (kind) {
    case OverrideValueKind.currency:
      final c = statics?.currency(s);
      return c == null ? unknown : '${c.code} — ${c.name}';
    case OverrideValueKind.language:
      return statics?.language(s)?.name ?? unknown;
    case OverrideValueKind.country:
      return statics?.country(s)?.name ?? unknown;
    case OverrideValueKind.timezone:
      return statics?.timezone(s)?.name ?? unknown;
    case OverrideValueKind.dateFormat:
      final f = statics?.dateFormat(s);
      if (f == null || f.format.isEmpty) return unknown;
      return dateFormatSample(f.format, locale: l?.formatter?.settings.locale);
    case OverrideValueKind.paymentType:
      // One id, or — `hidden_payment_types` — a comma-separated list.
      final l10n = Localization.of(context);
      return [
        for (final id in s.split(','))
          if (id.trim().isNotEmpty)
            switch (statics?.paymentType(id.trim())) {
              final t? => paymentTypeName(l10n, t),
              null => unknown,
            },
      ].join(', ');
    case OverrideValueKind.design:
      for (final d in l?.designs ?? const <Design>[]) {
        if (d.id == s) return d.name;
      }
      return unknown;
    case OverrideValueKind.days:
      final n = int.tryParse(s);
      if (n == null) return s;
      // Named the way the terms picker names it ("Net 30") when a term with
      // that many days has a name of its own.
      if (key == 'payment_terms' || key == 'valid_until') {
        for (final t in l?.terms ?? const <PaymentTerm>[]) {
          if (t.numDays == n && t.name.trim().isNotEmpty) return t.name.trim();
        }
      }
      return dayCountLabel(context, n);
    case OverrideValueKind.frequency:
      if (s == '0') return context.tr('never');
      for (final (id, labelKey) in kEndlessReminderFrequencies) {
        if (id == s) return context.tr(labelKey);
      }
      return unknown;
    case OverrideValueKind.emailProvider:
      return _emailProviders[s] != null
          ? context.trIfDefined(_emailProviders[s]!) ?? _emailProviders[s]!
          : unknown;
    case OverrideValueKind.alignment:
      return switch (s.toUpperCase()) {
        'C' => context.tr('center'),
        'R' => context.tr('right'),
        'L' => context.tr('left'),
        _ => unknown,
      };
    case OverrideValueKind.hour:
      final h = int.tryParse(s);
      if (h == null || h < 1 || h > 24) return unknown;
      final ownMilitary = l?.groupSettings?['military_time'];
      final military = ownMilitary is bool
          ? ownMilitary
          : l?.formatter?.settings.enableMilitaryTime ?? false;
      return formatSendTimeHour(h, military: military);
    case OverrideValueKind.gateways:
      final byId = <String, CompanyGateway>{
        for (final g in l?.gateways ?? const <CompanyGateway>[]) g.id: g,
      };
      final names = [
        for (final id in s.split(','))
          if (id.trim().isNotEmpty)
            byId[id.trim()]?.resolveDisplayName(
                  gatewayName: statics
                      ?.gateway(byId[id.trim()]!.gatewayKey)
                      ?.name,
                ) ??
                unknown,
      ];
      return names.isEmpty ? '—' : names.join(', ');
    case OverrideValueKind.word:
      return context.trIfDefined(s) ??
          context.trIfDefined(s.toLowerCase()) ??
          s;
    case OverrideValueKind.html:
      final text = plainTextFromHtml(s, singleLine: true).trim();
      return text.isEmpty ? '—' : text;
    case OverrideValueKind.user:
      return unknown;
    case OverrideValueKind.plain:
    case OverrideValueKind.secret:
    case OverrideValueKind.code:
    case OverrideValueKind.custom:
    case OverrideValueKind.currencyFormat:
    case OverrideValueKind.roundDirection:
    case OverrideValueKind.emailRecipients:
      return s;
  }
}

/// `email_sending_method` → how the Email Settings provider picker names it.
/// A translation key where one exists, else the brand.
const Map<String, String> _emailProviders = {
  'default': 'default',
  'gmail': 'Gmail',
  'office365': 'microsoft',
  'microsoft': 'microsoft',
  'postmark': 'postmark',
  'client_postmark': 'postmark',
  'mailgun': 'mailgun',
  'client_mailgun': 'mailgun',
  'ses': 'Amazon SES',
  'client_ses': 'Amazon SES',
  'client_brevo': 'brevo',
  'smtp': 'smtp',
};
