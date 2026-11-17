import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/basic/backup_restore/backup_restore_shell.dart';

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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<void> pump(WidgetTester tester, {String? initialTab}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
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
          home: BackupRestoreShell(initialTab: initialTab),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('backup and restore are one page, with no tabs', (tester) async {
    await pump(tester);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Import Settings'), findsOneWidget);
    expect(find.text('Import Data'), findsOneWidget);
  });

  testWidgets('Import data says it replaces, never merges', (tester) async {
    await pump(tester);
    expect(
      find.textContaining('first, then loads the backup', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing is merged'), findsOneWidget);
  });

  testWidgets('the old Restore tab URL scrolls to the Restore card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 300));
    await pump(tester, initialTab: 'restore');
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });
}
