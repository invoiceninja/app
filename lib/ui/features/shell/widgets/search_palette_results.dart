/// The search palette's results, filtered, ranked and grouped on the device —
/// pure, no widgets (docs/search-palette.md).
///
/// `POST /api/v1/search` answers in one of two shapes, and neither can be
/// rendered as it arrives:
///
///  * **The fallback** (a server without Elasticsearch, the demo included)
///    ignores the query: it returns up to 1000 clients with every contact,
///    3000 invoices and 3000 projects, unfiltered. Typing "Pro" listed every
///    client. Nothing but the device can filter it.
///  * **Elasticsearch** fuzzy-matches every field, caps the whole answer at
///    100 hits and returns the groups in a fixed order with the score thrown
///    away — so clients always came first and buried the rest. Its `name` is
///    a translated, pipe-joined label (`Invoice 0042 | Acme | $1,234.00 |
///    Nov 3, 2026`), so it has to be parsed before anything can rank it.
///
/// [buildPaletteResults] turns either into a [PaletteResults]: every hit
/// parsed into a title / number / subtitle, scored in tiers, merged (a contact
/// folds into its client), grouped into scopes ordered by their best match,
/// capped, and led by a "Top hits" group.
library;

import 'package:flutter/foundation.dart';

import 'package:admin/data/models/domain/search_result.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/l10n/transifex_php_parser.dart' show decodeHtmlEntities;
import 'package:admin/utils/search_fold.dart';

/// Maps a `POST /api/v1/search` response group key to an [EntityType] so
/// the hit routes through the entity registry (module-enabled + permission
/// gated). `settings` (and any unknown group) → null: the caller falls
/// back to the server-supplied `path`. Pure + unit-tested.
EntityType? entityTypeForSearchGroup(String group) {
  switch (group) {
    case 'clients':
    case 'client_contacts':
      return EntityType.client;
    case 'invoices':
      return EntityType.invoice;
    case 'quotes':
      return EntityType.quote;
    case 'credits':
      return EntityType.credit;
    case 'payments':
      return EntityType.payment;
    case 'recurrings':
    case 'recurring_invoices':
      return EntityType.recurringInvoice;
    case 'projects':
      return EntityType.project;
    case 'tasks':
      return EntityType.task;
    case 'products':
      return EntityType.product;
    case 'expenses':
      return EntityType.expense;
    case 'vendors':
    case 'vendor_contacts':
      return EntityType.vendor;
    case 'purchase_orders':
      return EntityType.purchaseOrder;
    default:
      return null; // settings + anything unknown → use server path
  }
}

/// Groups whose row describes a **contact**, not the record it routes to.
///
/// `SearchController::mapResults` puts the CONTACT's `hashed_id` in `id` and
/// the parent in `path` (`/clients/{client_id}`), so routing by `id` opens a
/// client/vendor that doesn't exist — the detail screen resolves nothing and
/// renders its empty state. Only the Elasticsearch branch does this; the
/// non-ES `clientMap` fallback happens to put the parent id in BOTH fields, so
/// reading the parent out of `path` is correct on either backend.
const _contactGroups = {'client_contacts', 'vendor_contacts'};

/// The id to route a hit by: the parent's id for a contact row (parsed out of
/// the server `path`), otherwise the hit's own `id`.
///
/// Falls back to `id` when `path` is empty or has no trailing segment, so an
/// unexpected server shape degrades to today's behavior rather than to nothing.
String recordIdForSearchHit(SearchResult r) {
  if (!_contactGroups.contains(r.group)) return r.id;
  final segments = Uri.parse(
    r.path,
  ).pathSegments.where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? r.id : segments.last;
}

/// The scope a server or local group is shown under. A contact is shown as
/// the client (or vendor) it belongs to; the palette's small local groups —
/// release notes, Getting Started, Rate the app, Help, company switching —
/// share one `app` scope, since five near-empty categories are noise.
String paletteScopeOf(String group) => switch (group) {
  'client_contacts' => 'clients',
  'vendor_contacts' => 'vendors',
  'recurrings' => 'recurring_invoices',
  'release_notes' ||
  'getting_started' ||
  'rate_the_app' ||
  'help' ||
  'company' => kAppScope,
  _ => group,
};

