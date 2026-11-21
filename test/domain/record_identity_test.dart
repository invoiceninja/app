import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/record_identity.dart';

/// A draft written before its record existed takes the ids the server gave
/// the record's contacts — but only where it is sure which contact is which
/// (docs/after-saving.md). The server stores and returns contacts primary
/// first, where the form keeps the user's order, and a contact handed another
/// one's id takes that one's portal link, password and invitations.
void main() {
  ContactIdentity c(
    String firstName, {
    String id = '',
    String email = '',
    bool primary = false,
  }) => (
    id: id,
    email: email,
    firstName: firstName,
    lastName: '',
    isPrimary: primary,
  );

  test('a primary that is not first lands on the right contact', () {
    // The form: Ada, then Bo marked primary. The server: Bo first.
    final ids = storedContactIds(
      [c('Ada'), c('Bo', primary: true)],
      [c('Bo', id: 'id_b', primary: true), c('Ada', id: 'id_a')],
    );
    expect(ids, ['id_a', 'id_b']);
  });

  test('an email match wins over the place', () {
    final ids = storedContactIds(
      [c('Ada', email: 'b@x.test'), c('Bo', email: 'A@x.test')],
      [
        c('Ada', id: 'id_a', email: 'a@x.test'),
        c('Bo', id: 'id_b', email: 'b@x.test'),
      ],
    );
    expect(ids, ['id_b', 'id_a']);
  });

  test('a contact removed and another added in its place does not reuse '
      'its id', () {
    expect(
      storedContactIds(
        [c('Ada', email: 'a@x.test'), c('Cy', email: 'c@x.test')],
        [
          c('Ada', id: 'id_a', email: 'a@x.test'),
          c('Bo', id: 'id_b', email: 'b@x.test'),
        ],
      ),
      isNull,
    );
    expect(
      storedContactIds(
        [c('Ada'), c('Cy')],
        [c('Ada', id: 'id_a'), c('Bo', id: 'id_b')],
      ),
      isNull,
      reason: 'no email: a different name is a different person',
    );
  });

  test('a list of another length is not matched', () {
    expect(
      storedContactIds([c('Ada')], [c('Ada', id: 'id_a'), c('Bo', id: 'id_b')]),
      isNull,
    );
  });

  test('a contact that already has its id keeps it, and its stored '
      'contact is not handed out again', () {
    final ids = storedContactIds(
      [c('Ada', id: 'id_a'), c('Bo')],
      [c('Ada', id: 'id_a'), c('Bo', id: 'id_b')],
    );
    expect(ids, [null, 'id_b']);
  });
}
