// `EntityEditScaffold.titleTrailing` — a billing document's status pill —
// sits between the title and the "Unsaved" label on a wide header, and is not
// drawn on a narrow one (title · status · Unsaved).

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/ui/core/edit/entity_edit_scaffold.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';
import 'package:admin/ui/core/unsaved_changes/unsaved_changes_guard.dart';

import '../../../_localization_helper.dart';

class _FakeServices implements Services {
  _FakeServices(this.unsavedChangesGuard);
  @override
  final UnsavedChangesGuard unsavedChangesGuard;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeVM extends GenericEditViewModel<String> {
  _FakeVM({required super.initialDraft, super.original});

  void edit(String next) => updateDraft(next);

  @override
  Future<SaveResult<String>> performSave() async =>
      SaveResult(entity: draft, outboxRowId: 1);
}

Future<void> _pump(WidgetTester tester, _FakeVM vm, Size surface) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Provider<Services>.value(
        value: _FakeServices(UnsavedChangesGuard()),
        child: EntityEditScaffold<String>(
          vm: vm,
          canSave: true,
          titleBuilder: (_) => 'Edit · #0025',
          titleTrailing: (_) => const Text('STATUS'),
          bodyBuilder: (_) => const SizedBox.shrink(),
          resetToEmpty: () {},
          onSaved: (_, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: title · status · Unsaved', (tester) async {
    final vm = _FakeVM(initialDraft: 'a', original: 'a');
    addTearDown(vm.dispose);
    await _pump(tester, vm, const Size(1200, 700));
    vm.edit('b');
    await tester.pumpAndSettle();

    final title = tester.getTopLeft(find.text('Edit · #0025')).dx;
    final status = tester.getTopLeft(find.text('STATUS')).dx;
    final unsaved = tester.getTopLeft(find.text('Unsaved')).dx;
    expect(title, lessThan(status));
    expect(status, lessThan(unsaved));
  });

  testWidgets('narrow: no status beside the title', (tester) async {
    final vm = _FakeVM(initialDraft: 'a', original: 'a');
    addTearDown(vm.dispose);
    await _pump(tester, vm, const Size(390, 700));
    expect(find.text('STATUS'), findsNothing);
  });
}
