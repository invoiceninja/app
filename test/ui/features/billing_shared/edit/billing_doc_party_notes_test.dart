// The client's (a purchase order's vendor's) own notes under the billing-doc
// edit form's party picker — invoiceninja/app#201. Users keep invoicing
// information on the client ("driving distance", "special prices") and need
// it while they bill; v1 showed both notes there, private first.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/vendor_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/ui/features/billing_shared/edit/billing_doc_client_picker.dart';
import 'package:admin/ui/features/billing_shared/edit/billing_doc_party_notes.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/invoices/widgets/edit/invoice_edit_layout.dart';
import 'package:admin/ui/features/purchase_orders/view_models/purchase_order_edit_view_model.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

const _notesKey = ValueKey('billing-party-notes');
const _calloutKey = ValueKey('private-notes-callout');

Future<void> _seedClient(
  Services services, {
  String id = 'c1',
  String privateNotes = '',
  String publicNotes = '',
  int updatedAt = 1710000000,
}) => services.clients.applyUpdateResponse(
  companyId: kHarnessCompanyId,
  serverResponse: ClientApi(
    id: id,
    name: 'Client $id',
    displayName: 'Client $id',
    privateNotes: privateNotes,
    publicNotes: publicNotes,
    updatedAt: updatedAt,
    createdAt: 1700000000,
  ),
);

Future<void> _seedVendor(
  Services services, {
  String privateNotes = '',
  String publicNotes = '',
}) => services.vendors.applyUpdateResponse(
  companyId: kHarnessCompanyId,
  serverResponse: VendorApi.fromJson({
    'id': 'v1',
    'name': 'Northwind Paper Co.',
    'private_notes': privateNotes,
    'public_notes': publicNotes,
    'updated_at': 1710000000,
    'created_at': 1700000000,
  }),
);

Future<ShellFixture> _fixture() async {
  final fixture = await buildFixture(
    closeStreamsSynchronously: true,
    companies: [const FakeCompany(id: kHarnessCompanyId, name: 'Co')],
  );
  addTearDown(fixture.dispose);
  return fixture;
}

/// The widget alone, between two fixed boxes, so its own height (gap
/// included) is the distance between them.
Widget _notes(BillingDocParty party, String partyId, {double gap = 12}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(key: ValueKey('above'), height: 10),
        BillingDocPartyNotes(
          party: party,
          companyId: kHarnessCompanyId,
          partyId: partyId,
          gap: gap,
        ),
        const SizedBox(key: ValueKey('below'), height: 10),
      ],
    );

double _heightBetween(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('below'))).dy -
    tester.getBottomLeft(find.byKey(const ValueKey('above'))).dy;

