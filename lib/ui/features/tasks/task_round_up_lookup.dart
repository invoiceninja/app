import 'package:admin/app/services.dart';
import 'package:admin/domain/tasks/task_rounding.dart';

/// [taskRoundUpSeconds] for a task of [clientId], read from the rows the app
/// already holds — the client, its group, the company — so it makes no
/// request. A row not loaded yet is skipped, so a client or group override
/// the app has not seen falls back to the next level down; the server reads
/// the real rows. That errs safe: a missed interval only leaves a Start in
/// the tail blocked, as before. Never throws: 1 (no rounding) on failure.
Future<int> lookupTaskRoundUpSeconds(
  Services services, {
  required String companyId,
  required String clientId,
}) async {
  try {
    final company = await services.company.get(companyId);
    final client = clientId.isEmpty
        ? null
        : await services.clients
              .watch(companyId: companyId, id: clientId)
              .first;
    final groupId = client?.groupSettingsId ?? '';
    final group = groupId.isEmpty
        ? null
        : await services.groupSettings
              .watchByRealId(companyId: companyId, id: groupId)
              .first;
    return taskRoundUpSeconds(client: client, group: group, company: company);
  } catch (_) {
    return 1;
  }
}
