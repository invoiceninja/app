import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/search_result.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/features/shell/widgets/search_palette_results.dart';

SearchResult _hit(String group, String name, {String id = '', String? path}) =>
    SearchResult(group: group, name: name, id: id, path: path ?? '/$group/$id');

/// The rows of [r], in order, as their titles.
List<String> _titles(PaletteResults r) => [
  for (final i in r.items)
    if (i is PaletteRow) i.hit.title,
];

/// The headers of [r], in order.
List<String> _headers(PaletteResults r) => [
  for (final i in r.items)
    if (i is PaletteHeader) i.scope,
];

void main() {
  // The non-Elasticsearch answer, shaped like the demo's: it IGNORES the
  // query, so every client, contact, invoice and project comes back for
  // "Pro" — the screenshot that started this.
  final fallback = [
    _hit('clients', 'Macejkovic-Hintz', id: 'c1'),
    _hit('clients', 'Carter, Reichert and Pouros', id: 'c2'),
    _hit('clients', 'Langworth-Prosacco', id: 'c3'),
    _hit('clients', 'Crooks-Price', id: 'c4'),
    _hit('clients', 'Prosper Ltd', id: 'c5'),
    _hit(
      'client_contacts',
      'Jane Doe <jane@macejkovic.test>',
      id: 'c1',
      path: '/clients/c1',
    ),
    _hit(
      'client_contacts',
      'Pro Buyer <buyer@carter.test>',
      id: 'c2',
      path: '/clients/c2',
    ),
    _hit('invoices', 'Macejkovic-Hintz - 0042', id: 'i1'),
    _hit('invoices', 'Prosper Ltd - 0043', id: 'i2'),
    _hit('projects', 'Website rebuild - 0007', id: 'p1'),
    _hit('projects', 'Pro onboarding - 0008', id: 'p2'),
  ];

  group('parseSearchHit', () {
    test('Elasticsearch labels, in English and German', () {
      final en = parseSearchHit(
        _hit('invoices', 'Invoice 0042 | Acme | \$1,234.00 | Nov 3, 2026'),
        serverFiltered: true,
      );
      expect(en.title, '0042');
      expect(en.number, '0042');
      expect(en.subtitle, 'Acme · \$1,234.00 · Nov 3, 2026');

      final de = parseSearchHit(
        _hit(
          'recurring_invoices',
          'Wiederkehrende Rechnung R-17 | Müller GmbH | 1.234,00 € | 03.11.2026',
        ),
        serverFiltered: true,
      );
      expect(de.number, 'R-17');
      expect(de.subtitle, 'Müller GmbH · 1.234,00 € · 03.11.2026');

      final client = parseSearchHit(
        _hit('clients', 'Kunde | Müller GmbH | DE123'),
        serverFiltered: true,
      );
      expect(client.title, 'Müller GmbH');
      expect(client.extra, ['DE123']);

      final project = parseSearchHit(
        _hit('projects', 'Project 0001 | Website | Acme'),
        serverFiltered: true,
      );
      expect(project.title, 'Website');
      expect(project.number, '0001');
      expect(project.subtitle, 'Acme');

      final task = parseSearchHit(
        _hit('tasks', 'Task 0009 | [ Website ] | Acme ]'),
        serverFiltered: true,
      );
      expect(task.number, '0009');
      expect(task.subtitle, 'Website · Acme');
    });

    test('fallback names', () {
      final inv = parseSearchHit(
        _hit('invoices', 'Acme - 0025'),
        serverFiltered: false,
      );
      expect(inv.title, '0025');
      expect(inv.subtitle, 'Acme');

      final project = parseSearchHit(
        _hit('projects', 'Website - 0007'),
        serverFiltered: false,
      );
      expect(project.title, 'Website');
      expect(project.number, '0007');

      final contact = parseSearchHit(
        _hit('client_contacts', 'Jane Doe &lt;jane@acme.test&gt;'),
        serverFiltered: false,
      );
      expect(contact.title, 'Jane Doe');
      expect(contact.email, 'jane@acme.test');

      // A contact with no name reads as its email.
      final bare = parseSearchHit(
        _hit('client_contacts', ' <ops@acme.test>'),
        serverFiltered: false,
      );
      expect(bare.title, 'ops@acme.test');
    });

    test('labels with no number, or nothing after it', () {
      // A task with neither project nor client: no ` | ` at all.
      final task = parseSearchHit(
        _hit('tasks', 'Task 0001 '),
        serverFiltered: true,
      );
      expect(task.number, '0001');
      expect(task.title, '0001');

      // A draft with no number leads with its client, not "Invoice".
      final draft = parseSearchHit(
        _hit('invoices', 'Invoice  | Acme | \$5.00 | Jan 1'),
        serverFiltered: true,
      );
      expect(draft.title, 'Acme');
      expect(draft.number, isNull);
      expect(draft.subtitle, '\$5.00 · Jan 1');

      // A two-word type with no number is not type "Recurring", number
      // "Invoice".
      final recurring = parseSearchHit(
        _hit('recurring_invoices', 'Recurring Invoice | Acme | \$5.00 | Jan 1'),
        serverFiltered: true,
      );
      expect(recurring.number, isNull);
      expect(recurring.title, 'Acme');

      // The fallback's numberless invoice / project: `Acme - `.
      final bare = parseSearchHit(
        _hit('invoices', 'Acme - '),
        serverFiltered: false,
      );
      expect(bare.title, 'Acme');
      expect(bare.number, isNull);
    });

    test('anything unrecognised is the title, as it arrived', () {
      final odd = parseSearchHit(
        _hit('invoices', 'no number here'),
        serverFiltered: false,
      );
      expect(odd.title, 'no number here');
      expect(odd.number, isNull);
    });
  });

  group('the fallback is filtered on the device', () {
    test('"Pro" keeps only rows that hold it, best match first', () {
      final r = buildPaletteResults(
        query: 'Pro',
        hits: fallback,
        serverFiltered: false,
      );
      final titles = _titles(r);
      expect(titles, isNot(contains('Macejkovic-Hintz')));
      expect(titles, isNot(contains('Crooks-Price')));
      // "Prosper Ltd" starts with it; "Langworth-Prosacco" has a word that
      // does; "Pouros" only contains "ro", not "pro" — gone.
      expect(titles, contains('Prosper Ltd'));
      expect(titles, contains('Langworth-Prosacco'));
      expect(
        titles,
        isNot(contains('Carter, Reichert and Pouros')),
        reason: 'only its contact matched — the client row stands in for it',
      );
      expect(
        titles.indexOf('Prosper Ltd'),
        lessThan(titles.indexOf('Langworth-Prosacco')),
      );
    });

    test('a client found through a contact is one row, naming the contact', () {
      final r = buildPaletteResults(
        query: 'buyer',
        hits: fallback,
        serverFiltered: false,
      );
      final rows = r.items.whereType<PaletteRow>().toList();
      expect(rows, hasLength(1));
      expect(rows.single.hit.title, 'Pro Buyer');
      expect(rows.single.hit.subtitle, 'buyer@carter.test');
      expect(rows.single.hit.scope, 'clients');
      expect(recordIdForSearchHit(rows.single.hit.source), 'c2');
    });

    test('a client and its own contact match: the client row wins', () {
      final r = buildPaletteResults(
        query: 'macejkovic',
        hits: fallback,
        serverFiltered: false,
      );
      final clients = [
        for (final i in r.items)
          if (i is PaletteRow && i.hit.scope == 'clients') i.hit,
      ];
      expect(clients, hasLength(1));
      expect(clients.single.title, 'Macejkovic-Hintz');
    });

    test('"42" finds invoice 0042 as an exact match', () {
      final r = buildPaletteResults(
        query: '42',
        hits: fallback,
        serverFiltered: false,
      );
      final hit = r.items.whereType<PaletteRow>().first.hit;
      expect(hit.title, '0042');
      expect(hit.tier, MatchTier.exact);
    });

    test('a word matched only in a subtitle still finds the row', () {
      final r = buildPaletteResults(
        query: 'prosper',
        hits: fallback,
        serverFiltered: false,
      );
      // Invoice 0043 is Prosper Ltd's — its client is its subtitle.
      expect(_titles(r), containsAll(['Prosper Ltd', '0043']));
      expect(r.scopes.map((s) => s.id), ['clients', 'invoices']);
    });

    test('every word must match, in any field', () {
      final r = buildPaletteResults(
        query: 'prosper 0043',
        hits: fallback,
        serverFiltered: false,
      );
      expect(_titles(r), ['0043']);
    });
  });

  group('answerIgnoresQuery', () {
    test('an answer holding non-matching rows ignored the query', () {
      expect(answerIgnoresQuery(fallback, 'Pro'), isTrue);
    });

    test('judged per record: a client sent for its matching contact counts '
        'as a match', () {
      // What a server filtering the fallback by contact would send for
      // "john": the client's own row (no "john" in it) and its contact.
      final filtered = [
        _hit('clients', 'Acme', id: 'c1'),
        _hit(
          'client_contacts',
          'John Smith <john@acme.test>',
          id: 'c1',
          path: '/clients/c1',
        ),
      ];
      expect(answerIgnoresQuery(filtered, 'john'), isFalse);
    });

    test('an answer that all matches may have been filtered — not cached', () {
      final filtered = [
        _hit('clients', 'Prosper Ltd', id: 'c5'),
        _hit('projects', 'Pro onboarding - 0008', id: 'p2'),
      ];
      expect(answerIgnoresQuery(filtered, 'Pro'), isFalse);
      expect(answerIgnoresQuery(fallback, '  '), isFalse);
    });
  });

  group('the fallback\'s limits', () {
    test('a group at its limit is a floor', () {
      final hits = [
        for (var i = 0; i < kFallbackGroupCaps['clients']!; i++)
          _hit('clients', 'Acme $i', id: 'c$i'),
        _hit('invoices', 'Acme 0 - 0001', id: 'i1'),
      ];
      final capped = fallbackCappedScopes(hits);
      expect(capped, {'clients'});
      final r = buildPaletteResults(
        query: 'acme',
        hits: hits,
        serverFiltered: false,
        cappedScopes: capped,
      );
      expect(r.scopes.firstWhere((s) => s.id == 'clients').atLeast, isTrue);
      expect(r.scopes.firstWhere((s) => s.id == 'invoices').atLeast, isFalse);
      expect(r.totalAtLeast, isTrue);
    });

    test('no match offers the lists to search instead', () {
      final r = buildPaletteResults(
        query: 'zzzq',
        hits: fallback,
        serverFiltered: false,
        listScopes: const ['clients', 'invoices'],
      );
      expect(r.items.first, isA<PaletteNoMatches>());
      expect(r.items.whereType<PaletteSearchList>().map((i) => i.type), [
        EntityType.client,
        EntityType.invoice,
      ]);
      expect(r.total, 0);
    });
  });

  group('Elasticsearch answers', () {
    test('a fuzzy hit that shows no query word is kept, ranked last', () {
      final r = buildPaletteResults(
        query: 'Pro',
        hits: [
          _hit('clients', 'Client | Crooks-Price', id: 'c4'),
          _hit('clients', 'Client | Prosper Ltd', id: 'c5'),
        ],
        serverFiltered: true,
      );
      expect(_titles(r), ['Prosper Ltd', 'Crooks-Price']);
      final fuzzy = r.items.whereType<PaletteRow>().last.hit;
      expect(fuzzy.tier, MatchTier.fuzzy);
    });

    test('an all-digit query puts number matches above name matches', () {
      final r = buildPaletteResults(
        query: '2026',
        hits: [
          _hit('clients', 'Client | Studio 2026', id: 'c1'),
          _hit('invoices', 'Invoice 2026-01 | Acme | \$5.00 | Jan 1', id: 'i1'),
        ],
        serverFiltered: true,
      );
      expect(_headers(r).first, isNot('clients'));
      expect(_titles(r).first, '2026-01');
    });

    test('a query with @ ranks a contact by its email', () {
      final r = buildPaletteResults(
        query: 'jane@acme.test',
        hits: [
          _hit('clients', 'Client | Acme', id: 'c1'),
          _hit(
            'client_contacts',
            'Jane Doe <jane@acme.test>',
            id: 'x1',
            path: '/clients/c9',
          ),
        ],
        serverFiltered: true,
      );
      final top = r.items.whereType<PaletteRow>().first.hit;
      expect(top.title, 'Jane Doe');
      expect(top.tier, MatchTier.exact);
    });

    test('counts from an answer at the 100-hit cap are floors', () {
      final hits = [
        for (var i = 0; i < kServerSearchHitCap; i++)
          _hit('clients', 'Client | Pro $i', id: 'c$i'),
      ];
      final r = buildPaletteResults(
        query: 'pro',
        hits: hits,
        serverFiltered: true,
        serverHitCount: hits.length,
      );
      expect(r.scopes.single.atLeast, isTrue);
      expect(r.totalAtLeast, isTrue);

      final fb = buildPaletteResults(
        query: 'pro',
        hits: [
          for (var i = 0; i < 150; i++) _hit('clients', 'Pro $i', id: 'c$i'),
        ],
        serverFiltered: false,
        serverHitCount: 150,
      );
      expect(
        fb.scopes.single.atLeast,
        isFalse,
        reason: 'the fallback is not capped at 100 — its count is exact',
      );
    });
  });

  group('grouping', () {
    final many = [
      for (var i = 0; i < 7; i++) _hit('clients', 'Acme $i', id: 'c$i'),
      _hit('invoices', 'Acme 0 - 0001', id: 'i1'),
      _hit('invoices', 'Acme 1 - 0002', id: 'i2'),
    ];

    test('All caps a group at four with a Show all row', () {
      final r = buildPaletteResults(
        query: 'zzz acme',
        hits: [
          for (var i = 0; i < 7; i++) _hit('clients', 'zzz Acme $i', id: 'c$i'),
        ],
        serverFiltered: false,
      );
      final rows = r.items.whereType<PaletteRow>();
      expect(rows, hasLength(kPaletteGroupCap));
      final more = r.items.whereType<PaletteShowAll>().single;
      expect(more.count, 7);
      expect(more.firstHiddenKey, 'clients|c4');
    });

    test(
      'Top hits lead, lift their rows out, and counts still include them',
      () {
        final r = buildPaletteResults(
          query: 'acme',
          hits: many,
          serverFiltered: false,
        );
        expect(r.items.first, isA<PaletteHeader>());
        expect((r.items.first as PaletteHeader).scope, PaletteHeader.topHits);
        final top = r.items
            .skip(1)
            .takeWhile((i) => i is PaletteRow)
            .cast<PaletteRow>()
            .toList();
        // Only clients match at prefix strength, and one category gives at most
        // two.
        expect(top, hasLength(kPaletteTopHitsPerScope));
        expect(top.every((t) => t.inTopHits), isTrue);
        final keys = [
          for (final i in r.items)
            if (i is PaletteRow) i.key,
        ];
        expect(keys.toSet(), hasLength(keys.length), reason: 'never twice');
        expect(r.scopes.firstWhere((s) => s.id == 'clients').count, 7);
        expect(r.total, 9);
      },
    );

    test('Top hits take at most two from one category', () {
      final r = buildPaletteResults(
        query: 'pro',
        hits: [_hit('clients', 'Prosper Ltd', id: 'c1')],
        serverFiltered: false,
        localHits: [
          _hit('settings', 'Pro'),
          _hit('settings', 'Product Settings'),
          _hit('settings', 'Project Location'),
        ],
      );
      final top = [
        for (final i in r.items)
          if (i is PaletteRow && i.inTopHits) i.hit.title,
      ];
      expect(top, ['Pro', 'Product Settings', 'Prosper Ltd']);
    });

    test('no Top hits for one category or a one-letter query', () {
      final one = buildPaletteResults(
        query: 'acme',
        hits: [_hit('clients', 'Acme', id: 'c1')],
        serverFiltered: false,
      );
      expect(_headers(one), ['clients']);

      final short = buildPaletteResults(
        query: 'a',
        hits: many,
        serverFiltered: false,
      );
      expect(_headers(short), isNot(contains(PaletteHeader.topHits)));
    });

    test('a group with a better match comes first', () {
      final r = buildPaletteResults(
        query: 'website',
        hits: [
          _hit('clients', 'The Website Shop', id: 'c1'),
          _hit('projects', 'Website - 0007', id: 'p1'),
        ],
        serverFiltered: false,
      );
      // The project IS it (exact); the client only has a word that starts
      // with it — so Projects outranks the clients-first default.
      expect(r.scopes.map((s) => s.id), ['projects', 'clients']);
    });

    test('a recent record leads its tier, never jumps one', () {
      final hits = [
        _hit('clients', 'Acme North', id: 'c1'),
        _hit('clients', 'Acme South', id: 'c2'),
        _hit('clients', 'Big Acme', id: 'c3'),
      ];
      final r = buildPaletteResults(
        query: 'acme',
        hits: hits,
        serverFiltered: false,
        recents: const [(EntityType.client, 'c3'), (EntityType.client, 'c2')],
      );
      expect(_titles(r), ['Acme South', 'Acme North', 'Big Acme']);
    });

    test('a scope shows all its rows, ending with a search of the list', () {
      final r = buildPaletteResults(
        query: 'acme',
        hits: many,
        serverFiltered: false,
        scope: 'clients',
      );
      expect(r.items.whereType<PaletteRow>(), hasLength(7));
      expect(r.items.last, isA<PaletteSearchList>());
      expect((r.items.last as PaletteSearchList).type, EntityType.client);
      expect(r.scopes.map((s) => s.id), containsAll(['clients', 'invoices']));
    });

    test('a scope left empty by a re-query offers the way back to All', () {
      final r = buildPaletteResults(
        query: '0001',
        hits: many,
        serverFiltered: false,
        scope: 'clients',
      );
      expect(r.items.first, isA<PaletteBackToAll>());
      expect((r.items.first as PaletteBackToAll).count, 1);
    });

    test('local hits: settings keep their catalog order; app hits rank as '
        'prefix matches', () {
      final r = buildPaletteResults(
        query: 'company',
        hits: const [],
        serverFiltered: true,
        localHits: [
          _hit('company', 'Switch Company'),
          _hit('settings', 'Company Details'),
          _hit('settings', 'Company Address'),
        ],
      );
      final app = r.items.whereType<PaletteRow>().firstWhere(
        (i) => i.hit.scope == kAppScope,
      );
      expect(app.hit.tier, MatchTier.prefix);
      final settings = [
        for (final i in r.items)
          if (i is PaletteRow && i.hit.scope == 'settings') i.hit.title,
      ];
      expect(settings, ['Company Details', 'Company Address']);
    });

    // The palette's app hits are matched by curated terms, not their label:
    // "changelog" finds "See what's new in v2.0.2", "old app" Getting
    // Started, "review" Rate the app, "bug" Contact Us. None of those labels
    // holds the query, so the on-device filter must keep them anyway, under
    // App (their old one-row headings are gone).
    for (final (query, group, label) in const [
      ('changelog', 'release_notes', "See what's new in v2.0.2"),
      ('version', 'release_notes', "See what's new in v2.0.2"),
      ('old app', 'getting_started', 'Getting Started'),
      ('review', 'rate_the_app', 'Rate the app'),
      ('bug', 'help', 'Contact Us'),
    ]) {
      test('an app hit found only by its terms is kept: "$query"', () {
        final r = buildPaletteResults(
          query: query,
          hits: const [],
          serverFiltered: true,
          localHits: [_hit(group, label)],
        );
        expect(_titles(r), [label]);
        expect(_headers(r), [kAppScope]);
        final row = r.items.whereType<PaletteRow>().single;
        expect(row.hit.scope, kAppScope);
        expect(row.hit.tier, MatchTier.prefix);
      });
    }

    test('an app hit found only by its terms still makes Top hits beside '
        'a settings match', () {
      final r = buildPaletteResults(
        query: 'version',
        hits: const [],
        serverFiltered: true,
        localHits: [
          _hit('release_notes', "See what's new in v2.0.2"),
          _hit('settings', 'Device Settings · App version'),
        ],
      );
      final first = r.items.whereType<PaletteRow>().first;
      expect(first.hit.title, "See what's new in v2.0.2");
      expect(first.inTopHits, isTrue);
      expect(r.scopes.map((s) => s.id), containsAll([kAppScope, 'settings']));
    });

    test('match runs cover the typed words, merged', () {
      final r = buildPaletteResults(
        query: 'lang pro',
        hits: fallback,
        serverFiltered: false,
      );
      final hit = r.items
          .whereType<PaletteRow>()
          .firstWhere((i) => i.hit.title == 'Langworth-Prosacco')
          .hit;
      expect(hit.matches, [(0, 4), (10, 13)]);
    });
  });

  group('a highlight never splits a glyph', () {
    test('a Latin title keeps its runs', () {
      expect(snapHighlightRuns('Prosper Ltd', [(0, 3)]), [(0, 3)]);
    });

    test('a Thai vowel or tone mark stays on its letter', () {
      // ท + ี + ่ is one grapheme; a run of just the consonant left the
      // marks to float in a span of their own.
      expect(snapHighlightRuns('ที่ดิน', [(0, 1)]), [(0, 3)]);
    });

    test('a Khmer coeng keeps its subscript consonant', () {
      // ក + ្ (coeng) + ក: the second ក is drawn under the first.
      expect(snapHighlightRuns('ក្ក', [(0, 2)]), [(0, 3)]);
    });

    test('an Arabic word is bolded whole', () {
      // شركة النور — a run inside the first word takes the word.
      expect(snapHighlightRuns('شركة النور', [(1, 3)]), [(0, 4)]);
      expect(snapHighlightRuns('شركة النور', [(6, 8)]), [(5, 10)]);
    });

    test('only the word in a joining script is widened', () {
      expect(snapHighlightRuns('Acme شركة', [(0, 2)]), [(0, 2)]);
    });

    test('runs that meet once widened are merged', () {
      expect(snapHighlightRuns('شركة', [(0, 1), (2, 3)]), [(0, 4)]);
    });

    test('the match runs a hit carries are snapped', () {
      final r = buildPaletteResults(
        query: 'ت',
        hits: [_hit('clients', 'شركة التقنية', id: 'c1')],
        serverFiltered: true,
        localHits: const [],
        serverHitCount: 1,
      );
      final hit = r.items.whereType<PaletteRow>().single.hit;
      expect(hit.matches, [(5, 12)], reason: 'the whole second word');
    });
  });
}
