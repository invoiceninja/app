import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/contact_api_model.dart';
import 'package:admin/data/models/api/credit_api_model.dart';
import 'package:admin/data/models/api/invitation_api_model.dart';
import 'package:admin/data/models/api/invoice_api_model.dart';
import 'package:admin/data/models/api/line_item_api_model.dart';
import 'package:admin/data/models/api/quote_api_model.dart';
import 'package:admin/data/models/api/task_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/credit.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/quote.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/ui/core/edit/carry_edit_entities.dart';

/// An edit typed while a new record's create was out rides to the record's
/// editor (docs/after-saving.md) — but only what that edit changed. The rest
/// is the server's copy: laid over it wholesale, the create form's draft
/// would send contacts without ids and invitations without keys, which the
/// server deletes and recreates, and blank fields the server had filled. And
/// each list keeps the server's identity the way the server matches it —
/// never by place where an item may have been added or removed.
void main() {
  group('a client', () {
    final sent = Client.fromApi(
      const ClientApi(
        name: 'Acme',
        contacts: [
          ContactApi(firstName: 'Ada'),
          ContactApi(firstName: 'Bo'),
        ],
      ),
    );
    final stored = Client.fromApi(
      const ClientApi(
        id: 'c1',
        name: 'Acme',
        number: '0007',
        contacts: [
          ContactApi(id: 'ct1', firstName: 'Ada'),
          ContactApi(id: 'ct2', firstName: 'Bo'),
        ],
      ),
    );

    test('carries a changed field and keeps the stored contacts, ids and '
        'all', () {
      final carried = carryClientEdit(
        sent,
        sent.copyWith(publicNotes: 'Call first'),
        stored,
      );

      expect(carried.record.publicNotes, 'Call first');
      expect(carried.record.id, 'c1');
      expect(carried.record.number, '0007', reason: 'the server gave it');
      expect(carried.record.contacts, stored.contacts);
      expect(carried.dropped, isEmpty);
    });

    test('a contact edited in place keeps the stored id at its place', () {
      final edited = sent.copyWith(
        contacts: [
          sent.contacts.first,
          sent.contacts.last.copyWith(firstName: 'Bob'),
        ],
      );

      final carried = carryClientEdit(sent, edited, stored).record;

      expect(carried.contacts.map((c) => (c.id, c.firstName)), [
        ('ct1', 'Ada'),
        ('ct2', 'Bob'),
      ]);
    });

    test('a contact added meanwhile is not carried: the stored contacts '
        'stay, and the list is reported dropped', () {
      final edited = sent.copyWith(
        publicNotes: 'Call first',
        contacts: [
          sent.contacts.first.copyWith(firstName: 'Cy'),
          ...sent.contacts,
        ],
      );

      final carried = carryClientEdit(sent, edited, stored);

      expect(carried.record.contacts, stored.contacts);
      expect(carried.record.publicNotes, 'Call first');
      expect(carried.dropped, {'contacts'});
    });

    test('a contact removed meanwhile is not carried either', () {
      final edited = sent.copyWith(contacts: [sent.contacts.last]);

      final carried = carryClientEdit(sent, edited, stored);

      expect(carried.record, same(stored));
      expect(carried.dropped, {'contacts'});
    });

    test('nothing changed: the stored record itself', () {
      expect(carryClientEdit(sent, sent, stored).record, same(stored));
    });
  });

  group('an invoice', () {
    final sent = Invoice.fromApi(
      const InvoiceApi(
        clientId: 'c1',
        invitations: [
          InvitationApi(clientContactId: 'ct1'),
          InvitationApi(clientContactId: 'ct2'),
        ],
        lineItems: [
          LineItemApi(productKey: 'Widget'),
          LineItemApi(productKey: 'Gadget'),
        ],
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
          InvitationApi(id: 'iv2', key: 'k2', clientContactId: 'ct2'),
        ],
        lineItems: [
          LineItemApi(productKey: 'Widget'),
          LineItemApi(productKey: 'Gadget'),
        ],
      ),
    );

    test('keeps its stored invitation keys and the due date the server '
        'filled', () {
      final carried = carryInvoiceEdit(
        sent,
        sent.copyWith(publicNotes: 'Thank you'),
        stored,
      ).record;

      expect(carried.publicNotes, 'Thank you');
      expect(carried.id, 'i1');
      expect(carried.number, '0042');
      expect(carried.dueDate, stored.dueDate);
      expect(carried.invitations, stored.invitations);
    });

    test('an untick keeps the remaining contact its own key', () {
      final edited = sent.copyWith(invitations: [sent.invitations.last]);

      final carried = carryInvoiceEdit(sent, edited, stored).record;

      expect(carried.invitations.map((i) => (i.clientContactId, i.key)), [
        ('ct2', 'k2'),
      ]);
    });

    test('a contact ticked meanwhile is invited without a key; the others '
        'keep theirs', () {
      final edited = sent.copyWith(
        invitations: [
          sent.invitations.first.copyWith(clientContactId: 'ct3'),
          ...sent.invitations,
        ],
      );

      final carried = carryInvoiceEdit(sent, edited, stored).record;

      expect(carried.invitations.map((i) => (i.clientContactId, i.key)), [
        ('ct3', ''),
        ('ct1', 'k1'),
        ('ct2', 'k2'),
      ]);
    });

    test('a line inserted meanwhile is carried, as are the others', () {
      final edited = sent.copyWith(
        lineItems: [
          sent.lineItems.first.copyWith(productKey: 'Gizmo'),
          ...sent.lineItems,
        ],
      );

      final carried = carryInvoiceEdit(sent, edited, stored).record;

      expect(carried.lineItems.map((l) => l.productKey), [
        'Gizmo',
        'Widget',
        'Gadget',
      ]);
      expect(carried.invitations, stored.invitations);
    });

    test('a line removed meanwhile is gone', () {
      final edited = sent.copyWith(lineItems: [sent.lineItems.last]);

      final carried = carryInvoiceEdit(sent, edited, stored).record;

      expect(carried.lineItems.map((l) => l.productKey), ['Gadget']);
    });
  });

  test('a quote carries a changed field and keeps its number', () {
    final sent = Quote.fromApi(const QuoteApi(clientId: 'c1'));
    final stored = Quote.fromApi(
      const QuoteApi(id: 'q1', clientId: 'c1', number: 'Q-1'),
    );

    final carried = carryQuoteEdit(
      sent,
      sent.copyWith(publicNotes: 'Valid 30 days'),
      stored,
    ).record;

    expect(carried.id, 'q1');
    expect(carried.number, 'Q-1');
    expect(carried.publicNotes, 'Valid 30 days');
  });

  test('a credit carries a changed field and keeps its number', () {
    final sent = Credit.fromApi(const CreditApi(clientId: 'c1'));
    final stored = Credit.fromApi(
      const CreditApi(id: 'cr1', clientId: 'c1', number: 'CR-1'),
    );

    final carried = carryCreditEdit(
      sent,
      sent.copyWith(publicNotes: 'Refund'),
      stored,
    ).record;

    expect(carried.id, 'cr1');
    expect(carried.number, 'CR-1');
    expect(carried.publicNotes, 'Refund');
  });

  test('a task carries a changed description and keeps its number', () {
    final sent = Task.fromApi(const TaskApi(description: 'Design'));
    final stored = Task.fromApi(
      const TaskApi(id: 't1', number: '0003', description: 'Design'),
    );

    final carried = carryTaskEdit(
      sent,
      sent.copyWith(description: 'Design review'),
      stored,
    ).record;

    expect(carried.id, 't1');
    expect(carried.number, '0003');
    expect(carried.description, 'Design review');
  });
}
