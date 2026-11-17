import 'package:admin/data/services/api_client.dart';

/// `POST /api/v1/charts/entity_totals` — the exact per-currency figure behind
/// a list's totals line (docs/entity-lists.md § A money list's totals line).
///
/// Body `{"entity": "<quotes|credits|payments|...>"}`; answer
/// `{"data": {"<currency_id>": {"amount": "123.45", "count": 3}, ...}}`,
/// scoped to what the user may view. A server older than the route answers
/// 404 (400 / 405 on some stacks), which `ListTotalsRepository` remembers for
/// the session and answers from Drift instead.
class EntityTotalsApi {
  EntityTotalsApi(this.client);

  final ApiClient client;

  /// The unwrapped `data` object — parse it with `parseEntityTotals`.
  Future<Object?> fetch(String entity) async {
    final raw = await client.postJson(
      '/api/v1/charts/entity_totals',
      body: {'entity': entity},
      readOnly: true,
    );
    if (raw is Map && raw.containsKey('data')) return raw['data'];
    return raw;
  }
}
