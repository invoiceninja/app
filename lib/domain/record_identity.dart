import 'package:collection/collection.dart';

import 'package:admin/data/models/domain/billing/invitation.dart';

/// Giving a draft that was written before its record existed the identity
/// the server gave the record's lists, matched the way the server matches
/// each (docs/after-saving.md). A form opened on a record before its create
/// landed — offline, or past the 30 s wait — holds such a draft; sent as it
/// is, the server would delete and recreate the contacts.

/// What a contact is matched on: its id, and who it is.
typedef ContactIdentity = ({
  String id,
  String email,
  String firstName,
  String lastName,
  bool isPrimary,
});

/// The stored id for each of [draft]'s contacts (null where the draft's own
/// id stands), or null when they can't all be matched safely — the list then
/// goes as the draft has it, and the server recreates what it must rather
/// than a contact taking another's id (and with it the other's portal link,
/// password and invitations).
///
/// The server updates a contact by `id` and deletes the stored ones a save
/// leaves out (`ClientContactRepository::save`), and it stores and returns
/// them primary first (`orderBy is_primary desc`), where the form keeps the
/// user's order. So:
///
/// - only lists of the same length are matched, and only stored contacts no
///   draft contact already names;
/// - a unique email on both sides matches first;
/// - the rest are paired in the server's order (primary first, stably), and a
///   pair stands only when it is the same person by name with no email on
///   either side — a contact removed and another added in its place is not;
/// - any pair that doesn't stand leaves the whole list unmatched.
List<String?>? storedContactIds(
  List<ContactIdentity> draft,
  List<ContactIdentity> stored,
) {
  if (draft.length != stored.length) return null;
  String norm(String s) => s.trim().toLowerCase();
  final named = {
    for (final d in draft)
      if (d.id.isNotEmpty) d.id,
  };
  final open = [
    for (var i = 0; i < stored.length; i++)
      if (!named.contains(stored[i].id) && stored[i].id.isNotEmpty) i,
  ];
  final wanting = [
    for (var i = 0; i < draft.length; i++)
      if (draft[i].id.isEmpty) i,
  ];
  if (wanting.length != open.length) return null;
  final result = List<String?>.filled(draft.length, null);
  if (wanting.isEmpty) return result;

  // A unique email on both sides.
  int count(Iterable<ContactIdentity> list, String email) =>
      list.where((c) => norm(c.email) == email).length;
  final draftLeft = <int>[];
  for (final i in wanting) {
    final email = norm(draft[i].email);
    final candidates = [
      for (final j in open)
        if (email.isNotEmpty && norm(stored[j].email) == email) j,
    ];
    if (email.isNotEmpty &&
        candidates.length == 1 &&
        count(draft, email) == 1 &&
        count(stored, email) == 1) {
      result[i] = stored[candidates.single].id;
      open.remove(candidates.single);
    } else {
      draftLeft.add(i);
    }
  }

  // The rest in the server's order: primary first, otherwise as listed.
  List<int> serverOrder(List<int> indexes, List<ContactIdentity> list) => [
    ...indexes.where((i) => list[i].isPrimary),
    ...indexes.where((i) => !list[i].isPrimary),
  ];
  final d = serverOrder(draftLeft, draft);
  final s = serverOrder(open, stored);
  if (d.length != s.length) return null;
  for (var k = 0; k < d.length; k++) {
    final a = draft[d[k]];
    final b = stored[s[k]];
    final samePerson =
        norm(a.email).isEmpty &&
        norm(b.email).isEmpty &&
        norm(a.firstName) == norm(b.firstName) &&
        norm(a.lastName) == norm(b.lastName);
    if (!samePerson) return null;
    result[d[k]] = b.id;
  }
  return result;
}

/// [draft] with [storedContactIds] applied — unchanged when they can't all be
/// matched.
List<T> withStoredContactIds<T>(
  List<T> draft,
  List<T> stored, {
  required ContactIdentity Function(T contact) identityOf,
  required T Function(T contact, String id) withId,
}) {
  final ids = storedContactIds(
    [for (final c in draft) identityOf(c)],
    [for (final c in stored) identityOf(c)],
  );
  if (ids == null) return draft;
  return [
    for (var i = 0; i < draft.length; i++)
      ids[i] == null ? draft[i] : withId(draft[i], ids[i]!),
  ];
}

/// [draft]'s invitations, each keyless one for a contact the [stored] record
/// invites becoming that stored invitation — its key and its signing state,
/// which the server applies with the key (`can_sign ?? false`). Matched by
/// contact, never by place: the server finds an invitation by its key alone
/// (`getInvitation`). An invitation with a key, or for a contact the record
/// doesn't invite, is left as it is.
List<Invitation> invitationsByContact(
  List<Invitation> draft,
  List<Invitation> stored,
) => [
  for (final invitation in draft)
    invitation.key.isNotEmpty
        ? invitation
        : stored.firstWhereOrNull(
                (s) =>
                    (invitation.clientContactId.isNotEmpty &&
                        s.clientContactId == invitation.clientContactId) ||
                    (invitation.vendorContactId.isNotEmpty &&
                        s.vendorContactId == invitation.vendorContactId),
              ) ??
              invitation,
];