/// The scope of the palette's own app hits. Also its heading's key ("App").
const String kAppScope = 'app';

/// Scope order when two scopes match equally well — what the palette showed
/// before it ranked anything. Unknown scopes go last, in arrival order.
const List<String> kPaletteScopeOrder = [
  'link',
  'clients',
  'invoices',
  'quotes',
  'credits',
  'recurring_invoices',
  'purchase_orders',
  'expenses',
  'tasks',
  'projects',
  'vendors',
  'payments',
  'products',
  'reports',
  kAppScope,
  'settings',
];

/// The groups whose ES label leads with `<Type> <number>`.
const _numberedGroups = {
  'invoices',
  'quotes',
  'credits',
  'recurring_invoices',
  'recurrings',
  'purchase_orders',
  'expenses',
  'tasks',
  'projects',
};

/// Rows per group in the All view; the rest sit behind "Show all".
const int kPaletteGroupCap = 4;

/// Most rows the Top hits group lifts out of the others.
const int kPaletteTopHits = 3;

/// Most Top hits from any one category, so the group mixes categories.
const int kPaletteTopHitsPerScope = 2;

/// How many rows of each group the fallback answer stops at
/// (`SearchController::clientMap` / `invoiceMap` / `projectMap`). A group that
/// reaches its limit may be missing older records the device can never see,
/// so its count is a floor.
const Map<String, int> kFallbackGroupCaps = {
  'clients': 1000,
  'invoices': 3000,
  'projects': 3000,
};

/// The whole Elasticsearch answer is capped at this many hits
/// (`SearchController::search`, `'size' => 100`), so a scope's count from a
/// capped answer is a floor, not a total.
const int kServerSearchHitCap = 100;

/// An Elasticsearch answer this large is treated as capped: `mapResults`
/// drops deleted hits AFTER the 100 were chosen, so a capped answer usually
/// arrives a few short of 100. Erring this way shows "97+" for a complete
/// 97, never "97" for a cut-short one.
const int kServerSearchNearCap = 90;

/// Match quality, best first. A multi-word query takes its weakest word's.
abstract final class MatchTier {
  /// The title (or number, leading zeros aside) is exactly the query.
  static const exact = 0;

  /// The title starts with it.
  static const prefix = 1;

  /// A word in the title starts with it.
  static const wordPrefix = 2;

  /// The title contains it.
  static const contains = 3;

  /// Only a secondary field (the client on an invoice, an email) holds it.
  static const secondary = 4;

  /// Nothing the row shows holds it — an Elasticsearch fuzzy or
  /// other-field hit, kept but ranked last.
  static const fuzzy = 5;
}

/// One hit, parsed for display and ranking.
@immutable
class PaletteHit {
  const PaletteHit({
    required this.source,
    required this.scope,
    required this.title,
    required this.key,
    required this.tier,
    this.number,
    this.subtitle,
    this.matches = const [],
  });

  /// What routes the row: the server (or local) hit as it arrived. For a
  /// client found only through a contact this is the contact's hit, whose
  /// [recordIdForSearchHit] is the client.
  final SearchResult source;

  /// [paletteScopeOf] the hit's group.
  final String scope;

  /// What the row reads as: a name, or a document's number.
  final String title;

  /// A document's number, when it has one (also matched for "42" → "0042").
  final String? number;

  /// The muted second line: the client, amount and date of a document; the
  /// email a contact was found by.
  final String? subtitle;

  /// Stable identity for selection — survives a re-rank, a scope switch and
  /// a refresh.
  final String key;

  /// [MatchTier] of the hit against the query.
  final int tier;

  /// `[start, end)` runs of [title] that the query matched, for bolding.
  final List<(int, int)> matches;
}

/// One entry of the rendered list.
sealed class PaletteItem {
  const PaletteItem();

  /// Selection identity; null for a header, which can't be selected.
  String? get key;
}

/// A group heading: a scope's label key, or [PaletteHeader.topHits].
class PaletteHeader extends PaletteItem {
  const PaletteHeader(this.scope);

  /// Scope id; also the localization key of its label.
  final String scope;

  static const String topHits = 'top_hits';

  @override
  String? get key => null;
}

class PaletteRow extends PaletteItem {
  const PaletteRow(this.hit, {this.inTopHits = false});

