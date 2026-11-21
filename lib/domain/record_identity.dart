import 'package:collection/collection.dart';

import 'package:admin/data/models/domain/billing/invitation.dart';

/// Giving a draft that was written before its record existed the identity
/// the server gave the record's lists, matched the way the server matches
/// each (docs/after-saving.md). A form opened on a record before its create
/// landed — offline, or past the 30 s wait — holds such a draft; sent as it
/// is, the server would delete and recreate the contacts.

/// [draft] with each item that has no id taking the id of the [stored] item
/// at its place — only while both lists are the same length. The server
/// updates a contact by `id` and deletes the stored ones a save leaves out
/// (`ClientContactRepository::save`), so a list whose length changed can't be
/// matched by place: it is left as it is.
List<T> idsByPosition<T>(
  List<T> draft,
  List<T> stored, {
  required String Function(T item) idOf,
  required T Function(T item, String id) withId,
}) {
  if (draft.length != stored.length) return draft;
  return [
    for (var i = 0; i < draft.length; i++)
      idOf(draft[i]).isEmpty && idOf(stored[i]).isNotEmpty
          ? withId(draft[i], idOf(stored[i]))
          : draft[i],
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
