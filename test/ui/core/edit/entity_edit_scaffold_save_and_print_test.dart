import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/print_after_saving_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/ui/core/edit/entity_edit_scaffold.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';

import '../../../_localization_helper.dart';
import '../../../_support/device_prefs_test_support.dart';

/// Save then Print (docs/after-saving.md § Print After Saving): with the
/// device setting on, a plain Save of an editor that has a print action runs
/// that action's save-then-print — the path Print PDF takes from the editor's
/// menu — and ⌘P / Ctrl+P does the same whatever the setting says.
class _FakeServices implements Services {
  @override
  final UnsavedChangesGuard unsavedChangesGuard = UnsavedChangesGuard();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _Vm extends GenericEditViewModel<String> {
  _Vm({super.original}) : super(initialDraft: original ?? '');

  int saves = 0;

  /// A client-side refusal: `save()` returns null before any outbox row.
  bool invalid = false;

  /// A save that fails outright (a network error, a 5xx).
  bool throws = false;

  void setDraft(String v) => updateDraft(v);

  @override
  Map<String, List<String>> validate() => invalid
      ? const {
          'name': ['required'],
        }
      : const {};

  @override
  Future<SaveResult<String>> performSave() async {
    if (throws) throw Exception('offline');
    saves++;
    return SaveResult(entity: isCreate ? 'tmp_1' : draft, outboxRowId: 1);
  }
}

/// What the scaffold did after a save, in order.
final List<String> _events = [];

Future<void> _pump(
  WidgetTester tester, {
  required _Vm vm,
  required bool printAfterSaving,
  Object? printAction = 'print',
  Widget? body,
}) async {
  _events.clear();
  final prefs = PrintAfterSavingController(
    prefs: prefsWith({DevicePrefKeys.printAfterSaving: printAfterSaving}),
  );
  addTearDown(prefs.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<Services>.value(value: _FakeServices()),
        ChangeNotifierProvider<PrintAfterSavingController>.value(value: prefs),
      ],
      child: MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => EntityEditScaffold<String>(
            vm: vm,
            canSave: !vm.isSaving,
            titleBuilder: (_) => 'Edit',
            bodyBuilder: (_) =>
                body ?? Text('draft ${vm.draft}', key: const Key('body')),
            resetToEmpty: () {},
            printAction: printAction,
            onSaved: (_, saved) => _events.add('saved:$saved'),
            onSavedByAction: (_, saved) => _events.add('savedByAction:$saved'),
            onSaveCleanup: () => _events.add('cleanup'),
            onAfterSaveAction: (_, saved, action) async =>
                _events.add('$action:$saved'),
            onAfterSaveActionOnCreate: (_, saved, action) async {
              _events.add('$action-on-create:$saved');
              return false;
            },
            actionsBuilder: (context, onTap, saveButton) => saveButton,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('entity_edit_save')));
  await tester.pumpAndSettle();
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pumpAndSettle();
}

