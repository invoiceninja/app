import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/repositories/base_entity_repository.dart';
import 'package:admin/domain/entity_type.dart';

/// One row of a `/refresh` delta that will not map must not take the rest of
/// the entity's delta with it (invoiceninja/app#208: invoices paid and
/// archived on the server stayed Sent here for days).
typedef _Item = ({String id, int updatedAt, bool maps});

class _Repo extends BaseEntityRepository<Object, Object> {
  _Repo({required super.db}) : super(entityType: EntityType.invoice);

  final upserted = <String>[];

  Future<void> apply(List<_Item> bundle) =>
      applyRefreshDeltaTemplate<_Item, String>(
        companyId: 'co',
        bundle: bundle,
        idOf: (i) => i.id,
        updatedAtOf: (i) => i.updatedAt,
        toCompanion: (i) =>
            i.maps ? 'row ${i.id}' : throw const FormatException('bad'),
        upsert: (byId) async => upserted.addAll(byId.keys),
        storedUpdatedAt: ({required companyId, required ids}) async => {},
      );

  @override
  Stream<Object?> watchByRealId({
    required String companyId,
    required String id,
  }) => const Stream.empty();
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'a row that will not map is skipped and reported; the rest land',
    () async {
      final repo = _Repo(db: db);
      await expectLater(
        repo.apply([
          (id: 'a', updatedAt: 10, maps: true),
          (id: 'bad', updatedAt: 11, maps: false),
          (id: 'c', updatedAt: 12, maps: true),
        ]),
        throwsA(
          isA<RefreshDeltaRowsSkipped>().having((e) => e.ids, 'ids', ['bad']),
        ),
        reason:
            'reported after the rest is written, so the company watermark is '
            'held and the skipped row is asked for again',
      );
      expect(repo.upserted, ['a', 'c']);
    },
  );
}
