/// How a client contact receives a document's email: in the To line, copied
/// in once (CC), or not at all. The wire carries this as two booleans,
/// `send_email` and `cc_only`, and the edit screen offers it as one choice of
/// three (`docs/contacts-and-invitations.md` § A contact's email is one choice
/// of three).
///
/// The server decides what the pair means on save
/// (`ClientContactRepository::save`): the primary contact is never CC-only
/// (`cc_only` forced false), and a CC-only contact never gets its own email
/// (`send_email` forced false). [contactEmailModeOf] reads the pair the same
/// way, so the form shows what the server will store.
enum ContactEmailMode { to, cc, none }

/// The choice a contact's stored flags amount to. CC-only wins over
/// `send_email` (the server clears the latter), except on the primary
/// contact, which the server never stores as CC-only.
ContactEmailMode contactEmailModeOf({
  required bool sendEmail,
  required bool ccOnly,
  required bool isPrimary,
}) {
  if (ccOnly && !isPrimary) return ContactEmailMode.cc;
  return sendEmail ? ContactEmailMode.to : ContactEmailMode.none;
}

/// The two wire flags for [mode].
({bool sendEmail, bool ccOnly}) contactEmailFlagsOf(ContactEmailMode mode) =>
    switch (mode) {
      ContactEmailMode.to => (sendEmail: true, ccOnly: false),
      ContactEmailMode.cc => (sendEmail: false, ccOnly: true),
      ContactEmailMode.none => (sendEmail: false, ccOnly: false),
    };
