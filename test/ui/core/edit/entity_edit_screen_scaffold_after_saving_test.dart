import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/after_saving_controller.dart';
import 'package:admin/app/print_after_saving_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/sync_repository.dart';
import 'package:admin/data/services/connectivity_watcher.dart';
import 'package:admin/ui/core/edit/carry_edit.dart';
import 'package:admin/ui/core/edit/entity_edit_screen_scaffold.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/core/list/master_detail_layout.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';

import '../../../_localization_helper.dart';
import '../../../_support/device_prefs_test_support.dart';

/// What Save does next on an entity editor (docs/after-saving.md,
/// invoiceninja/app#202): with "After Saving" = Edit Record a plain Save
/// keeps the editor open — reloading an existing record from the stored copy,
/// moving a new one to its own edit route — and with View Record, or for a
/// save an action made, it goes to the record as it always did.
///
/// Mounted in the production route shape: `/clients/new` a sibling of the
/// list inside the entity shell, `/clients/:id/edit` under the record.
class _FakeAuth implements AuthRepository {
  @override
  final ValueListenable<AuthSession?> session = ValueNotifier<AuthSession?>(
    const AuthSession(
      baseUrl: 'https://example.test',
      isHosted: false,
      accountId: 'acct',
      companies: [],
      currentCompanyId: 'co',
    ),
  );

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeSync implements SyncRepository {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeServices implements Services {
  _FakeServices(this.db);

  @override
  final AppDatabase db;
  @override
  final SyncRepository sync = _FakeSync();
  @override
  final AuthRepository auth = _FakeAuth();
  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// A record: its id and one editable field.
@immutable
class _Rec {
  const _Rec(this.id, this.name);
  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is _Rec && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

const _tmpId = 'tmp_00000000-0000-4000-8000-0000000000cc';

/// The server's answer to a save, given at once — after [whileWaiting],
/// which stands in for what the user does while it is out.
class _AwaitSync implements SyncRepository {
  void Function()? whileWaiting;

  @override
  Future<SyncRowResult> awaitRow({
    required int rowId,
    required String companyId,
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 200),
    bool callerWillDisplayFailure = true,
  }) async {
    whileWaiting?.call();
    return const SyncRowResult(outcome: SyncRowOutcome.success);
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Saves the way a repository does: a create comes back under its `tmp_`
/// id, and the save waits on [_AwaitSync].
class _Vm extends GenericEditViewModel<_Rec> {
  _Vm(_Rec? existing, this.wait)
    : super(
        initialDraft: existing ?? const _Rec('', ''),
        original: existing,
        sync: wait,
        connectivity: ConnectivityWatcher.fixed(online: true),
        companyId: 'co',
      );

  final _AwaitSync wait;

  int saves = 0;

  /// Stands in for an edit that the save saw made while it was out.
  bool editedWhileSaving = false;

  /// What the user types while the save is out.
  set whileSaving(void Function() edit) => wait.whileWaiting = edit;

  @override
  bool get editedDuringSave => editedWhileSaving || super.editedDuringSave;

  void setName(String v) => updateDraft(_Rec(draft.id, v));

  @override
  Future<SaveResult<_Rec>> performSave() async {
    saves++;
    return SaveResult(
      entity: isCreate ? _Rec(_tmpId, draft.name) : draft,
      outboxRowId: 0,
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// The view models the scaffold built, in order — the first is the one the
  /// form opened with, a second one is the reload after a Save.
  late List<_Vm> built;
  late int fetches;
  late AfterSavingController afterSaving;

  /// What "Print After Saving" printed: `<id>:<name>` per print, recorded
  /// only when the editor was still mounted once the (fake) PDF download
  /// came back — the check the real dispatch makes before it prints.
  late List<String> printed;

  Future<GoRouter> pump(
    WidgetTester tester, {
    required bool stay,
    String initial = '/clients/c1/edit',
    _Rec stored = const _Rec('c1', 'Acme'),
    _Rec? Function()? storedNow,
    void Function(int fetch)? onFetch,
    Future<bool> Function(_Rec saved)? canKeepEditing,
    Widget Function(_Vm vm)? body,
    void Function(_Vm vm)? onBuilt,
    bool printAfterSaving = false,
  }) async {
    built = [];
    fetches = 0;
    printed = [];
    Future<void> fakePrint(BuildContext ctx, _Rec saved) async {
      // The download the real dispatch awaits before `context.mounted` —
      // longer than a route transition, which keeps a leaving page mounted.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (ctx.mounted) printed.add('${saved.id}:${saved.name}');
    }

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget scaffold(String? id) =>
        EntityEditScreenScaffold<_Rec, GenericEditViewModel<_Rec>>(
          existingId: id,
          entityTypeName: 'client',
          basePath: '/clients',
          fetchExisting: (_, _, _, _) async {
            fetches++;
            onFetch?.call(fetches);
            return storedNow == null ? stored : storedNow();
          },
          buildVm: (_, _, _, existing) {
            final vm = _Vm(existing, _AwaitSync());
            built.add(vm);
            onBuilt?.call(vm);
            return vm;
          },
          canKeepEditing: canKeepEditing == null
              ? null
              : (_, _, _, saved) => canKeepEditing(saved),
          titleBuilder: (_, _) => 'Client',
          titleWhileLoading: (_) => 'Client',
          bodyBuilder: (_, vm) =>
              body?.call(vm as _Vm) ??
              Text('name ${vm.draft.name}', key: const ValueKey('body')),
          resetToEmpty: (_) {},
          entityIdOf: (draft) => draft.id,
          carryEdit: (sent, edited, stored) => CarriedEdit(
            edited.name == sent.name ? stored : _Rec(stored.id, edited.name),
          ),
          saveParamFor: (action) =>
              action == 'print' ? null : {'mark_sent': 'true'},
          printAction: 'print',
          onAfterSaveAction: (ctx, saved, _) => fakePrint(ctx, saved),
          onAfterSaveActionOnCreate: (ctx, saved, _) async {
            await fakePrint(ctx, saved);
            return false;
          },
          actionsBuilder: (_, _, onTap, saveButton) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              saveButton,
              TextButton(
                onPressed: () => onTap('mark_sent'),
                child: const Text('Mark Sent'),
              ),
            ],
          ),
        );
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage<void>(
            key: const ValueKey('master_detail:/clients'),
            child: MasterDetailLayout(
              basePath: '/clients',
              list: const Scaffold(body: Center(child: Text('clients list'))),
              rightPane: child,
              hasPane: state.matchedLocation != '/clients',
              viewMode: state.uri.queryParameters['view'],
            ),
          ),
          routes: [
            GoRoute(
              path: '/clients',
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(path: '/clients/new', builder: (_, _) => scaffold(null)),
            GoRoute(
              path: '/clients/:id',
              builder: (_, _) => const Text('client detail'),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (_, state) => KeyedSubtree(
                    key: ValueKey('edit:${state.pathParameters['id']}'),
                    child: scaffold(state.pathParameters['id']),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    afterSaving = AfterSavingController(
      prefs: prefsWith({DevicePrefKeys.afterSaving: stay}),
    );
    addTearDown(afterSaving.dispose);
    final printAfter = PrintAfterSavingController(
      prefs: prefsWith({DevicePrefKeys.printAfterSaving: printAfterSaving}),
    );
    addTearDown(printAfter.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: _FakeServices(db)),
          ChangeNotifierProvider<AfterSavingController>.value(
            value: afterSaving,
          ),
          ChangeNotifierProvider<PrintAfterSavingController>.value(
            value: printAfter,
          ),
        ],
        child: MaterialApp.router(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  String uriOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  // A wide window promotes a full-width editor to `?view=full` on its own;
  // where the user lands is the path.
  String pathOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  final saveButton = find.byKey(const ValueKey('entity_edit_save'));

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  group('Edit Record', () {
    testWidgets('an existing record stays open, reloaded from the stored '
        'copy', (tester) async {
      final router = await pump(tester, stay: true);
      expect(saveEnabled(tester), isTrue, reason: 'Save is never disabled');

      built.single
        ..formUiState['tab'] = 2
        ..setName('Acme Inc');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);

      expect(pathOf(router), '/clients/c1/edit');
      expect(built.first.saves, 1);
      expect(fetches, 2, reason: 'the form reloads from the stored record');
      expect(built, hasLength(2));
      expect(built.last.isCreate, isFalse);
      expect(built.last.isDirty, isFalse);
      expect(
        built.last.formUiState['tab'],
        2,
        reason: 'the selected tab rides across the reload',
      );
      expect(find.text('name Acme'), findsOneWidget, reason: 'stored copy');
      expect(saveEnabled(tester), isTrue);

      // Leaving now needs no Discard prompt.
      router.go('/clients');
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(pathOf(router), '/clients');
    });

    testWidgets('a new record moves to its own edit route, under its tmp_ id '
        'while its create has not landed', (tester) async {
      final router = await pump(
        tester,
        stay: true,
        initial: '/clients/new?view=full',
      );
      built.single.setName('Globex');
      await tester.pump();
      await tapSave(tester);

      expect(uriOf(router), '/clients/$_tmpId/edit?view=full');
      expect(built.last.isCreate, isFalse, reason: 'no second create');
    });

    testWidgets('a new record whose create landed opens under the real id', (
      tester,
    ) async {
      await db.idRemapDao.remember(
        entityType: 'client',
        tempId: _tmpId,
        realId: 'c9',
        now: 0,
      );
      final router = await pump(tester, stay: true, initial: '/clients/new');
      built.single.setName('Globex');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/c9/edit');
    });

    testWidgets('a record that may no longer be edited goes to the record', (
      tester,
    ) async {
      final router = await pump(
        tester,
        stay: true,
        initial: '/clients/c1',
        canKeepEditing: (_) async => false,
      );
      router.push('/clients/c1/edit').ignore();
      await tester.pumpAndSettle();
      built.single.setName('Locked');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/c1');
      expect(find.text('client detail'), findsOneWidget);
      expect(fetches, 1, reason: 'no reload');
    });

    testWidgets('a save an action made goes to the record', (tester) async {
      final router = await pump(tester, stay: true);
      await tester.tap(find.text('Mark Sent'));
      await tester.pumpAndSettle();

      expect(
        built.first.saves,
        1,
        reason: 'a SAVE-PARAM action needs no change',
      );
      expect(pathOf(router), '/clients/c1');
    });

    testWidgets('Save on an unchanged record saves — a re-save can make the '
        'server recalculate', (tester) async {
      await pump(tester, stay: true);
      final form = tester.element(find.byKey(const ValueKey('body')));
      // What Enter in a field (and the banner's Retry) reaches; ⌘S runs the
      // same handler.
      FormSaveScope.maybeOf(form)!.trySubmit();
      await tester.pumpAndSettle();
      expect(built.first.saves, 1);
      expect(built, hasLength(2), reason: 'reloaded');
    });
  });

  group('Edit Record, the reload', () {
    testWidgets('an edit made while the save was out is kept: no reload, the '
        'form stays dirty', (tester) async {
      final router = await pump(
        tester,
        stay: true,
        onBuilt: (vm) => vm.editedWhileSaving = true,
      );
      built.single.setName('Acme Inc');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/c1/edit');
      expect(fetches, 1, reason: 'a reload would throw the edit away');
      expect(built, hasLength(1));
    });

    testWidgets('a new record carries an edit typed while its create was out '
        'into its editor, dirty', (tester) async {
      final router = await pump(
        tester,
        stay: true,
        initial: '/clients/new',
        onBuilt: (vm) {
          if (vm.isCreate) vm.whileSaving = () => vm.setName('Globex Ltd');
        },
      );
      built.single.setName('Globex');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/$_tmpId/edit');
      expect(built, hasLength(2));
      expect(built.last.draft, const _Rec('c1', 'Globex Ltd'));
      expect(built.last.isDirty, isTrue);
    });

    testWidgets('keeps the scroll position when another scroll view comes '
        'late, as a PDF pane does after its spinner', (tester) async {
      await pump(
        tester,
        stay: true,
        body: (vm) => Row(
          key: const ValueKey('body'),
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('primary'),
                children: [
                  for (var i = 0; i < 100; i++)
                    SizedBox(height: 50, child: Text('row $i')),
                ],
              ),
            ),
            const Expanded(child: _LateScrollView()),
          ],
        ),
      );
      ScrollPosition primary() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('primary')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      primary().jumpTo(1200);
      await tester.pump();
      built.single.setName('Acme Inc');
      await tester.pump();
      await tapSave(tester);

      expect(built, hasLength(2), reason: 'reloaded');
      expect(primary().pixels, 1200);
    });

    testWidgets('a carried edit for a record that is not there is dropped, '
        'not adopted by a later visit', (tester) async {
      _Rec? record;
      final router = await pump(
        tester,
        stay: true,
        initial: '/clients/new',
        onBuilt: (vm) {
          if (vm.isCreate) vm.whileSaving = () => vm.setName('Globex Ltd');
        },
        storedNow: () => record,
      );
      built.single.setName('Globex');
      await tester.pump();
      await tapSave(tester);
      expect(pathOf(router), '/clients/$_tmpId/edit');
      expect(built, hasLength(1), reason: 'not found: no view model');

      record = const _Rec('c1', 'Acme');
      router.go('/clients');
      await tester.pumpAndSettle();
      router.go('/clients/$_tmpId/edit');
      await tester.pumpAndSettle();

      expect(built.last.draft, const _Rec('c1', 'Acme'));
      expect(built.last.isDirty, isFalse);
    });

    testWidgets("a text field's own scroll is not carried", (tester) async {
      final controller = TextEditingController(
        text: [for (var i = 0; i < 30; i++) 'line $i'].join('\n'),
      );
      addTearDown(controller.dispose);
      await pump(
        tester,
        stay: true,
        body: (vm) => Material(
          key: const ValueKey('body'),
          child: TextField(controller: controller, maxLines: 3),
        ),
      );
      ScrollPosition field() => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(TextField),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      field().jumpTo(40);
      await tester.pump();
      built.single.setName('Acme Inc');
      await tester.pump();
      await tapSave(tester);

      expect(built, hasLength(2), reason: 'reloaded');
      expect(field().pixels, 0);
    });

    testWidgets('keeps the scroll position', (tester) async {
      await pump(
        tester,
        stay: true,
        body: (vm) => ListView(
          key: const ValueKey('body'),
          children: [
            for (var i = 0; i < 100; i++)
              SizedBox(height: 50, child: Text('row $i')),
          ],
        ),
      );
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(1200);
      await tester.pump();
      built.single.setName('Acme Inc');
      await tester.pump();
      await tapSave(tester);

      expect(built, hasLength(2), reason: 'reloaded');
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        1200,
      );
    });

    testWidgets('Enter in a field, a Save that stays: the focus is back in '
        'that field', (tester) async {
      await pump(
        tester,
        stay: true,
        body: (vm) => Material(
          key: const ValueKey('body'),
          child: Column(
            children: [
              const TextField(key: ValueKey('first')),
              TextField(key: const ValueKey('name'), onChanged: vm.setName),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('name')));
      await tester.enterText(find.byKey(const ValueKey('name')), 'Acme Inc');
      await tester.pump();
      final form = tester.element(find.byKey(const ValueKey('body')));
      FormSaveScope.maybeOf(form)!.trySubmit();
      await tester.pumpAndSettle();

      expect(built, hasLength(2), reason: 'reloaded');
      final name = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('name')),
          matching: find.byType(EditableText),
        ),
      );
      expect(name.widget.focusNode.hasFocus, isTrue);
    });

    testWidgets('an edit typed while the record was read back keeps the form: '
        'no reload over it', (tester) async {
      final router = await pump(
        tester,
        stay: true,
        onFetch: (n) {
          if (n == 2) built.first.setName('typed while reading');
        },
      );
      built.single.setName('Acme Inc');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/c1/edit');
      expect(fetches, 2);
      expect(built, hasLength(1), reason: 'not swapped');
      expect(built.single.draft.name, 'typed while reading');
      expect(built.single.isDirty, isTrue);
    });
  });

  group('View Record', () {
    testWidgets('an existing record goes to the record', (tester) async {
      final router = await pump(tester, stay: false);
      built.single.setName('Acme Inc');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/c1');
      expect(fetches, 1);
    });

    testWidgets('a new record goes to the record', (tester) async {
      final router = await pump(tester, stay: false, initial: '/clients/new');
      built.single.setName('Globex');
      await tester.pump();
      await tapSave(tester);

      expect(pathOf(router), '/clients/$_tmpId');
    });
  });

  // Print After Saving adds a print to a plain Save and takes nothing away:
  // the toast, After Saving and the reload all still happen
  // (docs/after-saving.md § Print After Saving adds a print to a plain Save).
  /// Save, then let the fake PDF download (2 s) come back — `pumpAndSettle`
  /// alone stops once no frame is pending and never reaches that timer.
  Future<void> saveAndWaitForPrint(WidgetTester tester) async {
    await tapSave(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  group('Print After Saving', () {
    testWidgets('Edit Record: an existing record prints, then stays open, '
        'reloaded', (tester) async {
      final router = await pump(tester, stay: true, printAfterSaving: true);
      built.single.setName('Acme Inc');
      await tester.pump();
      await saveAndWaitForPrint(tester);

      expect(printed, ['c1:Acme Inc']);
      expect(pathOf(router), '/clients/c1/edit');
      expect(fetches, 2, reason: 'the form reloads from the stored record');
      expect(built, hasLength(2));
      expect(built.last.isDirty, isFalse);
    });

    testWidgets('View Record: an existing record prints before the editor '
        'leaves for the record', (tester) async {
      final router = await pump(tester, stay: false, printAfterSaving: true);
      built.single.setName('Acme Inc');
      await tester.pump();
      await saveAndWaitForPrint(tester);

      expect(printed, ['c1:Acme Inc']);
      expect(pathOf(router), '/clients/c1');
    });

    testWidgets('Edit Record: a new record prints, then moves to its own '
        'edit route', (tester) async {
      final router = await pump(
        tester,
        stay: true,
        initial: '/clients/new',
        printAfterSaving: true,
      );
      built.single.setName('Globex');
      await tester.pump();
      await saveAndWaitForPrint(tester);

      expect(printed, ['$_tmpId:Globex']);
      expect(pathOf(router), '/clients/$_tmpId/edit');
    });

    testWidgets('View Record: a new record prints, then goes to the record', (
      tester,
    ) async {
      final router = await pump(
        tester,
        stay: false,
        initial: '/clients/new',
        printAfterSaving: true,
      );
      built.single.setName('Globex');
      await tester.pump();
      await saveAndWaitForPrint(tester);

      expect(printed, ['$_tmpId:Globex']);
      expect(pathOf(router), '/clients/$_tmpId');
    });

    testWidgets('off: Save prints nothing', (tester) async {
      final router = await pump(tester, stay: false);
      built.single.setName('Acme Inc');
      await tester.pump();
      await saveAndWaitForPrint(tester);

      expect(printed, isEmpty);
      expect(pathOf(router), '/clients/c1');
    });
  });
}

/// Builds nothing on its first frame and a scroll view after — the shape of
/// a PDF pane, whose spinner turns into a preview.
class _LateScrollView extends StatefulWidget {
  const _LateScrollView();

  @override
  State<_LateScrollView> createState() => _LateScrollViewState();
}

class _LateScrollViewState extends State<_LateScrollView> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) => _ready
      ? ListView(children: const [SizedBox(height: 2000)])
      : const SizedBox.shrink();
}