  final PaletteHit hit;

  /// Shown in the Top hits group, so its label names its own scope.
  final bool inTopHits;

  @override
  String get key => hit.key;
}

/// "Show all N" at the foot of a capped group in All.
class PaletteShowAll extends PaletteItem {
  const PaletteShowAll(this.scope, this.count, this.firstHiddenKey);

  final String scope;
  final int count;

  /// The first row the cap hid — selected after the switch, so the user keeps
  /// moving forward rather than back to rows they have already seen.
  final String? firstHiddenKey;

  @override
  String get key => 'show_all|$scope';
}

/// "Search Clients for 'Pro'" — the last row of an entity scope, opening the
/// real, paged list with the query applied: the way past the server's caps.
class PaletteSearchList extends PaletteItem {
  const PaletteSearchList(this.scope, this.type);

  final String scope;
  final EntityType type;

  @override
  String get key => 'search_list|$scope';
}

/// "No records found", above the list searches offered in its place — the
/// server's answer may stop short of the record (its caps), and the paged
/// list does not.
class PaletteNoMatches extends PaletteItem {
  const PaletteNoMatches();

  @override
  String? get key => null;
}

/// The empty state of a scope that has nothing for this query while All does.
class PaletteBackToAll extends PaletteItem {
  const PaletteBackToAll(this.count);

  /// Hits across every scope.
  final int count;

  @override
  String get key => 'back_to_all';
}

/// A scope in the category bar.
@immutable
class PaletteScope {
  const PaletteScope(this.id, this.count, {this.atLeast = false});

  final String id;
  final int count;

  /// The server capped its answer, so [count] is a floor.
  final bool atLeast;
}

/// What the palette renders for one query, in one scope.
@immutable
class PaletteResults {
  const PaletteResults({
    required this.items,
    required this.scopes,
    required this.total,
    required this.totalAtLeast,
  });

  static const empty = PaletteResults(
    items: [],
    scopes: [],
    total: 0,
    totalAtLeast: false,
  );

  final List<PaletteItem> items;

  /// Every scope with hits, in result order (All not included).
  final List<PaletteScope> scopes;

  /// Hits across every scope.
  final int total;

  /// [total] is a floor (the server capped its answer).
  final bool totalAtLeast;

  /// The items that can take the selection, in order.
  List<PaletteItem> get selectable => [
    for (final i in items)
      if (i.key != null) i,
  ];

  bool get isEmpty => items.isEmpty;
}

/// Whether an unfiltered-shaped answer ([SearchResponse.serverFiltered]
/// false) really ignored [query]: it holds a RECORD that matches none of it.
///
/// Only then may the palette keep it and filter every later keystroke on the
/// device. A server that one day filters the fallback — still without the
/// `quotes` key — would otherwise have its answer to the FIRST query reused
/// for every query after it, silently losing results.
///
/// Judged per record, not per row: a server filtering by contact would send
/// "Acme" (the client's own row, which holds no "john") beside its matching
/// contact `John <john@acme.test>`, and a per-row check would read that
/// filtered answer as a query-blind one.
bool answerIgnoresQuery(List<SearchResult> hits, String query) {
  final words = foldedSearchWords(query);
  if (words.isEmpty) return false;
  final matched = <String, bool>{};
  for (final hit in hits) {
    if (hit.isSettings) continue;
    final key = '${paletteScopeOf(hit.group)}|${recordIdForSearchHit(hit)}';
    final p = _prepare(hit, serverFiltered: false);
    final holds = containsEveryWord(p.everything, words);
    matched[key] = (matched[key] ?? false) || holds;
  }
  return matched.values.any((m) => !m);
}

/// The scopes whose group in a fallback answer reached its limit
/// ([kFallbackGroupCaps]), counted over the rows as they arrived.
Set<String> fallbackCappedScopes(List<SearchResult> hits) {
  final counts = <String, int>{};
  for (final hit in hits) {
    counts[hit.group] = (counts[hit.group] ?? 0) + 1;
  }
  return {
    for (final MapEntry(key: group, value: cap) in kFallbackGroupCaps.entries)
      if ((counts[group] ?? 0) >= cap) paletteScopeOf(group),
  };
}

