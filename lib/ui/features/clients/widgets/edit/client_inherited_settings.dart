import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/domain/group_setting.dart';

/// Where a client's blank cascade setting takes its value from.
sealed class InheritedSource {
  const InheritedSource();
}

/// The client's group sets it.
class FromGroup extends InheritedSource {
  const FromGroup(this.name);
  final String name;
}

/// The company sets it (the client has no group, or its group leaves the
/// setting blank too).
class FromCompany extends InheritedSource {
  const FromCompany();
}

/// A blank client setting's effective value and where it comes from.
typedef InheritedSetting = ({Object value, InheritedSource source});

/// The cascade the server runs for a client setting left blank
/// (`Client::getSetting`): the client's group, then the company. [key] is the
/// wire key (`currency_id`, `payment_terms`, …). As on the server, a group
/// that holds the key at all decides it, even blank — which reads here as
/// "not known" rather than the company's value.
///
/// Null — the caller then says a plain "Default" — when the answer is not
/// known: the client names a group that has not loaded ([groups] null) or is
/// not in it, or nothing up the cascade sets a value. Saying "From company"
/// for a client whose group might set the value would be a guess.
InheritedSetting? inheritedClientSetting(
  String key, {
  required String groupId,
  required List<GroupSetting>? groups,
  required CompanySettings? companySettings,
}) {
  if (groupId.isNotEmpty) {
    if (groups == null) return null;
    GroupSetting? group;
    for (final g in groups) {
      if (g.id == groupId) {
        group = g;
        break;
      }
    }
    if (group == null) return null;
    final raw = group.settings?[key];
    if (raw != null) {
      final fromGroup = _present(raw);
      if (fromGroup == null) return null;
      return (
        value: fromGroup,
        source: FromGroup(group.name.isEmpty ? group.id : group.name),
      );
    }
  }
  if (companySettings == null) return null;
  final fromCompany = _present(companySettings.toJson()[key]);
  if (fromCompany == null) return null;
  return (value: fromCompany, source: const FromCompany());
}

/// [raw] when it holds a value: not null, not a blank string. A zero task
/// rate is "no rate" on the server, so it does not count either.
Object? _present(Object? raw) {
  if (raw == null) return null;
  if (raw is String) return raw.trim().isEmpty ? null : raw.trim();
  if (raw is num && raw == 0) return null;
  return raw;
}
