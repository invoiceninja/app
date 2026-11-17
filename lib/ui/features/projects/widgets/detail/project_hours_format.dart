import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/ui/features/projects/widgets/detail/project_progress_math.dart';
import 'package:admin/utils/formatting.dart';

/// Whether the project screen reads hours as `H:MM` rather than decimal
/// hours — the device's hours-format preference (`HoursFormatController`,
/// `DevicePrefKeys.hoursFormat`), the one the weekly timesheet's Total row
/// switches and the reports follow (`ReportHoursFormat`).
///
/// Put above the whole record by `ProjectDetailScreen`, so the standing card,
/// the progress chart and the Analytics tab all hear one answer. Absent, hours
/// read as decimal — the preference's default.
class ProjectHoursFormat extends InheritedWidget {
  const ProjectHoursFormat({
    super.key,
    required this.hoursMinutes,
    required super.child,
  });

  final bool hoursMinutes;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ProjectHoursFormat>()
          ?.hoursMinutes ??
      false;

  @override
  bool updateShouldNotify(ProjectHoursFormat oldWidget) =>
      oldWidget.hoursMinutes != hoursMinutes;
}

/// [hours] as a project figure: `12.5 h` (`fmtHours`, as it always read), or
/// `12:30` when [hoursMinutes] — `hoursMinutesText`, the timesheet's and the
/// reports' spelling, so one preference reads the same on every surface.
/// `H:MM` carries no unit: the colon already says hours and minutes.
String projectHoursText(double hours, {bool hoursMinutes = false}) =>
    hoursMinutes
    ? hoursMinutesText((hours * 3600).round())
    : '${fmtHours(hours)} h';

/// [builder] handed the hours-format answer, rebuilt when it changes — for a
/// surface that may sit outside the record's [ProjectHoursFormat] (the
/// Projects list's narrow rows and hours columns). Under the scope it reads
/// the scope; elsewhere it listens to the device preference itself.
class ProjectHoursFormatBuilder extends StatelessWidget {
  const ProjectHoursFormatBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool hoursMinutes) builder;

  @override
  Widget build(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<ProjectHoursFormat>();
    if (scoped != null) return builder(context, scoped.hoursMinutes);
    final pref = context.read<Services>().hoursFormat;
    return ValueListenableBuilder<String>(
      valueListenable: pref,
      builder: (context, _, _) => builder(context, pref.showsHoursMinutes),
    );
  }
}