/// Parses, filters, ranks and groups [hits] for [query].
///
/// - [serverFiltered]: false for the fallback answer, whose rows must each
///   match every word of [query] or be dropped. On an Elasticsearch answer a
///   row that matches nothing it shows is kept, ranked [MatchTier.fuzzy].
/// - [serverHitCount]: how many entity hits the server returned, to mark the
///   counts of a capped Elasticsearch answer as floors.
/// - [recents]: `(type, id)` of recently viewed records, most recent first —
///   such a record moves ahead of others in its tier, never across tiers.
/// - [cappedScopes]: scopes the fallback answer cut short
///   ([fallbackCappedScopes]); their counts are floors.
/// - [listScopes]: entity scopes whose own list the palette can search,
///   offered when nothing matched.
/// - [scope]: null for All, else the one scope to show in full.
/// - [localHits]: the palette's own groups (reports, app, settings), already
///   filtered by their own catalogs; ranked by their names alongside.
PaletteResults buildPaletteResults({
  required String query,
  required List<SearchResult> hits,
  required bool serverFiltered,
  List<SearchResult> localHits = const [],
  int serverHitCount = 0,
  List<(EntityType, String)> recents = const [],
  Set<String> cappedScopes = const {},
  List<String> listScopes = const [],
  String? scope,
}) {
  final words = foldedSearchWords(query);
  final q = _QueryShape(query);
  final ranked = <_Ranked>[];
  var order = 0;

  // Server hits — merged by record so a client found through three of its
  // contacts is one row.
  final byRecord = <String, int>{};
  for (final hit in hits) {
    if (hit.isSettings) continue;
    final prepared = _prepare(hit, serverFiltered: serverFiltered);
    final parsed = prepared.parsed;
    // A word that matches nothing the row holds: the fallback's row is not a
    // hit at all; Elasticsearch matched it on a field it doesn't send (or
    // fuzzily), so it stays, last.
    final tier =
        _tierOf(prepared, words, q) ??
        (serverFiltered ? MatchTier.fuzzy : null);
    if (tier == null) continue;
    final scopeId = paletteScopeOf(hit.group);
    final type = entityTypeForSearchGroup(hit.group);
    final recordId = recordIdForSearchHit(hit);
    final key = type != null && recordId.isNotEmpty
        ? '$scopeId|$recordId'
        : '$scopeId|${hit.id}|${hit.name}|${hit.path}';
    final viaContact = _contactGroups.contains(hit.group);
    final entry = _Ranked(
      hit: PaletteHit(
        source: hit,
        scope: scopeId,
        title: parsed.title,
        number: parsed.number,
        subtitle: viaContact
            ? parsed.email ?? parsed.subtitle
            : parsed.subtitle,
        key: key,
        tier: tier,
        matches: _matchRuns(prepared, words),
      ),
      order: order++,
      recent: type == null
          ? -1
          : recents.indexWhere((r) => r.$1 == type && r.$2 == recordId),
      viaContact: viaContact,
    );
    final existing = byRecord[key];
    if (existing == null) {
      byRecord[key] = ranked.length;
      ranked.add(entry);
      continue;
    }
    // A record seen twice (the client and a contact, or two contacts): keep
    // the better match. A client's own row reads better than a contact's, so
    // it wins a tie, and it then names the contact the query matched.
    final prev = ranked[existing];
    final better =
        entry.hit.tier < prev.hit.tier ||
        (entry.hit.tier == prev.hit.tier && prev.viaContact && !viaContact);
    if (better) {
      ranked[existing] = entry.copyWithOrder(prev.order);
    }
  }

  // The palette's own hits — already matched by their catalogs, so a row that
  // holds no query word still stays (Help for "bug"). An app hit is found by
  // its curated terms ("company" → Switch Company), each matched from the
  // start of a word, so it ranks as a prefix match at worst: the name alone
  // would bury it under every settings label holding the word.
  for (final hit in localHits) {
    final scopeId = paletteScopeOf(hit.group);
    final prepared = _prepare(hit, serverFiltered: true);
    var tier = _tierOf(prepared, words, q) ?? MatchTier.secondary;
    if (scopeId == kAppScope && tier > MatchTier.prefix) {
      tier = MatchTier.prefix;
    }
    ranked.add(
      _Ranked(
        hit: PaletteHit(
          source: hit,
          scope: scopeId,
          title: hit.name,
          key: '$scopeId|${hit.group}|${hit.id}|${hit.name}|${hit.path}',
          tier: tier,
          matches: _matchRuns(prepared, words),
        ),
        order: order++,
        recent: -1,
        // Settings keep their catalog's order: `searchSettings` already
        // ranks them, by more than the label this sees.
        keepOrder: scopeId == 'settings',
      ),
    );
  }

  if (ranked.isEmpty) {
    if (query.trim().isEmpty || listScopes.isEmpty) {
      return PaletteResults.empty;
    }
    return PaletteResults(
      items: [
        const PaletteNoMatches(),
        for (final s in listScopes)
          if (entityTypeForSearchGroup(s) case final type?)
            PaletteSearchList(s, type),
      ],
      scopes: const [],
      total: 0,
      totalAtLeast: false,
    );
  }

  // Group, each group sorted best first.
  final groups = <String, List<_Ranked>>{};
  for (final r in ranked) {
    groups.putIfAbsent(r.hit.scope, () => []).add(r);
  }
  for (final g in groups.values) {
    g.sort(_compare);
  }
  int bestTier(String s) =>
      groups[s]!.map((r) => r.hit.tier).reduce((a, b) => a < b ? a : b);
  int baseRank(String s) {
    final i = kPaletteScopeOrder.indexOf(s);
    return i < 0 ? kPaletteScopeOrder.length : i;
  }

  final scopeIds = groups.keys.toList()
    ..sort((a, b) {
      final byTier = bestTier(a).compareTo(bestTier(b));
      if (byTier != 0) return byTier;
      return baseRank(a).compareTo(baseRank(b));
    });

  final esCapped = serverFiltered && serverHitCount >= kServerSearchNearCap;
  final capped = esCapped || cappedScopes.isNotEmpty;
  bool isEntityScope(String s) => entityTypeForSearchGroup(s) != null;
  final scopes = [
    for (final s in scopeIds)
      PaletteScope(
        s,
        groups[s]!.length,
        atLeast: (esCapped && isEntityScope(s)) || cappedScopes.contains(s),
      ),
  ];
  final total = ranked.length;

  // One scope, in full.
  if (scope != null) {
    final rows = groups[scope];
    final type = entityTypeForSearchGroup(scope);
    final items = <PaletteItem>[
      if (rows == null || rows.isEmpty)
        PaletteBackToAll(total)
      else ...[
        PaletteHeader(scope),
        for (final r in rows) PaletteRow(r.hit),
      ],
      // A pasted link is never a list to search, and only an entity scope
      // has one.
      if (type != null && query.trim().isNotEmpty)
        PaletteSearchList(scope, type),
    ];
    return PaletteResults(
      items: items,
      scopes: scopes,
      total: total,
      totalAtLeast: capped,
    );
  }

  // All: Top hits first, lifted out of their groups.
  final top = <_Ranked>[];
  final foldedQuery = foldSearchText(query.trim());
  if (foldedQuery.length >= 2 && scopeIds.length >= 2) {
    final candidates =
        [
          for (final s in scopeIds)
            for (final r in groups[s]!)
              if (r.hit.tier <= MatchTier.prefix) r,
        ]..sort((a, b) {
          final byTier = a.hit.tier.compareTo(b.hit.tier);
          if (byTier != 0) return byTier;
          final byScope = scopeIds
              .indexOf(a.hit.scope)
              .compareTo(scopeIds.indexOf(b.hit.scope));
          if (byScope != 0) return byScope;
          return _compare(a, b);
        });
    // At most two from one category: "Pro" matches a dozen settings labels
    // at prefix strength, and three of them filled Top hits while the
    // client the user was after waited below the fold.
    final perScope = <String, int>{};
    for (final c in candidates) {
      if (top.length == kPaletteTopHits) break;
      final n = perScope[c.hit.scope] ?? 0;
      if (n >= kPaletteTopHitsPerScope) continue;
      perScope[c.hit.scope] = n + 1;
      top.add(c);
    }
  }
  final lifted = {for (final r in top) r.hit.key};

  final items = <PaletteItem>[
    if (top.isNotEmpty) ...[
      const PaletteHeader(PaletteHeader.topHits),
      for (final r in top) PaletteRow(r.hit, inTopHits: true),
    ],
  ];
  for (final s in scopeIds) {
    final rows = [
      for (final r in groups[s]!)
        if (!lifted.contains(r.hit.key)) r,
    ];
    if (rows.isEmpty) continue;
    items.add(PaletteHeader(s));
    for (final r in rows.take(kPaletteGroupCap)) {
      items.add(PaletteRow(r.hit));
    }
    if (rows.length > kPaletteGroupCap) {
      items.add(
        PaletteShowAll(s, groups[s]!.length, rows[kPaletteGroupCap].hit.key),
      );
    }
  }
  return PaletteResults(
    items: items,
    scopes: scopes,
    total: total,
    totalAtLeast: capped,
  );
}

