import 'package:collection/collection.dart';

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
/// taken from [edited]. A list that changed keeps, item by item, the `id` and
/// `key` the stored list has at the same place.
///
/// [fromJson] rebuilds the record from the merged wire map; [keepStored]
/// then puts back what the wire does not carry — the stored record's id,
/// local state and timestamps, and every list that did not change, as the
/// stored domain objects themselves. [changed] is the set of wire keys taken
/// from [edited]. Returns [stored] itself when nothing changed.
T carryChangedFields<T>({
  required T sent,
  required T edited,
  required T stored,
  required Map<String, dynamic> Function(T record) toJson,
  required T Function(Map<String, dynamic> json) fromJson,
  required T Function(T merged, T stored, Set<String> changed) keepStored,
}) {
  const equality = DeepCollectionEquality();
  final before = toJson(sent);
  final after = toJson(edited);
  final changed = <String>{
    for (final key in {...before.keys, ...after.keys})
      if (key != 'id' && !equality.equals(before[key], after[key])) key,
  };
  if (changed.isEmpty) return stored;
  final merged = toJson(stored);
  for (final key in changed) {
    merged[key] = _keepIdentity(after[key], merged[key]);
  }
  return keepStored(fromJson(merged), stored, changed);
}

/// [edited]'s value, with a list's items keeping the `id` / `key` the
/// [stored] list has at the same index.
Object? _keepIdentity(Object? edited, Object? stored) {
  if (edited is! List || stored is! List) return edited;
  return [
    for (var i = 0; i < edited.length; i++)
      if (edited[i] is Map<String, dynamic> &&
          i < stored.length &&
          stored[i] is Map<String, dynamic>)
        {
          ...edited[i] as Map<String, dynamic>,
          for (final id in const ['id', 'key'])
            if ((stored[i] as Map<String, dynamic>)[id] case final String v
                when v.isNotEmpty)
              id: v,
        }
      else
        edited[i],
  ];
}
