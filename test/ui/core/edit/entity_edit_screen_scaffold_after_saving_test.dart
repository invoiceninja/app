import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/after_saving_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/data/repositories/auth_repository.dart';
import 'package:admin/data/repositories/sync_repository.dart';
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

/// Saves the way a repository does without the sync wiring: a create comes
/// back under its `tmp_` id.
class _Vm extends GenericEditViewModel<_Rec> {
  _Vm(_Rec? existing)
    : super(initialDraft: existing ?? const _Rec('', ''), original: existing);

  int saves = 0;

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

  Future<GoRouter> pump(
    WidgetTester tester, {
    required bool stay,
    String initial = '/clients/c1/edit',
    _Rec stored = const _Rec('c1', 'Acme'),
    Future<bool> Function(_Rec saved)? canKeepEditing,
  }) async {
    built = [];
    fetches = 0;
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
            return stored;
          },
          buildVm: (_, _, _, existing) {
            final vm = _Vm(existing);
            built.add(vm);
            return vm;
          },
          canKeepEditing: canKeepEditing == null
              ? null
              : (_, _, _, saved) => canKeepEditing(saved),
          titleBuilder: (_, _) => 'Client',
          titleWhileLoading: (_) => 'Client',
          bodyBuilder: (_, vm) =>
              Text('name ${vm.draft.name}', key: const ValueKey('body')),
          resetToEmpty: (_) {},
          entityIdOf: (draft) => draft.id,
          saveParamFor: (action) => {'mark_sent': 'true'},
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
    final afterSaving = AfterSavingController(
      prefs: prefsWith({DevicePrefKeys.afterSaving: stay}),
    );
    addTearDown(afterSaving.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<Services>.value(value: _FakeServices(db)),
          ChangeNotifierProvider<AfterSavingController>.value(
            value: afterSaving,
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
        'copy, with Save disabled until the next change', (tester) async {
      final router = await pump(tester, stay: true);
      expect(saveEnabled(tester), isFalse, reason: 'nothing to save yet');

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
      expect(saveEnabled(tester), isFalse);

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

    testWidgets('Enter / ⌘S on an unchanged record saves nothing', (
      tester,
    ) async {
      await pump(tester, stay: true);
      final form = tester.element(find.byKey(const ValueKey('body')));
      // What Enter in a field (and the banner's Retry) reaches; ⌘S runs the
      // same handler.
      FormSaveScope.maybeOf(form)!.trySubmit();
      await tester.pumpAndSettle();
      expect(built.first.saves, 0);
    });

    testWidgets('a focused text field keeps Save enabled — its typing may not '
        'have reached the draft', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pump(tester, stay: true);
      expect(saveEnabled(tester), isFalse);
      // Any focused text input counts; mount one beside the form.
      final overlay = tester.state<OverlayState>(find.byType(Overlay).first);
      final entry = OverlayEntry(
        builder: (_) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            child: Material(child: TextField(focusNode: focus)),
          ),
        ),
      );
      overlay.insert(entry);
      addTearDown(entry.remove);
      await tester.pump();
      focus.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('View Record', () {
    testWidgets('an existing record goes to the record', (tester) async {
      final router = await pump(tester, stay: false);
      expect(saveEnabled(tester), isTrue, reason: 'Save is never disabled');
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
}
