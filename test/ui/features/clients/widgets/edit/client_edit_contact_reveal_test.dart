import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/models/api/client_api_model.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/contact.dart';
import 'package:admin/data/repositories/client_repository.dart';
import 'package:admin/data/services/clients_api.dart';
import 'package:admin/ui/core/widgets/contact_edit_rows.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';

import '../../../../../_localization_helper.dart';

/// The record screen's "+ Add" opens the edit screen on a new blank contact,
/// scrolled into view. The reveal is a one-shot: still set on the view model,
/// a later remount of the Contacts card (the layout moving it between its
/// one- and two-column trees on a resize) pulled the form back to it.

class _NoopApi implements ClientsApi {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API call: ${invocation.memberName}');
}

void main() {
  late AppDatabase db;
  late ClientRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ClientRepository(db: db, api: _NoopApi());
  });
  tearDown(() async {
    await db.close();
  });

  testWidgets('a remount does not scroll to the added contact again', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = ClientEditViewModel(
      repo: repo,
      companyId: 'co',
      existing: Client.fromApi(
        ClientApi.fromJson({
          'id': 'c1',
          'name': 'Acme',
          'balance': '0',
          'contacts': [
            for (var i = 0; i < 12; i++)
              {
                'id': 'k$i',
                'first_name': 'Person $i',
                'email': 'p$i@example.com',
                'is_primary': i == 0,
              },
          ],
        }),
      ),
    );
    addTearDown(vm.dispose);
    vm.addContact();

    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    // Wired as `ClientEditContactsSection` wires it; [generation] keys the
    // rows, standing in for the layout swapping the card's subtree.
    Future<void> pump(int generation) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: ContactEditRows(
                key: ValueKey(generation),
                reveal: vm.contactToReveal,
                onRevealed: vm.contactRevealed,
                contacts: [
                  for (final c in vm.draft.contacts)
                    ContactRowData(
                      id: c.id,
                      firstName: c.firstName,
                      lastName: c.lastName,
                      email: c.email,
                      phone: c.phone,
                      isPrimary: c.isPrimary,
                      isBlank: c.isBlank,
                    ),
                ],
                fieldsBuilder: (_, _) => const [],
                onMakePrimary: (_) {},
                onDelete: (_) => null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(0);
    expect(scroll.offset, greaterThan(0), reason: 'the new contact is shown');
    expect(vm.contactToReveal, isNull);

    scroll.jumpTo(0);
    await pump(1);
    expect(scroll.offset, 0, reason: 'the user scrolled away; stay there');
  });
}