/// A hit's name, parsed into what a row shows (see the library doc for the
/// two shapes).
@immutable
class ParsedSearchHit {
  const ParsedSearchHit({
    required this.title,
    this.number,
    this.subtitle,
    this.email,
    this.extra = const [],
  });

  final String title;
  final String? number;
  final String? subtitle;

  /// A contact's email, matched first for a query holding `@`.
  final String? email;

  /// Fields that match a query but aren't shown — a VAT number.
  final List<String> extra;
}

final RegExp _kContactWithEmail = RegExp(r'^(.*?)\s*<([^<>]+)>\s*$');
final RegExp _kTrailingNumber = RegExp(r'^(.*\S)\s+-\s+(\S+)$');
final RegExp _kTrailingDash = RegExp(r'^(.*\S)\s+-$');
final RegExp _kWhitespaceRun = RegExp(r'\s+');
final RegExp _kTaskBrackets = RegExp(r'^\[\s*|\s*\]$');
final RegExp _kDigit = RegExp(r'\d');
final RegExp _kDigitsOnly = RegExp(r'^\d+$');
final RegExp _kLeadingZeros = RegExp(r'^0+(?=.)');

/// A hit parsed and folded once — the fallback answer is re-ranked on every
/// keystroke, up to ~9,000 rows, so nothing per row is computed twice.
class _Prepared {
  _Prepared(this.parsed, String raw)
    : title = foldSearchText(parsed.title),
      number = parsed.number == null ? null : foldSearchText(parsed.number!),
      email = parsed.email == null ? null : foldSearchText(parsed.email!),
      secondary = foldedSearchLines([parsed.subtitle, ...parsed.extra]),
      everything = foldedSearchLines([
        parsed.title,
        parsed.number,
        parsed.subtitle,
        parsed.email,
        ...parsed.extra,
        raw,
      ]);