void main() {
  group('BillingDocPartyNotes', () {
    testWidgets('renders both notes as words, private first, under the gap', (
      tester,
    ) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedClient(
        fixture.services,
        privateNotes: '<p>Driving distance: <b>42 km</b></p>',
        publicNotes: '<p>Thanks for your business</p>',
      );
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);

      expect(find.text('Driving distance: 42 km'), findsOneWidget);
      expect(find.text('Thanks for your business'), findsOneWidget);
      expect(find.textContaining('<'), findsNothing);
      final private = tester.getTopLeft(find.text('Private Notes')).dy;
      final public = tester.getTopLeft(find.text('Public Notes')).dy;
      expect(private, lessThan(public));
      // The gap is the widget's own, drawn with the notes.
      expect(
        tester.getTopLeft(find.byKey(_notesKey)).dy,
        tester.getBottomLeft(find.byKey(const ValueKey('above'))).dy,
      );
      expect(
        tester.getTopLeft(find.byKey(_calloutKey)).dy -
            tester.getTopLeft(find.byKey(_notesKey)).dy,
        12,
      );
      await unmount(tester, fixture);
    });

    testWidgets('the private note is the account alert: the highlighted '
        'callout; the public note stays plain', (tester) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedClient(
        fixture.services,
        privateNotes: '<p>On credit hold</p>',
        publicNotes: 'Thanks for your business',
      );
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);

      final callout = find.byKey(_calloutKey);
      expect(callout, findsOneWidget);
      expect(
        find.descendant(of: callout, matching: find.text('On credit hold')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: callout, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: callout,
          matching: find.text('Thanks for your business'),
        ),
        findsNothing,
      );
      await unmount(tester, fixture);
    });

    testWidgets('public notes alone raise no alert', (tester) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedClient(fixture.services, publicNotes: 'Net 15 for this one');
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);

      expect(find.byKey(_calloutKey), findsNothing);
      await unmount(tester, fixture);
    });

    testWidgets('only the note that holds words is shown', (tester) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedClient(fixture.services, publicNotes: 'Net 15 for this one');
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);

      expect(find.text('Net 15 for this one'), findsOneWidget);
      expect(find.text('Private Notes'), findsNothing);
      expect(find.text('Public Notes'), findsOneWidget);
      await unmount(tester, fixture);
    });

    for (final (name, privateNotes, publicNotes) in [
      ('blank', '', ''),
      ('whitespace', '  \n ', ' '),
      ('markup that renders as nothing', '<p></p>', '<p><br></p>'),
      ('whitespace markup', '<p> </p>', '<p>&nbsp;</p>'),
    ]) {
      testWidgets('$name notes draw nothing, not even the gap', (tester) async {
        setWindow(tester, 800);
        final fixture = await _fixture();
        await _seedClient(
          fixture.services,
          privateNotes: privateNotes,
          publicNotes: publicNotes,
        );
        await tester.pumpWidget(
          wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
        );
        await settle(tester);

        expect(find.byKey(_notesKey), findsNothing);
        expect(_heightBetween(tester), 0);
        await unmount(tester, fixture);
      });
    }

    testWidgets('no party picked draws nothing', (tester) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, '')),
      );
      await settle(tester);

      expect(find.byKey(_notesKey), findsNothing);
      expect(_heightBetween(tester), 0);
      await unmount(tester, fixture);
    });

    testWidgets('follows the client when its notes change in Drift', (
      tester,
    ) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedClient(fixture.services, privateNotes: 'Old rate');
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);
      expect(find.text('Old rate'), findsOneWidget);

      await tester.runAsync(
        () => _seedClient(
          fixture.services,
          privateNotes: 'New rate',
          updatedAt: 1720000000,
        ),
      );
      await settle(tester);

      expect(find.text('Old rate'), findsNothing);
      expect(find.text('New rate'), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('clearing and re-picking an unsynced client shows its notes '
        'again', (tester) async {
      // An inline-created client is `tmp_` until its create syncs, and its
      // watch is single-subscription: a re-pick must not hand the cached
      // stream to a second StreamBuilder ("already been listened to").
      setWindow(tester, 800);
      final fixture = await _fixture();
      final created = (await tester.runAsync(
        () => fixture.services.clients.create(
          companyId: kHarnessCompanyId,
          draft: Client.fromApi(
            const ClientApi(
              id: '',
              name: 'New Co',
              privateNotes: 'Unsynced note',
              updatedAt: 1,
            ),
          ),
        ),
      ))!.entity;
      expect(created.id, startsWith('tmp_'));

      Future<void> pick(String id) async {
        await tester.pumpWidget(
          wrapWithShell(fixture.services, _notes(BillingDocParty.client, id)),
        );
        await settle(tester);
      }

      await pick(created.id);
      expect(find.text('Unsynced note'), findsOneWidget);
      await pick('');
      expect(find.text('Unsynced note'), findsNothing);
      await pick(created.id);
      expect(tester.takeException(), isNull);
      expect(find.text('Unsynced note'), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('picking another client swaps the notes', (tester) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedClient(fixture.services, privateNotes: 'First client note');
      await _seedClient(
        fixture.services,
        id: 'c2',
        privateNotes: 'Second client note',
      );
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);
      expect(find.text('First client note'), findsOneWidget);

      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c2')),
      );
      await settle(tester);

      expect(find.text('First client note'), findsNothing);
      expect(find.text('Second client note'), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('a vendor party reads the vendor\'s notes', (tester) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      await _seedVendor(
        fixture.services,
        privateNotes: 'Ships on Tuesdays',
        publicNotes: '<p>Account 1234</p>',
      );
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.vendor, 'v1')),
      );
      await settle(tester);

      expect(find.text('Ships on Tuesdays'), findsOneWidget);
      expect(find.text('Account 1234'), findsOneWidget);
      await unmount(tester, fixture);
    });

    testWidgets('a long note is clamped to three lines with More', (
      tester,
    ) async {
      setWindow(tester, 800);
      final fixture = await _fixture();
      final long = List.generate(12, (i) => 'Line ${i + 1}').join('\n');
      await _seedClient(fixture.services, privateNotes: long);
      await tester.pumpWidget(
        wrapWithShell(fixture.services, _notes(BillingDocParty.client, 'c1')),
      );
      await settle(tester);

      expect(kBillingDocPartyNoteLines, 3);
      final text = tester.widget<Text>(find.text(long));
      expect(text.maxLines, kBillingDocPartyNoteLines);
      expect(find.text('More'), findsOneWidget);

      await tester.tap(find.text('More'));
      await settle(tester);
      expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
      expect(find.text('Less'), findsOneWidget);
      await unmount(tester, fixture);
    });
  });

  group('in the edit layout', () {
    testWidgets('a new purchase order shows the vendor\'s notes (narrow)', (
      tester,
    ) async {
      setWindow(tester, 390);
      final fixture = await _fixture();
      await _seedVendor(fixture.services, privateNotes: 'Ships on Tuesdays');
      final mounted = buildLayout(
        BillingDoc.purchaseOrder,
        fixture.services,
        showPdfTab: false,
      );
      addTearDown(mounted.vm.dispose);
      (mounted.vm as PurchaseOrderEditViewModel).setVendorId('v1');
      await tester.pumpWidget(wrapWithShell(fixture.services, mounted.layout));
      await settle(tester);

      expect(find.text('Ships on Tuesdays'), findsOneWidget);
      await unmount(tester, fixture);
    });

    for (final (label, width) in [('phone', 390.0), ('desktop', 1440.0)]) {
      testWidgets('a new invoice follows the picked client ($label), and the '
          'picker keeps its place in the tree', (tester) async {
        setWindow(tester, width);
        final fixture = await _fixture();
        await _seedClient(fixture.services, privateNotes: 'On credit hold');
        await _seedClient(fixture.services, id: 'c2');
        await _seedClient(
          fixture.services,
          id: 'c3',
          privateNotes: 'Always add their PO number',
        );
        final mounted = buildLayout(
          BillingDoc.invoice,
          fixture.services,
          showPdfTab: false,
        );
        addTearDown(mounted.vm.dispose);
        await tester.pumpWidget(
          wrapWithShell(fixture.services, mounted.layout),
        );
        await settle(tester);
        expect(find.byKey(_calloutKey), findsNothing);

        final picker = find.byWidgetPredicate(
          (w) => w is BillingDocClientPicker,
        );
        final pickerElement = tester.element(picker);

        (mounted.vm as InvoiceEditViewModel).setClientId('c1');
        await settle(tester);
        expect(find.byKey(_calloutKey), findsOneWidget);
        expect(find.text('On credit hold'), findsOneWidget);
        // Directly under the picker.
        expect(
          tester.getTopLeft(find.byKey(_calloutKey)).dy,
          greaterThan(tester.getTopLeft(picker).dy),
        );

        // A client with no private notes: the alert goes.
        (mounted.vm as InvoiceEditViewModel).setClientId('c2');
        await settle(tester);
        expect(find.byKey(_calloutKey), findsNothing);
        expect(find.text('On credit hold'), findsNothing);

        (mounted.vm as InvoiceEditViewModel).setClientId('c3');
        await settle(tester);
        expect(find.text('Always add their PO number'), findsOneWidget);

        // The alert came and went beside the picker, never around it.
        expect(identical(tester.element(picker), pickerElement), isTrue);
        await unmount(tester, fixture);
      });
    }

    testWidgets('a saved invoice still shows its client\'s notes (wide)', (
      tester,
    ) async {
      setWindow(tester, 1440);
      final fixture = await _fixture();
      await _seedClient(fixture.services, privateNotes: 'Special price: 80/h');
      final vm = InvoiceEditViewModel(
        repo: fixture.services.invoices,
        companyId: kHarnessCompanyId,
        clientRequiredMessage: '',
        crossClientLineItemsMessage: '',
        partialInvalidMessage: '',
        existing: emptyInvoice().copyWith(id: 'i1', clientId: 'c1'),
      );
      addTearDown(vm.dispose);
      expect(vm.isCreate, isFalse);
      await tester.pumpWidget(
        wrapWithShell(
          fixture.services,
          InvoiceEditLayout(vm: vm, showPdfTab: true),
        ),
      );
      await settle(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('billing-details-party')),
          matching: find.text('Special price: 80/h'),
        ),
        findsOneWidget,
      );
      await unmount(tester, fixture);
    });
  });
}
