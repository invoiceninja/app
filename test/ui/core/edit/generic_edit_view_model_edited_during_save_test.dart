import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/data/repositories/sync_repository.dart';
import 'package:admin/data/services/connectivity_watcher.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';

/// Online, `save()` waits on the server for up to 30 s. An edit typed in that
/// window was not sent, so it must not be latched clean — a stay-in-editor
/// Save would then reload the form over it, and the guard would let the user
/// leave without it (docs/after-saving.md).
class _Sync implements SyncRepository {
  final reply = Completer<SyncRowResult>();

  @override
  Future<SyncRowResult> awaitRow({
    required int rowId,
    required String companyId,
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 200),
    bool callerWillDisplayFailure = true,
  }) => reply.future;

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _Vm extends GenericEditViewModel<String> {
  _Vm(SyncRepository sync, {String? saved})
    : super(
        initialDraft: saved ?? '',
        original: saved,
        sync: sync,
        connectivity: ConnectivityWatcher.fixed(online: true),
        companyId: 'co',
      );

  void set(String v) => updateDraft(v);

  /// Holds the local write open, when set.
  Completer<void>? write;
  int writes = 0;

  @override
  Future<SaveResult<String>> performSave() async {
    writes++;
    final sent = draft;
    await write?.future;
    return SaveResult(entity: sent, outboxRowId: 1);
  }
}

void main() {
  test('an edit typed while the save was out keeps the form dirty', () async {
    final sync = _Sync();
    final vm = _Vm(sync, saved: 'a')..set('b');
    final saving = vm.save();
    await Future<void>.delayed(Duration.zero);
    vm.set('c');
    sync.reply.complete(const SyncRowResult(outcome: SyncRowOutcome.success));

    expect(await saving, 'b', reason: 'what was sent');
    expect(vm.editedDuringSave, isTrue);
    expect(vm.isDirty, isTrue);
    expect(vm.draft, 'c');
  });

  test('without one the save latches the form clean', () async {
    final sync = _Sync();
    final vm = _Vm(sync, saved: 'a')..set('b');
    final saving = vm.save();
    await Future<void>.delayed(Duration.zero);
    sync.reply.complete(const SyncRowResult(outcome: SyncRowOutcome.success));

    await saving;
    expect(vm.editedDuringSave, isFalse);
    expect(vm.isDirty, isFalse);
  });

  test('a new record still latches clean, and reports the edit so its form can '
      'carry it to the record', () async {
    final sync = _Sync();
    final vm = _Vm(sync)..set('b');
    final saving = vm.save();
    await Future<void>.delayed(Duration.zero);
    vm.set('c');
    sync.reply.complete(const SyncRowResult(outcome: SyncRowOutcome.success));

    await saving;
    expect(vm.editedDuringSave, isTrue);
    expect(vm.isDirty, isFalse);
    expect(vm.draft, 'c');
  });

  test('an edit that ends where it started is no edit', () async {
    // Compared by value, not by count: typing a character and deleting it
    // again leaves nothing unsaved.
    final sync = _Sync();
    final vm = _Vm(sync, saved: 'a')..set('b');
    final saving = vm.save();
    await Future<void>.delayed(Duration.zero);
    vm
      ..set('bx')
      ..set('b');
    sync.reply.complete(const SyncRowResult(outcome: SyncRowOutcome.success));

    await saving;
    expect(vm.editedDuringSave, isFalse);
    expect(vm.isDirty, isFalse);
  });

  test('a keystroke during the local write is an edit too', () async {
    final sync = _Sync();
    final vm = _Vm(sync, saved: 'a')..set('b');
    vm.write = Completer<void>();
    final saving = vm.save();
    await Future<void>.delayed(Duration.zero);
    vm.set('c');
    vm.write!.complete();
    await Future<void>.delayed(Duration.zero);
    sync.reply.complete(const SyncRowResult(outcome: SyncRowOutcome.success));

    expect(await saving, 'b');
    expect(vm.editedDuringSave, isTrue);
    expect(vm.isDirty, isTrue);
  });

  test('a new record already created is not created again', () async {
    // The form is on its way to the record: onSaved awaits a few reads
    // before it navigates, and a Save in that window made it twice.
    final sync = _Sync()
      ..reply.complete(const SyncRowResult(outcome: SyncRowOutcome.success));
    final vm = _Vm(sync)..set('b');
    expect(await vm.save(), 'b');

    vm.set('c');
    expect(await vm.save(), isNull);
    expect(vm.writes, 1);
  });
}
