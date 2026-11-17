import 'package:flutter/foundation.dart';

/// A client's or vendor's edit route asked to open on a new, blank contact —
/// the record screen's Contacts card "+ Add".
///
/// Carried as the route's `extra`, not a query parameter, so it never reaches
/// the saved navigation state: a restart must not reopen the editor with a
/// contact added. `MasterDetailLayout`'s full-screen toggle re-attaches the
/// route's `extra` to the URL it rewrites, so the request survives that; and
/// the edit view model is built once per screen, so the toggle cannot add a
/// second contact.
@immutable
class AddContactRequest {
  const AddContactRequest();

  /// Whether [extra] is this request.
  static bool of(Object? extra) => extra is AddContactRequest;

  @override
  bool operator ==(Object other) => other is AddContactRequest;

  @override
  int get hashCode => (AddContactRequest).hashCode;
}

/// A contact the edit screen should bring into view once — the one just
/// added, by the form's own "Add contact" or by the record screen's Contacts
/// card "+ Add" (`AddContactRequest`). Compared by identity: each add makes a
/// new one, so adding a second contact scrolls again.
class ContactReveal {
  ContactReveal(this.index);

  /// The contact's position in the list.
  final int index;
}
