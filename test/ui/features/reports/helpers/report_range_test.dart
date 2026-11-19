import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/report_payload.dart';
import 'package:admin/data/models/value/dashboard_filter.dart';
import 'package:admin/ui/features/reports/helpers/report_range.dart';

void main() {
  test('every report preset but custom round-trips through the popover', () {
    for (final preset in ReportDatePreset.values) {
      if (preset == ReportDatePreset.custom) continue;
      final payload = ReportPayload(datePreset: preset);
      final back = reportPayloadWithRange(
        payload,
        reportRangeAsPickerValue(payload),
      );
      expect(back.datePreset, preset, reason: preset.name);
    }
  });

  test('Today stays a preset, so a remembered report rolls with the day', () {
    final picked = reportPayloadWithRange(
      const ReportPayload(datePreset: ReportDatePreset.thisYear),
      const DashboardPresetRange(DashboardDatePreset.today),
    );
    expect(picked.datePreset, ReportDatePreset.today);
    expect(picked.startDate, isNull);
    expect(picked.endDate, isNull);
    expect(reportPresetLabelKey(ReportDatePreset.today), 'today');
  });

  test('the reports rail offers Today first', () {
    expect(kRangePickerPresetsWithToday.first, DashboardDatePreset.today);
    expect(kRangePickerPresets, isNot(contains(DashboardDatePreset.today)));
  });
}
