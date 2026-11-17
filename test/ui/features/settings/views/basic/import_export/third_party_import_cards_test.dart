import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/core/widgets/file_drop_zone.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/basic/import_export_screen.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../../../_localization_helper.dart';

class _FakeAuth implements AuthRepository {
  @override
  final ValueListenable<AuthSession?> session = ValueNotifier<AuthSession?>(
    const AuthSession(
      baseUrl: '',
      isHosted: false,
      accountId: '',
      companies: [],
      currentCompanyId: 'co',
      userId: 'u',
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeServices implements Services {
  @override
  final AuthRepository auth = _FakeAuth();
  @override
  Formatter? formatterIfReady(String companyId) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final level = SettingsLevelController();
    addTearDown(level.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: _FakeServices()),
          ChangeNotifierProvider<SettingsLevelController>.value(value: level),
        ],
        child: MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          home: const ImportExportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inThirdParty(Finder f) => find.descendant(
    of: find
        .ancestor(
          of: find.text('FreshBooks'),
          matching: find.byType(FormSection),
        )
        .first,
    matching: f,
  );

  testWidgets(
    'every importer is a card, and the picked one asks for its files',
    (tester) async {
      await pump(tester);

      for (final name in [
        'FreshBooks',
        'Invoice2go',
        'Invoicely',
        'Wave Accounting',
        'Zoho',
        'Quickbooks',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }

      // FreshBooks (the default) needs a clients and an invoices file.
      expect(inThirdParty(find.text('Clients')), findsOneWidget);
      expect(inThirdParty(find.text('Invoices')), findsOneWidget);

      // QuickBooks takes one backup file instead.
      await tester.tap(find.text('Quickbooks'));
      await tester.pumpAndSettle();
      expect(inThirdParty(find.text('Backup')), findsOneWidget);
      expect(inThirdParty(find.text('Invoices')), findsNothing);
      expect(inThirdParty(find.byType(FileDropZone)), findsOneWidget);
    },
  );
}
