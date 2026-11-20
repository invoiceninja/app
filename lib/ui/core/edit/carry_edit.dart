import 'package:collection/collection.dart';

import 'package:admin/data/models/domain/billing/invitation.dart';

/// What [carryChangedFields] made of an edit: the record the editor opens on,
/// and the wire keys of lists it could not carry safely (and kept as stored).
class CarriedEdit<T> {
  const CarriedEdit(this.record, {this.dropped = const {}});

  final T record;
  final Set<String> dropped;
}

/// How a changed list's items keep the server's identity when an edit is
/// carried. The server matches each list its own way, so each is matched
/// the way it is — never by guesswork that hands one item's id to another.
enum CarriedList {
  /// No identity to keep: the server drops a line item's `id` / `_id`
  /// (`CleanLineItems::cleanItem`), so the edited items go as they are.
  asEdited,

  /// Contacts: the server updates a contact by `id` and deletes the stored
  /// ones a save leaves out (`ClientContactRepository::save`). Same length:
  /// each edited contact keeps the stored `id` at its place. A length that
  /// changed (one added or removed while the create was out) can't be
  /// matched safely: the stored list is kept and the key reported dropped.
  byPosition,
}

/// The record a new record's editor opens on when an edit was typed while
/// its create was out (docs/after-saving.md): [stored] — the server's copy —
/// with only what changed between [sent] (the draft the create sent) and
/// [edited] (the form's draft when the create came back) laid over it.
///
/// Laying the whole edited draft over the record would send, on the next
/// Save, what the create form never had: contacts without ids (the server
/// deletes and recreates them), invitations without keys (deleted and
/// recreated, keys and signing state lost), blank fields the server filled
/// (a due date from the terms). So the fields are compared on the wire
/// ([toJson], the record's `toApiJson`) and only a changed top-level key is
/// taken from [edited]; a changed list keeps identity as [lists] says
/// (default [CarriedList.asEdited]). Invitations are matched by contact in
/// [keepStoredInvitations].
///
/// [fromJson] rebuilds the record from the merged wire map; [keepStored]
/// then puts back what the wire does not carry — the stored record's id,
/// local state and timestamps, and every list that did not change, as the
/// stored domain objects themselves. Its `changed` is the set of wire keys
/// taken from [edited]. Returns [stored] itself when nothing changed.
CarriedEdit<T> carryChangedFields<T>({
  required T sent,
  required T edited,
  required T stored,
  required Map<String, dynamic> Function(T record) toJson,
  required T Function(Map<String, dynamic> json) fromJson,
  required T Function(T merged, T stored, Set<String> changed) keepStored,
  Map<String, CarriedList> lists = const {},
}) {
  const equality = DeepCollectionEquality();
  final before = toJson(sent);
  final after = toJson(edited);
  final changed = <String>{
    for (final key in {...before.keys, ...after.keys})
      if (key != 'id' && !equality.equals(before[key], after[key])) key,
  };
  final dropped = <String>{};
  final merged = toJson(stored);
  for (final key in changed) {
    final value = after[key];
    final current = merged[key];
    if (lists[key] == CarriedList.byPosition &&
        value is List &&
        current is List) {
      if (value.length != current.length) {
        dropped.add(key);
        continue;
      }
      merged[key] = [
        for (var i = 0; i < value.length; i++)
          if (value[i] case final Map<String, dynamic> item
              when current[i] is Map<String, dynamic>)
            {...item, 'id': (current[i] as Map<String, dynamic>)['id']}
          else
            value[i],
      ];
      continue;
    }
    merged[key] = value;
  }
  final taken = changed.difference(dropped);
  if (taken.isEmpty) return CarriedEdit(stored, dropped: dropped);
  return CarriedEdit(
    keepStored(fromJson(merged), stored, taken),
    dropped: dropped,
  );
}

/// The invitations of a carried edit: each one for a contact the stored
/// record already invites is that stored invitation — its key, signing
/// state and history — since the server finds an invitation by its key
/// alone (`getInvitation`); one for a contact newly ticked carries no key, so
/// the server makes it; one unticked is simply gone.
List<Invitation> keepStoredInvitations(
  List<Invitation> edited,
  List<Invitation> stored,
) => [
  for (final invitation in edited)
    stored.firstWhereOrNull(
          (s) =>
              (invitation.clientContactId.isNotEmpty &&
                  s.clientContactId == invitation.clientContactId) ||
              (invitation.vendorContactId.isNotEmpty &&
                  s.vendorContactId == invitation.vendorContactId),
        ) ??
        invitation.copyWith(id: '', key: ''),
];
