import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/entity_modules.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/api/contact_api_model.dart';
import 'package:admin/data/models/api/vendor_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/vendor.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/core/edit/add_contact_request.dart';
import 'package:admin/ui/features/clients/views/client_edit_screen.dart';
import 'package:admin/ui/features/clients/widgets/detail/client_detail_profile.dart';
import 'package:admin/ui/features/vendors/views/vendor_edit_screen.dart';
import 'package:admin/ui/features/vendors/widgets/detail/vendor_detail_profile.dart';

import '../../../_localization_helper.dart';
import '../../../_support/phone_actions_test_services.dart';

/// The record screen's Contacts card "+ Add": offered only to a user who may
/// edit the record, never on a deleted one, and it opens the party's editor
/// through the route — `extra: AddContactRequest()` — so the request survives
/// the full-screen URL toggle, which re-attaches `extra`.

AuthSession _session({required bool admin}) => AuthSession(
  baseUrl: 'https://example.test',
  isHosted: false,
  accountId: 'acct',
  userId: 'me',
  companies: [
    AuthCompany(
      id: 'co',
      name: 'Co',
      displayName: 'Co',
      permissions: admin ? '' : 'view_client,view_vendor',
      isAdmin: admin,
      isOwner: false,
    ),
  ],
  currentCompanyId: 'co',
);

Client _client({bool deleted = false}) => Client.fromApi(
  ClientApi(
    id: 'c1',
    name: 'Acme',
    userId: 'someone-else',
    isDeleted: deleted,
    contacts: const [ContactApi(id: 'ct1', firstName: 'Ada', isPrimary: true)],
  ),
);

Vendor _vendor({bool deleted = false}) => Vendor.fromApi(
  VendorApi(
    id: 'v1',
    name: 'Supplies',
    userId: 'someone-else',
    isDeleted: deleted,
    contacts: const [VendorContactApi(id: 'vc1', firstName: 'Bo')],
  ),
);

/// [profile] on `/clients/c1`, with the client and vendor edit routes the
/// real module specs build; returns what each edit route was handed.
Future<List<Widget>> _pump(
  WidgetTester tester,
  Widget profile, {
  required bool admin,
}) async {
  final built = <Widget>[];
  EntityModuleSpec spec(String path) =>
      kWiredEntityModules.firstWhere((m) => m.routePath == path);
  final router = GoRouter(
    initialLocation: '/record',
    routes: [
      GoRoute(
        path: '/record',
        builder: (context, state) =>
            Scaffold(body: SingleChildScrollView(child: profile)),
      ),
      for (final path in ['/clients', '/vendors'])
        GoRoute(
          path: '$path/:id/edit',
          builder: (context, state) {
            // The real route's widget, captured rather than mounted: the
            // editor needs the whole app graph.
            built.add(spec(path).editBuilder!(context, state));
            return const Scaffold(body: Text('editor'));
          },
        ),
    ],
  );
  final services = PhoneActionsTestServices(session: _session(admin: admin));
  await tester.pumpWidget(
    Provider<Services>.value(
      value: services,
      child: MaterialApp.router(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return built;
}

void main() {
  group('client', () {
    testWidgets('Add opens the editor on a new contact', (tester) async {
      final built = await _pump(
        tester,
        ClientDetailProfile(client: _client(), company: null),
        admin: true,
      );
      expect(find.text('Add'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsOneWidget);
      final editor = built.last as ClientEditScreen;
      expect(editor.existingId, 'c1');
      expect(editor.addContact, isTrue);
    });

    testWidgets('hidden without edit permission', (tester) async {
      await _pump(
        tester,
        ClientDetailProfile(client: _client(), company: null),
        admin: false,
      );
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Add'), findsNothing);
    });

    testWidgets('hidden on a deleted client', (tester) async {
      await _pump(
        tester,
        ClientDetailProfile(client: _client(deleted: true), company: null),
        admin: true,
      );
      expect(find.text('Add'), findsNothing);
    });
  });

  group('vendor', () {
    testWidgets('Add opens the editor on a new contact', (tester) async {
      final built = await _pump(
        tester,
        VendorDetailProfile(vendor: _vendor(), company: null),
        admin: true,
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      final editor = built.last as VendorEditScreen;
      expect(editor.existingId, 'v1');
      expect(editor.addContact, isTrue);
    });

    testWidgets('hidden without permission and on a deleted vendor', (
      tester,
    ) async {
      await _pump(
        tester,
        VendorDetailProfile(vendor: _vendor(), company: null),
        admin: false,
      );
      expect(find.text('Add'), findsNothing);
      await _pump(
        tester,
        VendorDetailProfile(vendor: _vendor(deleted: true), company: null),
        admin: true,
      );
      expect(find.text('Add'), findsNothing);
    });
  });

  test('a plain edit route carries no request', () {
    expect(AddContactRequest.of(null), isFalse);
    expect(AddContactRequest.of(const AddContactRequest()), isTrue);
    expect(AddContactRequest.of(Object()), isFalse);
  });
}
