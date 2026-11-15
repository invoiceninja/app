import 'package:admin/data/models/domain/company_gateway.dart';

/// Gateway type 32, Card present: the one type that takes no payment online.
const kCardPresentGatewayTypeId = '32';

/// Whether a customer could pay one of the company's invoices online, by the
/// best the device knows: an active gateway with a payment type switched on
/// other than Card present. The Stripe gateway Tap to Pay uses also takes
/// cards online, so this is false only when every online type is off (or
/// there is no gateway at all).
///
/// An active gateway that lists no types (a row from before they were kept)
/// counts as able: nothing local says it isn't. Which gateways the portal
/// offers one client, in one currency, the device doesn't model either — the
/// portal has the last word.
bool canTakeOnlinePayments(Iterable<CompanyGateway> gateways) {
  for (final g in gateways) {
    if (g.isDeleted || g.archivedAt != 0) continue;
    if (g.feesAndLimits.isEmpty) return true;
    for (final e in g.feesAndLimits.entries) {
      if (e.key != kCardPresentGatewayTypeId && e.value.isEnabled) return true;
    }
  }
  return false;
}
