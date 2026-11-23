import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/document.dart';
import 'package:admin/data/repositories/_repository_helpers.dart';
import 'package:admin/data/repositories/document_bearing_repository.dart';
import 'package:admin/data/services/upload_source.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';

/// invoiceninja/app#205: an existing record's edit form shows the record's own
/// documents, live, and its Save must write the CURRENT list back — a draft
/// still holding the list the form opened with would drop a file added,
/// renamed or deleted while the form was open.
void main() {
  const a = Document(id: 'a', name: 'a.pdf');
  const b = Document(id: 'b', name: 'b.png');

  test('a create form offers new files, never the saved panel', () {
    final vm = _RecVM(original: null, stored: StreamController.broadcast());
    expect(vm.offersDocuments, isTrue);
    expect(vm.offersSavedDocuments, isFalse);
    expect(vm.showsDocuments, isTrue);
    expect(vm.savedRecordId, isNull);
  });

  test('an edit form offers the saved panel for its record', () {
    final vm = _RecVM(
      original: const _Rec('r1', 'Acme', [a]),
      stored: StreamController.broadcast(),
    );
    expect(vm.offersDocuments, isFalse);
    expect(vm.offersSavedDocuments, isTrue);
    expect(vm.showsDocuments, isTrue);
    expect(vm.savedRecordId, 'r1');
    expect(vm.savedDocumentsRepository, isNotNull);
  });

  test('the live list lands in draft and baseline: the form stays clean, '
      'and an edit stays an edit', () async {
    final stored = StreamController<List<Document>?>.broadcast();
    addTearDown(stored.close);
    final vm = _RecVM(original: const _Rec('r1', 'Acme', [a]), stored: stored);
    addTearDown(vm.dispose);
    vm.watchSavedDocumentsLive();

    stored.add(const [a, b]);
    await pumpEventQueue();
    expect(vm.savedDocuments, const [a, b]);
    expect(vm.draft.docs, const [a, b]);
    expect(vm.isDirty, isFalse, reason: 'a file uploaded is not an edit');

    vm.rename('Acme Ltd');
    stored.add(const [b]);
    await pumpEventQueue();
    expect(vm.draft, const _Rec('r1', 'Acme Ltd', [b]));
    expect(vm.isDirty, isTrue);
  });

  test('Save sends the list the panel has seen, not the one the form '
      'opened with', () async {
    final stored = StreamController<List<Document>?>.broadcast();
    addTearDown(stored.close);
    final vm = _RecVM(original: const _Rec('r1', 'Acme', [a]), stored: stored);
    addTearDown(vm.dispose);
    vm.watchSavedDocumentsLive();
    stored.add(const [a, b]);
    await pumpEventQueue();
    vm.rename('Acme Ltd');

    final saved = await vm.save();
    expect(saved, const _Rec('r1', 'Acme Ltd', [a, b]));
    expect(vm.isDirty, isFalse);
  });

  test('a list that arrives mid-save waits for it to end, so the save is not '
      'taken for one edited while it was out', () async {
    final stored = StreamController<List<Document>?>.broadcast();
    addTearDown(stored.close);
    final gate = Completer<void>();
    final vm = _RecVM(
      original: const _Rec('r1', 'Acme', [a]),
      stored: stored,
      saveGate: gate.future,
    );
    addTearDown(vm.dispose);
    vm.watchSavedDocumentsLive();
    vm.rename('Acme Ltd');

    final saving = vm.save();
    await pumpEventQueue();
    expect(vm.isSaving, isTrue);
    stored.add(const [a, b]);
    await pumpEventQueue();
    expect(vm.draft.docs, const [a], reason: 'deferred while saving');

    gate.complete();
    await saving;
    expect(vm.editedDuringSave, isFalse);
    expect(vm.isDirty, isFalse);
    expect(vm.draft.docs, const [a, b], reason: 'taken once the save ended');
  });

  test('a record view that fails leaves the form as it was', () async {
    final vm = _RecVM(
      original: const _Rec('r1', 'Acme', [a]),
      stored: StreamController.broadcast(),
      watchThrows: true,
    );
    addTearDown(vm.dispose);
    vm.watchSavedDocumentsLive();
    await pumpEventQueue();
    vm.rename('Acme Ltd');
    expect(await vm.save(), const _Rec('r1', 'Acme Ltd', [a]));
  });
}

class _Rec {
  const _Rec(this.id, this.name, this.docs);

  final String id;
  final String name;
  final List<Document> docs;

  _Rec copyWith({String? name, List<Document>? docs}) =>
      _Rec(id, name ?? this.name, docs ?? this.docs);

  @override
  bool operator ==(Object other) =>
      other is _Rec &&
      other.id == id &&
      other.name == name &&
      _listEq(other.docs, docs);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(docs));

  @override
  String toString() => '_Rec($id, $name, $docs)';
}

bool _listEq(List<Document> x, List<Document> y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

class _RecVM extends GenericEditViewModel<_Rec> {
  // ignore: use_super_parameters — also seeds the initial draft.
  _RecVM({
    required _Rec? original,
    required this.stored,
    this.saveGate,
    this.watchThrows = false,
  }) : super(
         initialDraft: original ?? const _Rec('', '', []),
         original: original,
         companyId: 'co',
       );

  final StreamController<List<Document>?> stored;
  final Future<void>? saveGate;
  final bool watchThrows;

  @override
  PendingUploadsRepository get documentUploadRepository => _NoUploads();

  @override
  SavedDocumentsBinding<_Rec>? get savedDocumentsBinding {
    final id = original?.id;
    if (id == null) return null;
    return SavedDocumentsBinding(
      id: id,
      watch: () {
        if (watchThrows) return Stream.error(StateError('no row'));
        return stored.stream;
      },
      withDocuments: (e, docs) => e.copyWith(docs: docs),
    );
  }

  void rename(String name) => updateDraft(draft.copyWith(name: name));

  @override
  Future<SaveResult<_Rec>> performSave() async {
    await saveGate;
    return SaveResult(entity: draft, outboxRowId: 1);
  }
}

class _NoUploads implements PendingUploadsRepository {
  @override
  Future<void> uploadDocument({
    required String companyId,
    required String entityId,
    required UploadSource source,
  }) async {}

  @override
  Future<void> deleteDocument({
    required String companyId,
    required String entityId,
    required String documentId,
  }) async {}

  @override
  Future<void> setDocumentVisibility({
    required String companyId,
    required String entityId,
    required String documentId,
    required bool isPublic,
  }) async {}

  @override
  Future<List<String>> replaceUnsentDocumentUploads({
    required String companyId,
    required String tempId,
    required Future<void> Function() enqueue,
  }) async => const [];

  @override
  Future<int> requeueUnsentDocumentUploads({
    required String companyId,
    required String tempId,
  }) async => 0;
}
