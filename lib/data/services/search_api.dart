import 'package:admin/data/models/api/search_result_api_model.dart';
import 'package:admin/data/models/domain/search_result.dart';
import 'package:admin/data/services/api_client.dart';

/// What [SearchApi.search] returns, plus which of the server's two answers
/// it is.
class SearchResponse {
  const SearchResponse(this.hits, {required this.serverFiltered});

  final List<SearchResult> hits;

  /// False for the answer of a server without Elasticsearch
  /// (`SearchController::__invoke`), which **ignores the query** and returns
  /// every client, contact, invoice and project up to its caps. The palette
  /// fetches that once and filters it on the device
  /// (docs/search-palette.md).
  ///
  /// Told apart by the `quotes` key: only the Elasticsearch branch
  /// (`SearchController::search`) returns one, even when it is empty.
  final bool serverFiltered;
}

/// `POST /api/v1/search[?search=q]` — the global command-palette search.
/// Server-backed (like dashboard/reports): it searches *all* records, not
/// just the locally-paginated cache, so it can't be served from Drift.
/// `readOnly: true` — it's a read despite the POST verb (skips the
/// demo-mode block, no outbox row). Response is a map of
/// `{ group: [ {name,type,id,path}, ... ] }`; flattened preserving the
/// group key (the routing discriminator).
class SearchApi {
  SearchApi(this.client);

  final ApiClient client;

  Future<SearchResponse> search(String query) async {
    final q = query.trim();
    final raw = await client.postJson(
      '/api/v1/search',
      query: q.isEmpty ? null : {'search': q},
      readOnly: true,
    );
    if (raw is! Map<String, dynamic>) {
      return const SearchResponse([], serverFiltered: true);
    }
    final out = <SearchResult>[];
    for (final entry in raw.entries) {
      final list = entry.value;
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        out.add(
          SearchResult.fromApi(
            entry.key,
            SearchResultApi.fromJson(Map<String, dynamic>.from(item)),
          ),
        );
      }
    }
    return SearchResponse(out, serverFiltered: raw.containsKey('quotes'));
  }
}