void main() {
  group('Print After Saving', () {
    testWidgets('on: Save saves an edit, then prints it', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: true);
      vm.setDraft('Acme Inc');

      await _tapSave(tester);

      expect(vm.saves, 1);
      // The print dispatch against the saved record, then the plain Save's
      // own onSaved (After Saving, the reload) — while still mounted.
      expect(_events, ['print:Acme Inc', 'saved:Acme Inc']);
    });

    testWidgets('off: Save only saves', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: false);
      vm.setDraft('Acme Inc');

      await _tapSave(tester);

      expect(vm.saves, 1);
      expect(_events, ['saved:Acme Inc']);
    });

    testWidgets('an editor with nothing to print just saves', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: true, printAction: null);
      vm.setDraft('Acme Inc');

      await _tapSave(tester);

      expect(_events, ['saved:Acme Inc']);
    });

    testWidgets('on: an unchanged record is still saved before it prints', (
      tester,
    ) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: true);

      await _tapSave(tester);

      expect(vm.saves, 1, reason: 'Save re-saves an unchanged record');
      expect(_events, ['print:Acme', 'saved:Acme']);
    });

    testWidgets('on: a save the form refuses does not print', (tester) async {
      final vm = _Vm(original: 'Acme')..invalid = true;
      await _pump(tester, vm: vm, printAfterSaving: true);
      vm.setDraft('Acme Inc');

      await _tapSave(tester);

      expect(vm.saves, 0);
      expect(_events, isEmpty);
    });

    testWidgets('on: a save that fails does not print', (tester) async {
      final vm = _Vm(original: 'Acme')..throws = true;
      await _pump(tester, vm: vm, printAfterSaving: true);
      vm.setDraft('Acme Inc');

      await _tapSave(tester);

      expect(_events, isEmpty);
    });

    testWidgets('on: a new record is created, then printed through the '
        'create path', (tester) async {
      final vm = _Vm();
      await _pump(tester, vm: vm, printAfterSaving: true);
      vm.setDraft('New');

      await _tapSave(tester);

      expect(vm.saves, 1);
      // `onAfterSaveActionOnCreate` (which resolves the tmp id before it
      // dispatches), then the plain Save's onSaved — not the action's
      // onSavedByAction, which would leave for the record whatever After
      // Saving says.
      expect(_events, ['print-on-create:tmp_1', 'saved:tmp_1']);
    });

    testWidgets('on: Enter in a field saves and prints', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(
        tester,
        vm: vm,
        printAfterSaving: true,
        body: Builder(
          builder: (context) => TextField(
            onChanged: vm.setDraft,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FormSaveScope.maybeOf(context)?.trySubmit(),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Typed');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(vm.saves, 1);
      expect(_events, ['print:Typed', 'saved:Typed']);
    });

    testWidgets('on: ⌘S saves and prints', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: true);
      vm.setDraft('Acme Inc');

      await _chord(tester, LogicalKeyboardKey.keyS);

      expect(_events, ['print:Acme Inc', 'saved:Acme Inc']);
    });
  });

  group('⌘P / Ctrl+P', () {
    testWidgets('saves, then prints, with the setting off and no click '
        'first', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: false);
      vm.setDraft('Acme Inc');
      await tester.pump();

      // Nothing was clicked: the form's own focus owner holds focus below
      // the scaffold's `Shortcuts`.
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'entity-edit');
      await _chord(tester, LogicalKeyboardKey.keyP);

      expect(vm.saves, 1);
      expect(_events, ['cleanup', 'print:Acme Inc']);
    });

    testWidgets('fires from inside a text field', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(
        tester,
        vm: vm,
        printAfterSaving: false,
        body: TextField(onChanged: vm.setDraft),
      );
      await tester.enterText(find.byType(TextField), 'Typed');
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(null));

      await _chord(tester, LogicalKeyboardKey.keyP);

      expect(_events, ['cleanup', 'print:Typed']);
    });

    testWidgets('an unchanged record prints without a save, as the menu '
        'does', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: false);

      await _chord(tester, LogicalKeyboardKey.keyP);

      expect(vm.saves, 0);
      expect(_events, ['print:Acme']);
    });

    testWidgets('a refused save does not print', (tester) async {
      final vm = _Vm(original: 'Acme')..invalid = true;
      await _pump(tester, vm: vm, printAfterSaving: false);
      vm.setDraft('Acme Inc');

      await _chord(tester, LogicalKeyboardKey.keyP);

      expect(_events, isEmpty);
    });

    testWidgets('is not bound on an editor with nothing to print', (
      tester,
    ) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: false, printAction: null);
      vm.setDraft('Acme Inc');

      await _chord(tester, LogicalKeyboardKey.keyP);

      expect(vm.saves, 0);
      expect(_events, isEmpty);
    });

    testWidgets('⌘S still only saves with the setting off', (tester) async {
      final vm = _Vm(original: 'Acme');
      await _pump(tester, vm: vm, printAfterSaving: false);
      vm.setDraft('Acme Inc');

      await _chord(tester, LogicalKeyboardKey.keyS);

      expect(_events, ['saved:Acme Inc']);
    });
  });

  test('the chord is ⌘P on Apple platforms and Ctrl+P elsewhere', () {
    for (final p in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      final a = saveAndPrintActivator(p);
      expect((a.meta, a.control), (true, false), reason: '$p');
    }
    for (final p in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.android,
    ]) {
      final a = saveAndPrintActivator(p);
      expect((a.meta, a.control), (false, true), reason: '$p');
    }
  });

  testWidgets('a create form keeps its autofocused field', (tester) async {
    final vm = _Vm();
    final field = FocusNode(debugLabel: 'name');
    addTearDown(field.dispose);
    await _pump(
      tester,
      vm: vm,
      printAfterSaving: false,
      body: TextField(focusNode: field, autofocus: true),
    );

    expect(field.hasPrimaryFocus, isTrue);
  });

  testWidgets('the focus owner takes focus back after a save parks it on '
      'the route', (tester) async {
    final vm = _Vm(original: 'Acme');
    await _pump(tester, vm: vm, printAfterSaving: false);
    vm.setDraft('Acme Inc');

    await _chord(tester, LogicalKeyboardKey.keyS);
    vm.setDraft('Acme Ltd');
    await tester.pumpAndSettle();
    await _chord(tester, LogicalKeyboardKey.keyP);

    expect(vm.saves, 2);
    expect(_events, ['saved:Acme Inc', 'cleanup', 'print:Acme Ltd']);
  });
}
