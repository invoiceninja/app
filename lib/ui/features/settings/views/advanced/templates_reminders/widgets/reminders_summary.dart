import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/count_labels.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/template_options.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';

/// Where one reminder stands, read off the (cascade-resolved) settings.
///
/// A scheduled reminder (1–3, the quote reminder) is on, after [days] days,
/// relative to [scheduleKey] — a translation key that is also the wire value
/// (`after_due_date`). The endless reminder has no days, only a
/// [frequencyKey] (`freq_weekly`). Anything unset is null and is simply not
/// said; the row never invents a default the server would not apply.
typedef ReminderSummary = ({
  bool on,
  int? days,
  String? scheduleKey,
  String? frequencyKey,
});

ReminderSummary reminderSummaryFor(String templateKey, CompanySettings s) {
  String? nonEmpty(String? v) => v == null || v.isEmpty ? null : v;
  switch (templateKey) {
    case 'reminder1':
      return (
        on: s.enableReminder1 ?? false,
        days: s.numDaysReminder1,
        scheduleKey: nonEmpty(s.scheduleReminder1),
        frequencyKey: null,
      );
    case 'reminder2':
      return (
        on: s.enableReminder2 ?? false,
        days: s.numDaysReminder2,
        scheduleKey: nonEmpty(s.scheduleReminder2),
        frequencyKey: null,
      );
    case 'reminder3':
      return (
        on: s.enableReminder3 ?? false,
        days: s.numDaysReminder3,
        scheduleKey: nonEmpty(s.scheduleReminder3),
        frequencyKey: null,
      );
    case 'quote_reminder1':
      return (
        on: s.enableQuoteReminder1 ?? false,
        days: s.quoteNumDaysReminder1,
        scheduleKey: nonEmpty(s.quoteScheduleReminder1),
        frequencyKey: null,
      );
    case 'reminder_endless':
      final id = s.endlessReminderFrequencyId;
      String? frequency;
      for (final (value, key) in kEndlessReminderFrequencies) {
        if (value == id) frequency = key;
      }
      return (
        on: s.enableReminderEndless ?? false,
        days: null,
        scheduleKey: null,
        frequencyKey: frequency,
      );
    default:
      return (on: false, days: null, scheduleKey: null, frequencyKey: null);
  }
}

/// Every reminder the company can send, one row each, saying whether it
/// sends and when — the overview the template picker can't give, since it
/// shows one template at a time. The whole row is the target: it opens that
/// reminder in the editor above ([onOpen]), the same as picking it from the
/// Template dropdown.
class RemindersSummary extends StatelessWidget {
  const RemindersSummary({
    super.key,
    required this.options,
    required this.settings,
    required this.selectedKey,
    required this.onOpen,
  });

  /// The visible template options; the reminders among them are listed.
  final List<TemplateOption> options;
  final CompanySettings settings;
  final String selectedKey;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final reminders = [
      for (final o in options)
        if (o.isReminder) o,
    ];
    if (reminders.isEmpty) return const SizedBox.shrink();
    return FormSection(
      title: context.tr('reminders'),
      spacing: 0,
      children: [
        for (final o in reminders)
          _ReminderRow(
            option: o,
            summary: reminderSummaryFor(o.key, settings),
            selected: o.key == selectedKey,
            onTap: () => onOpen(o.key),
          ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.option,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final TemplateOption option;
  final ReminderSummary summary;
  final bool selected;
  final VoidCallback onTap;

  String _detail(BuildContext context) {
    final frequency = summary.frequencyKey;
    if (frequency != null) return context.tr(frequency);
    final days = summary.days;
    final schedule = summary.scheduleKey;
    return [
      if (days != null) dayCountLabel(context, days),
      if (schedule != null) context.tr(schedule),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final detail = summary.on ? _detail(context) : '';
    final state = context.tr(summary.on ? 'enabled' : 'off');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      selectedColor: tokens.ink,
      onTap: onTap,
      title: Text(context.tr(option.labelKey)),
      subtitle: detail.isEmpty
          ? null
          : Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.ink3),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateLabel(text: state, on: summary.on),
          const SizedBox(width: InSpacing.sm),
          Icon(Icons.chevron_right, size: 18, color: tokens.ink3),
        ],
      ),
    );
  }
}

/// "Enabled" / "Off" as a worded label — a rounded rectangle from the
/// tokens, never a pill.
class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.text, required this.on});

  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: on ? tokens.accentSoft : tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(InRadii.r1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: on ? tokens.accentInk : tokens.ink3,
        ),
      ),
    );
  }
}
