import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:admin/app/services_entity_wiring.dart';
import 'package:admin/data/models/api/login_response_api_model.dart';
import 'package:admin/domain/entity_type.dart';

/// The `/refresh` delta fan-out says whether every entity landed, and one
/// entity's failure does not stop the rest — `false` is what holds the
/// company's watermark for a retry (invoiceninja/app#208).
void main() {
  const company = CompanyEnvelopeApi(id: 'co');
  final log = Logger('test');

  Future<bool> run(Map<EntityType, BundleApplier> appliers) =>
      runRefreshDeltaAppliers(
        appliers,
        companyId: 'co',
        company: company,
        fullSync: false,
        log: log,
      );

  BundleApplier ok(List<EntityType> ran, EntityType t) =>
      ({required companyId, required company, required fullSync}) async =>
          ran.add(t);

  test('every applier landed → true', () async {
    final ran = <EntityType>[];
    expect(
      await run({
        EntityType.invoice: ok(ran, EntityType.invoice),
        EntityType.client: ok(ran, EntityType.client),
      }),
      isTrue,
    );
    expect(ran, [EntityType.invoice, EntityType.client]);
  });

  test('one throws → false, and the others still run', () async {
    final ran = <EntityType>[];
    expect(
      await run({
        EntityType.invoice:
            ({required companyId, required company, required fullSync}) =>
                throw StateError('bad row'),
        EntityType.client: ok(ran, EntityType.client),
      }),
      isFalse,
    );
    expect(ran, [EntityType.client]);
  });
}
