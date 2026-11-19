import 'package:flutter/widgets.dart';

import 'package:admin/data/models/domain/report_payload.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/utils/formatting.dart';

/// Localization key of a report date preset.
String reportPresetLabelKey(ReportDatePreset preset) => switch (preset) {
  ReportDatePreset.allTime => 'all_time',
  ReportDatePreset.today => 'today',
  ReportDatePreset.last7 => 'last_7_days',
  ReportDatePreset.last30 => 'last_30_days',
  ReportDatePreset.last365 => 'last_365_days',
  ReportDatePreset.thisMonth => 'this_month',
  ReportDatePreset.lastMonth => 'last_month',
  ReportDatePreset.thisQuarter => 'this_quarter',
  ReportDatePreset.lastQuarter => 'last_quarter',
  ReportDatePreset.thisYear => 'this_year',
  ReportDatePreset.lastYear => 'last_year',
  ReportDatePreset.custom => 'custom',
};

/// What the range control reads at rest: the preset's name, or the two dates
/// of a custom range in the company's format.
String reportRangeLabel(
  BuildContext context,
  ReportPayload payload,
  Formatter? formatter,
) {
  final start = payload.startDate;
  final end = payload.endDate;
  if (payload.datePreset == ReportDatePreset.custom &&
      start != null &&
      end != null) {
    return formatter?.dateRange(start.toIso(), end.toIso()) ??
        '${start.toIso()} – ${end.toIso()}';
  }
  return context.tr(reportPresetLabelKey(payload.datePreset));
}

/// The shared range popover speaks [DashboardDateRange]; the report request
/// speaks [ReportPayload]. The dashboard presets map one-to-one onto the
/// report presets; the reports' popover adds Today to its rail
/// (`kRangePickerPresetsWithToday`).
DashboardDateRange reportRangeAsPickerValue(ReportPayload payload) {
  final start = payload.startDate;
  final end = payload.endDate;
  if (payload.datePreset == ReportDatePreset.custom &&
      start != null &&
      end != null) {
    return DashboardCustomRange(start: start, end: end);
  }
  return DashboardPresetRange(switch (payload.datePreset) {
    ReportDatePreset.today => DashboardDatePreset.today,
    ReportDatePreset.last7 => DashboardDatePreset.last7,
    ReportDatePreset.last30 => DashboardDatePreset.last30,
    ReportDatePreset.last365 => DashboardDatePreset.last365,
    ReportDatePreset.thisMonth => DashboardDatePreset.thisMonth,
    ReportDatePreset.lastMonth => DashboardDatePreset.lastMonth,
    ReportDatePreset.thisQuarter => DashboardDatePreset.thisQuarter,
    ReportDatePreset.lastQuarter => DashboardDatePreset.lastQuarter,
    ReportDatePreset.thisYear => DashboardDatePreset.thisYear,
    ReportDatePreset.lastYear => DashboardDatePreset.lastYear,
    // A custom preset with a date missing is not a range yet.
    ReportDatePreset.allTime ||
    ReportDatePreset.custom => DashboardDatePreset.allTime,
  });
}

/// [payload] with the range the popover returned.
ReportPayload reportPayloadWithRange(
  ReportPayload payload,
  DashboardDateRange range,
) {
  switch (range) {
    case DashboardCustomRange():
      return payload.copyWith(
        datePreset: ReportDatePreset.custom,
        startDate: () => range.start,
        endDate: () => range.end,
      );
    case DashboardPresetRange():
      return payload.copyWith(
        datePreset: switch (range.preset) {
          DashboardDatePreset.today => ReportDatePreset.today,
          DashboardDatePreset.last7 => ReportDatePreset.last7,
          DashboardDatePreset.last30 => ReportDatePreset.last30,
          DashboardDatePreset.last365 => ReportDatePreset.last365,
          DashboardDatePreset.thisMonth => ReportDatePreset.thisMonth,
          DashboardDatePreset.lastMonth => ReportDatePreset.lastMonth,
          DashboardDatePreset.thisQuarter => ReportDatePreset.thisQuarter,
          DashboardDatePreset.lastQuarter => ReportDatePreset.lastQuarter,
          DashboardDatePreset.thisYear => ReportDatePreset.thisYear,
          DashboardDatePreset.lastYear => ReportDatePreset.lastYear,
          DashboardDatePreset.allTime => ReportDatePreset.allTime,
        },
        startDate: () => null,
        endDate: () => null,
      );
  }
}
