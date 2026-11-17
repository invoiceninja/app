import 'package:decimal/decimal.dart';

import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/group_setting.dart';
import 'package:admin/data/models/domain/project.dart';
import 'package:admin/data/models/domain/task.dart';

/// Resolve a task's effective hourly rate via the Invoice Ninja cascade:
///
///   `task.rate → project.taskRate → client.settings.default_task_rate →
///    group.settings.default_task_rate → company.settings.default_task_rate`
///
/// taking the first strictly-positive value (0 / absent means "inherit from
/// the next level"). Mirrors admin-portal's `taskRateSelector`
/// (`lib/redux/task/task_selectors.dart`). Pass whichever related entities
/// are loaded; `null` levels are skipped. The result is what an invoice line
/// derived from this task should cost — a task left at rate 0 under a company
/// (or client / project) default invoices at the inherited rate, not $0.
Decimal resolveTaskRate({
  required Task task,
  Project? project,
  Client? client,
  GroupSetting? group,
  Company? company,
}) => resolveTaskRateWithSource(
  task: task,
  project: project,
  client: client,
  group: group,
  company: company,
).rate;

/// The level of the task-rate cascade a resolved rate came from.
/// [none] means nothing up the cascade sets one: the rate is the task's own,
/// which is then zero.
enum TaskRateSource { task, project, client, group, company, none }

/// [resolveTaskRate] together with the level that answered — what the task
/// edit form names under a blank Rate field ("From project"). One walk of the
/// cascade, so the figure and its source can never disagree.
({Decimal rate, TaskRateSource source}) resolveTaskRateWithSource({
  required Task task,
  Project? project,
  Client? client,
  GroupSetting? group,
  Company? company,
}) {
  if (task.rate > Decimal.zero) {
    return (rate: task.rate, source: TaskRateSource.task);
  }
  if (project != null && project.taskRate > Decimal.zero) {
    return (rate: project.taskRate, source: TaskRateSource.project);
  }
  final clientRate = _settingsTaskRate(client?.settings);
  if (clientRate != null) {
    return (rate: clientRate, source: TaskRateSource.client);
  }
  final groupRate = _settingsTaskRate(group?.settings);
  if (groupRate != null) {
    return (rate: groupRate, source: TaskRateSource.group);
  }
  final companyRate = company?.settings.defaultTaskRate;
  if (companyRate != null && companyRate > 0) {
    final parsed = Decimal.tryParse(companyRate.toString());
    if (parsed != null) return (rate: parsed, source: TaskRateSource.company);
  }
  return (rate: task.rate, source: TaskRateSource.none);
}

/// Read a strictly-positive `default_task_rate` out of a sparse settings map.
/// Client / GroupSetting carry `settings` as raw JSON, where the value may be
/// a `num` or a `String`. Returns null when absent, unparseable, or ≤ 0.
Decimal? _settingsTaskRate(Map<String, dynamic>? settings) {
  final raw = settings?['default_task_rate'];
  if (raw == null) return null;
  final parsed = Decimal.tryParse(raw.toString());
  return (parsed != null && parsed > Decimal.zero) ? parsed : null;
}
