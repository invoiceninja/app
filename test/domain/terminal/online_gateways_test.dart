import 'package:admin/data/models/domain/company_gateway.dart';
import 'package:admin/domain/terminal/online_gateways.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether an invoice could be paid online, by what the device knows: the
/// signal behind "Pay another way" and the note on the enable screen's Ready
/// (docs/in-person-payments.md).
void main() {
  CompanyGateway gateway(
    Map<String, bool> types, {
    bool deleted = false,
    int archivedAt = 0,
  }) => const CompanyGateway(id: 'cg', gatewayKey: 'stripe').copyWith(
    isDeleted: deleted,
    archivedAt: archivedAt,
    feesAndLimits: {
      for (final e in types.entries) e.key: FeesAndLimits(isEnabled: e.value),
    },
  );

  test('no gateway at all: not payable online', () {
    expect(canTakeOnlinePayments(const []), isFalse);
  });

  test('a Stripe gateway taking cards in person only: not payable online', () {
    expect(
      canTakeOnlinePayments([
        gateway({'1': false, '2': false, kCardPresentGatewayTypeId: true}),
      ]),
      isFalse,
    );
  });

  test('any online type switched on counts', () {
    expect(
      canTakeOnlinePayments([
        gateway({'1': true, kCardPresentGatewayTypeId: true}),
      ]),
      isTrue,
    );
  });

  test('a deleted or archived gateway takes nothing', () {
    expect(
      canTakeOnlinePayments([
        gateway({'1': true}, deleted: true),
        gateway({'1': true}, archivedAt: 5),
      ]),
      isFalse,
    );
  });

  test('a gateway that lists no types counts as able: nothing says it '
      "isn't", () {
    expect(canTakeOnlinePayments([gateway(const {})]), isTrue);
  });
}
