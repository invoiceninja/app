import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/welcome_controller.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/services/upload_source.dart';
import 'package:admin/domain/setup_checklist.dart';
import 'package:admin/ui/features/dashboard/view_models/setup_checklist_view_model.dart';
import 'package:admin/ui/features/dashboard/widgets/setup_checklist_card.dart';

import '../../shell/_shell_test_helpers.dart';

/// The dashboard's "Start getting paid" checklist (docs/first-run-welcome.md).
void main() {
  late WelcomeController welcome;

  setUp(() {
    welcome = WelcomeController(
      prefs: DevicePrefsStore(null),
      currentUserKey: () => null,
      isDemoBuild: false,
      demoMode: false,
    );
  });
  tearDown(() => welcome.dispose());

  Future<ShellFixture> fixture() async {
    final f = await buildFixture(
      companies: const [FakeCompany(id: 'c1', name: 'Acme Studio')],
      currentCompanyId: 'c1',
      closeStreamsSynchronously: true,
    );
    f.services.refreshScheduler.stop();
    return f;
  }

  Future<List<String>> pumpSlot(WidgetTester tester, ShellFixture f) async {
    final opened = <String>[];
    await tester.pumpWidget(
      wrapWithShell(
        f.services,
        ChangeNotifierProvider<WelcomeController?>.value(
          value: welcome,
          child: ListView(
            children: [
              DashboardSetupChecklistSlot(
                companyId: 'c1',
                onNavigate: opened.add,
              ),
              const Text('below'),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return opened;
  }

  testWidgets('a company whose setup never ran shows nothing', (tester) async {
    final f = await fixture();
    addTearDown(f.dispose);
    await pumpSlot(tester, f);
    expect(find.byKey(const ValueKey('setup_checklist')), findsNothing);
    expect(find.text('below'), findsOneWidget);
  });

  testWidgets('starts one in, with the logo next', (tester) async {
    final f = await fixture();
    addTearDown(f.dispose);
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    final opened = await pumpSlot(tester, f);
    expect(find.text('Start getting paid'), findsOneWidget);
    expect(find.text('1 of 5 complete'), findsOneWidget);
    // Only the next row carries a button.
    expect(find.byKey(const ValueKey('setup_checklist_logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup_checklist_invoice')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('setup_checklist_logo')));
    expect(opened, [kChecklistLogoRoute]);
    // A quiet row is one tap target that leads to its screen.
    await tester.tap(find.byKey(const ValueKey('setup_checklist_row_invoice')));
    expect(opened.last, kChecklistInvoiceRoute);
  });

  testWidgets('a logo still uploading counts as done', (tester) async {
    final f = await fixture();
    addTearDown(f.dispose);
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    await f.services.company.uploadLogo(
      companyId: 'c1',
      source: BytesUploadSource(Uint8List.fromList([1]), 'logo.png'),
    );
    await pumpSlot(tester, f);
    expect(find.text('Uploading…'), findsOneWidget);
    expect(find.text('2 of 5 complete'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('setup_checklist_invoice')),
      findsOneWidget,
    );
  });

  testWidgets('Hide puts it away, and Undo brings it back', (tester) async {
    final f = await fixture();
    addTearDown(f.dispose);
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    await pumpSlot(tester, f);
    await tester.tap(find.byKey(const ValueKey('setup_checklist_hide')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(welcome.showsChecklist('c1'), isFalse);
    expect(find.text('Checklist hidden'), findsOneWidget);
    await tester.tap(find.text('UNDO'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(welcome.showsChecklist('c1'), isTrue);
    expect(find.text('Start getting paid'), findsOneWidget);
  });

  testWidgets('a narrow phone at 2x text puts the buttons under the text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fixture();
    addTearDown(f.dispose);
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 1400),
          textScaler: TextScaler.linear(2),
        ),
        child: wrapWithShell(
          f.services,
          ChangeNotifierProvider<WelcomeController?>.value(
            value: welcome,
            child: ListView(
              children: [
                DashboardSetupChecklistSlot(
                  companyId: 'c1',
                  onNavigate: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('Add your logo').first);
    final button = tester.getRect(
      find.byKey(const ValueKey('setup_checklist_logo')),
    );
    expect(button.top, greaterThan(title.bottom));
  });

  testWidgets('a phone folds finished steps away and shows titles only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await fixture();
    addTearDown(f.dispose);
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    final opened = await pumpSlot(tester, f);
    expect(find.text('1 of 5 complete'), findsOneWidget);
    // "Set up your business" is done: folded into the progress line.
    expect(find.text('Set up your business'), findsNothing);
    // The next step keeps its line; the ones after it show a title alone.
    expect(find.text('It appears on every invoice and quote.'), findsOneWidget);
    expect(find.text('Send your first invoice'), findsOneWidget);
    expect(
      find.text('Your client gets a link to view and pay it.'),
      findsNothing,
    );
    // The next step's words lead where its button does.
    await tester.tap(find.byKey(const ValueKey('setup_checklist_text_logo')));
    expect(opened, [kChecklistLogoRoute]);
  });

  testWidgets('only a fresh company lets the zero figures step back', (
    tester,
  ) async {
    final f = await fixture();
    addTearDown(f.dispose);
    // Armed, not fresh: an old company named in /setup.
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    final reported = <bool>[];
    await tester.pumpWidget(
      wrapWithShell(
        f.services,
        ChangeNotifierProvider<WelcomeController?>.value(
          value: welcome,
          child: ListView(
            children: [
              DashboardSetupChecklistSlot(
                companyId: 'c1',
                onNavigate: (_) {},
                onEmptyChanged: reported.add,
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(reported.where((e) => e), isEmpty);
  });

  testWidgets('a non-admin never sees it', (tester) async {
    final f = await buildFixture(
      companies: const [
        FakeCompany(
          id: 'c1',
          name: 'Acme Studio',
          isAdmin: false,
          isOwner: false,
          permissions: 'view_client',
        ),
      ],
      currentCompanyId: 'c1',
      closeStreamsSynchronously: true,
    );
    f.services.refreshScheduler.stop();
    addTearDown(f.dispose);
    await welcome.noteSetupCompleted(userKey: null, companyId: 'c1');
    await pumpSlot(tester, f);
    expect(find.byKey(const ValueKey('setup_checklist')), findsNothing);
  });

  testWidgets('the optional Tap to Pay on iPhone row: only where it is '
      'offered, last, and never counted', (tester) async {
    final f = await fixture();
    addTearDown(f.dispose);
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    bool? offered;
    final vm = SetupChecklistViewModel(
      db: f.services.db,
      companyId: 'c1',
      session: f.services.auth.session,
      welcome: welcome,
      tapToPay: () => offered,
      tapToPayChanges: changes,
    );
    addTearDown(vm.dispose);
    var told = 0;
    vm.addListener(() => told++);
    expect(
      vm.rows.map((r) => r.item),
      isNot(contains(SetupChecklistItem.tapToPay)),
      reason: 'not offered: someone who cannot finish it never sees it',
    );
    offered = false;
    changes.notifyListeners();
    expect(told, greaterThan(0));
    expect(vm.rows.last.item, SetupChecklistItem.tapToPay);
    expect(countedTotal(vm.rows), 5);
    expect(nextChecklistItem(vm.rows), isNot(SetupChecklistItem.tapToPay));
    offered = true;
    expect(vm.rows.last.isComplete, isTrue);
    expect(completedCount(vm.rows), lessThan(5));
  });
}
