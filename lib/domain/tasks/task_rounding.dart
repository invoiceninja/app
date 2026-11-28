import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/group_setting.dart';

/// The interval, in seconds, the server rounds a task's time entries *up* to
/// on every save (`TaskRepository::roundTimeLog`), or 1 when it doesn't round
/// up: `task_round_to_nearest` of 0 or 1, or `task_round_up` off (rounding
/// down never moves an end past the moment it was stopped).
///
/// Resolved the way the server's `getSetting` does: the client's settings,
/// then its group's, then the company's — the first level that sets the key.
/// Pass whichever rows are loaded; a null level is skipped. The server's
/// defaults are `task_round_up = true`, `task_round_to_nearest = 1`.
int taskRoundUpSeconds({
  Client? client,
  GroupSetting? group,
  Company? company,
}) {
  final roundUp =
      _bool(client?.settings?['task_round_up']) ??
      _bool(group?.settings?['task_round_up']) ??
      company?.settings.taskRoundUp ??
      true;
  if (!roundUp) return 1;
  final seconds =
      _int(client?.settings?['task_round_to_nearest']) ??
      _int(group?.settings?['task_round_to_nearest']) ??
      company?.settings.taskRoundToNearest?.toInt() ??
      1;
  return seconds > 1 ? seconds : 1;
}

/// A sparse settings map's value as the server reads it: absent, null or ''
/// means "inherit".
bool? _bool(Object? raw) => switch (raw) {
  final bool b => b,
  final num n => n != 0,
  final String s when s == 'true' || s == '1' => true,
  final String s when s == 'false' || s == '0' => false,
  _ => null,
};

int? _int(Object? raw) => switch (raw) {
  final num n => n.toInt(),
  final String s when s.trim().isNotEmpty => num.tryParse(s.trim())?.toInt(),
  _ => null,
};
