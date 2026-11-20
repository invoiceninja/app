import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/contact_api_model.dart';
import 'package:admin/data/models/api/vendor_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/models/domain/vendor.dart';
import 'package:admin/ui/core/edit/entity_edit_screen_scaffold.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';
import 'package:admin/ui/features/clients/views/client_edit_screen.dart';
import 'package:admin/ui/features/invoices/view_models/invoice_edit_view_model.dart';
import 'package:admin/ui/features/invoices/views/invoice_edit_screen.dart';
import 'package:admin/ui/features/vendors/view_models/vendor_edit_view_model.dart';
import 'package:admin/ui/features/vendors/views/vendor_edit_screen.dart';

import '../../shell/_shell_test_helpers.dart';
import '_billing_edit_harness.dart';

/// A stay-in-editor Save reloads the form through `reloadVm`
/// (docs/after-saving.md). An edit route's one-shot extra — the "Add to
/// invoice" draft, the record screen's "+ Add" contact — is applied by
/// `buildVm` once and must not be applied again by the reload: the record
/// just saved already holds it, and re-applying it showed a stale draft (the
/// next Save reverted the user's edits) or added a blank contact per Save.
void main() {
  /// The scaffold a screen builds, to call its builders directly. The record
  /// isn't in the cache, so the mounted screen shows "not found" — only its
  /// builders are used.
  Future<EntityEditScreenScaffold<T, VM>> scaffoldOf<
    T,
    VM extends GenericEditViewModel<T>
  >(WidgetTester tester, ShellFixture fixture, Widget screen) async {
    await tester.pumpWidget(wrapWithShell(fixture.services, screen));
    await settle(tester);
    return tester.widget<EntityEditScreenScaffold<T, VM>>(
      find.byType(EntityEditScreenScaffold<T, VM>),
    );
  }

  Future<ShellFixture> fixture(WidgetTester tester) async {
    setWindow(tester, 1440);
    final f = await buildFixture(
      closeStreamsSynchronously: true,
      companies: const [FakeCompany(id: kHarnessCompanyId, name: 'Co')],
    );
    addTearDown(f.dispose);
    return f;
  }

  BuildContext ctx(WidgetTester tester) =>
      tester.element(find.byType(Overlay).first);

  testWidgets('an invoice reloads without the "Add to invoice" draft', (
    tester,
  ) async {
    final f = await fixture(tester);
    final saved = emptyInvoice().copyWith(id: 'i1', poNumber: 'saved');
    final handoff = saved.copyWith(poNumber: 'handoff');
    final scaffold = await scaffoldOf<Invoice, InvoiceEditViewModel>(
      tester,
      f,
      InvoiceEditScreen(existingId: 'i1', cloneFrom: handoff),
    );

    final first = scaffold.buildVm(ctx(tester), f.services, 'co1', saved);
    addTearDown(first.dispose);
    expect(first.draft.poNumber, 'handoff', reason: 'the handoff opens once');

    final reloaded = scaffold.reloadVm!(ctx(tester), f.services, 'co1', saved);
    addTearDown(reloaded.dispose);
    expect(reloaded.draft.poNumber, 'saved');
    expect(reloaded.isDirty, isFalse);
    await unmount(tester, f);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a client reloads without another blank contact', (tester) async {
    final f = await fixture(tester);
    final saved = Client.fromApi(
      const ClientApi(
        id: 'c1',
        name: 'Acme',
        contacts: [ContactApi(id: 'ct1', firstName: 'Ada')],
      ),
    );
    final scaffold = await scaffoldOf<Client, ClientEditViewModel>(
      tester,
      f,
      const ClientEditScreen(existingId: 'c1', addContact: true),
    );

    final first = scaffold.buildVm(ctx(tester), f.services, 'co1', saved);
    addTearDown(first.dispose);
    expect(first.draft.contacts, hasLength(2), reason: '"+ Add" adds one');

    final reloaded = scaffold.reloadVm!(ctx(tester), f.services, 'co1', saved);
    addTearDown(reloaded.dispose);
    expect(reloaded.draft.contacts, hasLength(1));
    await unmount(tester, f);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a vendor reloads without another blank contact', (tester) async {
    final f = await fixture(tester);
    final saved = Vendor.fromApi(
      const VendorApi(
        id: 'v1',
        name: 'Supplies',
        contacts: [VendorContactApi(id: 'vc1', firstName: 'Bo')],
      ),
    );
    final scaffold = await scaffoldOf<Vendor, VendorEditViewModel>(
      tester,
      f,
      const VendorEditScreen(existingId: 'v1', addContact: true),
    );

    final first = scaffold.buildVm(ctx(tester), f.services, 'co1', saved);
    addTearDown(first.dispose);
    expect(first.draft.contacts, hasLength(2));

    final reloaded = scaffold.reloadVm!(ctx(tester), f.services, 'co1', saved);
    addTearDown(reloaded.dispose);
    expect(reloaded.draft.contacts, hasLength(1));
    await unmount(tester, f);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