  final ParsedSearchHit parsed;
  final String title;
  final String? number;
  final String? email;
  final String secondary;

  /// Every field folded, one per line — what the per-record check reads.
  final String everything;

  late final String titleWords = title.replaceAll(_kWhitespaceRun, ' ');
  late final String? numberNoZeros = number == null
      ? null
      : _stripZeros(number!);
}

final Expando<_Prepared> _preparedFiltered = Expando('palette hit (es)');
final Expando<_Prepared> _preparedFallback = Expando('palette hit (fallback)');

/// [hit] parsed and folded, cached on the hit itself. The palette's own hits
/// (reports, app, settings) are names, never parsed.
_Prepared _prepare(SearchResult hit, {required bool serverFiltered}) {
  final cache = serverFiltered ? _preparedFiltered : _preparedFallback;
  final local =
      entityTypeForSearchGroup(hit.group) == null &&
      !kFallbackGroupCaps.containsKey(hit.group);
  return cache[hit] ??= _Prepared(
    local
        ? ParsedSearchHit(title: hit.name)
        : parseSearchHit(hit, serverFiltered: serverFiltered),
    hit.name,
  );
}

/// What a query is, computed once per call rather than once per row.
class _QueryShape {
  _QueryShape(String query)
    : emailFirst = query.contains('@'),
      digitsOnly = _kDigitsOnly.hasMatch(query.trim()),
      whole = foldSearchText(query.trim()).replaceAll(_kWhitespaceRun, ' ');

