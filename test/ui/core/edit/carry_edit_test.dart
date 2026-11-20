import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/contact_api_model.dart';
import 'package:admin/data/models/api/invitation_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/ui/core/edit/carry_edit_entities.dart';

/// An edit typed while a new record's create was out rides to the record's
/// editor (docs/after-saving.md) — but only what that edit changed. The rest
/// is the server's copy: laid over it wholesale, the create form's draft
/// would send contacts without ids and invitations without keys, which the
/// server deletes and recreates, and blank fields the server had filled.
void main() {
  group('a client', () {
    final sent = Client.fromApi(
      const ClientApi(
        name: 'Acme',
        contacts: [ContactApi(firstName: 'Ada')],
      ),
    );
    final stored = Client.fromApi(
      const ClientApi(
        id: 'c1',
        name: 'Acme',
        number: '0007',
        contacts: [ContactApi(id: 'ct1', firstName: 'Ada')],
      ),
    );

    test('carries a changed field and keeps the stored contacts, ids and '
        'all', () {
      final carried = carryClientEdit(
        sent,
        sent.copyWith(publicNotes: 'Call first'),
        stored,
      );

      expect(carried.publicNotes, 'Call first');
      expect(carried.id, 'c1');
      expect(carried.number, '0007', reason: 'the server gave it');
      expect(carried.contacts, stored.contacts);
    });

    test('a contact edited meanwhile keeps the stored id', () {
      final edited = sent.copyWith(
        contacts: [sent.contacts.single.copyWith(firstName: 'Adele')],
      );

      final carried = carryClientEdit(sent, edited, stored);

      expect(carried.contacts.single.id, 'ct1');
      expect(carried.contacts.single.firstName, 'Adele');
    });

    test('nothing changed: the stored record itself', () {
      expect(carryClientEdit(sent, sent, stored), same(stored));
    });
  });

  test('an invoice keeps its stored invitation key and the due date the '
      'server filled', () {
    final sent = Invoice.fromApi(
      const InvoiceApi(
        clientId: 'c1',
        invitations: [InvitationApi(clientContactId: 'ct1')],
      ),
    );
    final stored = Invoice.fromApi(
      const InvoiceApi(
        id: 'i1',
        clientId: 'c1',
        number: '0042',
        dueDate: '2026-12-20',
        invitations: [
          InvitationApi(id: 'iv1', key: 'k1', clientContactId: 'ct1'),
        ],
      ),
    );

    final carried = carryInvoiceEdit(
      sent,
      sent.copyWith(publicNotes: 'Thank you'),
      stored,
    );

    expect(carried.publicNotes, 'Thank you');
    expect(carried.id, 'i1');
    expect(carried.number, '0042');
    expect(carried.dueDate, stored.dueDate);
    expect(carried.invitations, stored.invitations);
    expect(carried.invitations.single.key, 'k1');
  });
}