  final bool emailFirst;
  final bool digitsOnly;
  final String whole;
  late final String wholeNoZeros = _stripZeros(whole);
}

/// [hit]'s name parsed for display and ranking. Never throws: anything it
/// doesn't recognise becomes the title, as it arrived.
ParsedSearchHit parseSearchHit(
  SearchResult hit, {
  required bool serverFiltered,
}) {
  final raw = decodeHtmlEntities(hit.name).trim();
  if (raw.isEmpty) return ParsedSearchHit(title: hit.name);
  final group = hit.group;

  if (_contactGroups.contains(group)) {
    final m = _kContactWithEmail.firstMatch(raw);
    if (m == null) return ParsedSearchHit(title: raw);
    final name = m.group(1)!.trim();
    final email = m.group(2)!.trim();
    return ParsedSearchHit(
      title: name.isEmpty ? email : name,
      email: email,
      subtitle: email,
    );
  }

  // A numbered group's label is parsed even with no ` | ` in it: a task
  // with neither project nor client is just `Task 0001`.
  if (serverFiltered &&
      (raw.contains(' | ') || _numberedGroups.contains(group))) {
    final parts = [
      for (final p in raw.split(' | '))
        // A task's label wraps its project and client in stray brackets.
        p.replaceAll(_kTaskBrackets, '').trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return ParsedSearchHit(title: raw);
    if (_numberedGroups.contains(group)) {
      // `<Type> <number>` — the type is translated, so take the last token,
      // and only when it holds a digit: a draft with no number is labelled
      // `Invoice  | Acme | …`, and a two-word type ("Recurring Invoice")
      // would otherwise read as type "Recurring", number "Invoice".
      final lead = parts.first.split(_kWhitespaceRun);
      final number = lead.length > 1 && _kDigit.hasMatch(lead.last)
          ? lead.last
          : null;
      final rest = parts.sublist(1);
      if (group == 'projects' && rest.isNotEmpty) {
        // "Project 0001 | Name | Client"
        return ParsedSearchHit(
          title: rest.first,
          number: number,
          subtitle: rest.length > 1 ? rest.sublist(1).join(' · ') : null,
        );
      }
      if (number == null && rest.isNotEmpty) {
        // No number to show: lead with the client, not the type's name.
        return ParsedSearchHit(
          title: rest.first,
          subtitle: rest.length > 1 ? rest.sublist(1).join(' · ') : null,
        );
      }
      return ParsedSearchHit(
        title: number ?? parts.first,
        number: number,
        subtitle: rest.isEmpty ? null : rest.join(' · '),
      );
    }
    // "Client | Acme | VAT123" — the type label leads.
    if (parts.length >= 2) {
      return ParsedSearchHit(title: parts[1], extra: parts.sublist(2));
    }
    return ParsedSearchHit(title: parts.first);
  }

  if (!serverFiltered) {
    // `Acme - ` — a record with no number yet: the name alone.
    final bare = _kTrailingDash.firstMatch(raw);
    if (bare != null && (group == 'invoices' || group == 'projects')) {
      return ParsedSearchHit(title: bare.group(1)!.trim());
    }
    final m = _kTrailingNumber.firstMatch(raw);
    if (m != null) {
      final lead = m.group(1)!.trim();
      final number = m.group(2)!.trim();
      if (group == 'invoices') {
        // "<client> - <number>"
        return ParsedSearchHit(title: number, number: number, subtitle: lead);
      }
      if (group == 'projects') {
        // "<name> - <number>"
        return ParsedSearchHit(title: lead, number: number);
      }
    }
  }
  return ParsedSearchHit(title: raw);
}

/// [MatchTier] of [hit] for [words], or null when a word matches nothing
/// the row holds (see [buildPaletteResults] for what that means on each
/// answer). Empty [words] → [MatchTier.secondary].
int? _tierOf(_Prepared hit, List<String> words, _QueryShape q) {
  if (words.isEmpty) return MatchTier.secondary;
  final title = hit.title;
  final number = hit.number;
  final email = hit.email;

  // The whole query, exactly — a name, or a number with its zeros.
  if (q.whole.isNotEmpty) {
    if (hit.titleWords == q.whole) {
      // An all-digit query that equals a NAME is no better than a contains.
      if (!q.digitsOnly || number == null) return MatchTier.exact;
    }
    if (number != null && hit.numberNoZeros == q.wholeNoZeros) {
      return MatchTier.exact;
    }
    if (q.emailFirst && email != null && email == q.whole) {
      return MatchTier.exact;
    }
  }

  var worst = MatchTier.exact;
  for (final w in words) {
    int? best;
    void consider(int t) {
      if (best == null || t < best!) best = t;
    }

    if (number != null) {
      if (hit.numberNoZeros!.startsWith(_stripZeros(w)) ||
          number.startsWith(w)) {
        consider(MatchTier.prefix);
      } else if (number.contains(w)) {
        consider(MatchTier.contains);
      }
    }
    final titleTier = _textTier(title, w);
    if (titleTier != null) {
      // An all-digit query is after a number; a name that merely holds the
      // digits ranks below every number that does.
      consider(
        q.digitsOnly && number != null
            ? (titleTier + 2).clamp(0, MatchTier.secondary)
            : titleTier,
      );
    }
    if (email != null) {
      final t = _textTier(email, w);
      if (t != null) consider(q.emailFirst ? t : MatchTier.secondary);
    }
    if (hit.secondary.contains(w)) consider(MatchTier.secondary);
    if (best == null) return null;
    if (best! > worst) worst = best!;
  }
  return worst;
}

/// [MatchTier] of [word] in [text] (both folded), or null if absent.
int? _textTier(String text, String word) {
  if (text.isEmpty || word.isEmpty) return null;
  if (text.startsWith(word)) return MatchTier.prefix;
  var at = text.indexOf(word);
  if (at < 0) return null;
  // Any occurrence that starts a word — after a space, a hyphen, a comma.
  while (at >= 0) {
    if (!_isWordChar(text.codeUnitAt(at - 1))) return MatchTier.wordPrefix;
    at = text.indexOf(word, at + 1);
  }
  return MatchTier.contains;
}

bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c > 0x7f;

String _stripZeros(String s) => s.replaceFirst(_kLeadingZeros, '');

/// The `[start, end)` runs of [title] holding a query word, merged — or none
/// when folding changed the title's length (`ß` → `ss`), where the folded
/// offsets would no longer line up with what is drawn.
List<(int, int)> _matchRuns(_Prepared hit, List<String> words) {
  if (words.isEmpty) return const [];
  final folded = hit.title;
  if (folded.length != hit.parsed.title.length) return const [];
  final runs = <(int, int)>[];
  for (final w in words) {
    if (w.isEmpty) continue;
    var from = 0;
    while (true) {
      final at = folded.indexOf(w, from);
      if (at < 0) break;
      runs.add((at, at + w.length));
      from = at + w.length;
    }
  }
  if (runs.isEmpty) return const [];
  runs.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[runs.first];
  for (final r in runs.skip(1)) {
    final last = merged.last;
    if (r.$1 <= last.$2) {
      merged[merged.length - 1] = (last.$1, r.$2 > last.$2 ? r.$2 : last.$2);
    } else {
      merged.add(r);
    }
  }
  return merged;
}

class _Ranked {
  const _Ranked({
    required this.hit,
    required this.order,
    required this.recent,
    this.viaContact = false,
    this.keepOrder = false,
  });

  final PaletteHit hit;

  /// Arrival order — the server's own order within a tier.
  final int order;

  /// Index in the recents list, -1 when not recent.
  final int recent;
  final bool viaContact;

  /// Sort by arrival only (a catalog that ranks itself).
  final bool keepOrder;

  _Ranked copyWithOrder(int order) => _Ranked(
    hit: hit,
    order: order,
    recent: recent,
    viaContact: viaContact,
    keepOrder: keepOrder,
  );
}

int _compare(_Ranked a, _Ranked b) {
  if (a.keepOrder && b.keepOrder) return a.order.compareTo(b.order);
  final byTier = a.hit.tier.compareTo(b.hit.tier);
  if (byTier != 0) return byTier;
  final ar = a.recent < 0 ? 1 << 30 : a.recent;
  final br = b.recent < 0 ? 1 << 30 : b.recent;
  final byRecent = ar.compareTo(br);
  if (byRecent != 0) return byRecent;
  return a.order.compareTo(b.order);
}
