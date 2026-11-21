# The search palette

Companion to CLAUDE.md § Design system (v2). The ⌘K / Ctrl+K palette — its server answers, how it
filters and ranks them, the category bar, its keys, and when it is a page rather than a card. Code:
`lib/ui/features/shell/widgets/command_palette.dart` (the widget),
`search_palette_results.dart` (pure: parse, filter, rank, group),
`search_palette_scope_bar.dart` (the category bar). Tests: `test/ui/features/shell/command_palette_test.dart`,
`search_palette_results_test.dart`, `test/data/services/search_api_test.dart`.

## The palette filters and ranks on the device

Beta feedback (2026-11-20): typing "Pro" filled the card with clients that did not contain it, and
every other category was below the fold. The user asked for collapsible categories or a filter bar;
two UX reviews and a demo probe found the cause was underneath both.

`POST /api/v1/search` answers in one of two shapes (`SearchController.php`), and **neither can be
rendered as it arrives**:

- **No Elasticsearch — the fallback — ignores the query.** `__invoke` runs `clientMap` /
  `invoiceMap` / `projectMap`, none of which reads `search`: up to 1000 clients with every contact,
  3000 invoices, 3000 projects. The demo answers 26 clients / 116 contacts / 26 invoices /
  25 projects for anything. Names: `Acme`, `Jane Doe <jane@acme.test>`, `Acme - 0025` (invoice:
  client, number), `Website - 0007` (project: name, number).
- **Elasticsearch** fuzzy-matches `fields: ['*']`, caps the whole answer at `size => 100`, and returns
  the groups in a fixed key order (clients first) with `_score` dropped. Each `name` is the model's
  `toSearchableArray` label, translated into the company locale: `Invoice 0042 | Acme | $1,234.00 |
  Nov 3, 2026`, `Client | Acme | VAT123`, `Project 0001 | Website | Acme`, a task's
  `Task 0009 | [ Website ] | Acme ]` (stray brackets and all).

`SearchApi.search` returns a `SearchResponse` whose `serverFiltered` is false for the fallback,
told apart by the **`quotes` key**, which only the ES branch emits (even empty). BACKEND.md
§ Global search has the server asks.

## The fallback is fetched once per open, and only when it really ignored the query

Asking again per keystroke would move the same thousands of rows each time, so the palette keeps
the fallback answer (`_fallbackHits`) and filters every later keystroke on the device, behind a
40 ms debounce (the ES path's is 150 ms) — no request, but a burst of keys still settles before
thousands of rows are re-ranked. It keeps it **only when it has more rows than Elasticsearch ever
sends (100) and `answerIgnoresQuery` sees a record that matches none of the query** — an ES server
from late 2024 answered without the `quotes` key, and its fuzzy hits would pass the record test
alone. The record test is judged per record with its contacts folded in: a server that one day
filters the fallback (by contact, say) without adding `quotes` would otherwise have its answer to
the *first* query reused for every query after it — and a per-row check would misread "Acme", sent
for its contact John, as proof the query was ignored. A pasted record link resolves locally and is
the only hit (`deepLinkSearchHit`); it also closes any open category. **A query-blind answer that
lands after a newer keystroke is still kept** (and the current text re-ranked from it) — dropped as
stale, a steady typist fetched the whole company once per pause and never kept any of it.

**Each row is parsed and folded once** (`_prepare`, cached on the hit in an `Expando`), and the
query's shape once per call (`_QueryShape`): re-ranking the fallback's largest answer (~9,000 rows)
is `search.palette_rank_fallback` in `benchmark/perf/compute_perf_test.dart`.

**The fallback is cut short too**, at 1000 clients (by `updated_at`), 3000 invoices and 3000
projects (`kFallbackGroupCaps`). A group that reached its limit may be missing older records the
device can never see, so `fallbackCappedScopes` marks its count a floor, exactly as an ES answer
at its 100-hit cap is.

## A hit is parsed before anything ranks it

`parseSearchHit` turns each name into a **title**, a **number** and a **subtitle**: on ES, split on
` | `; a numbered group's number is the last token of the first segment (the type before it is
translated, so it is never matched) and only when it holds a digit — a draft is labelled
`Invoice  | Acme | …` and a two-word type would otherwise lend "Invoice" as the number; with no
number the client leads. A numbered group is parsed even with no ` | ` (a task with neither project
nor client is `Task 0001`). A project's title is its name; a client's leading type label is
dropped and its VAT number kept as a matchable extra. A fallback record with no number yet arrives
as `Acme - ` and reads as its name. A contact parses `Name <email>`
(HTML-decoded) and reads as its email when it has no name. Anything unrecognised is the title, as it
arrived. **Never rank the raw string** — on ES every invoice starts with "Invoice", so "inv" would
make all of them prefix matches.

## Match tiers, and what moves within one

`MatchTier`, best first: **exact** (the title is the query; or the number, leading zeros aside —
"42" is `0042`), **prefix**, **word prefix** (after a space, hyphen, comma), **contains**,
**secondary** (only the subtitle / an extra holds it — the client on an invoice), **fuzzy** (ES only:
nothing the row shows holds it). Every word must match somewhere; a multi-word query takes its
weakest word's tier. On the fallback a row with an unmatched word is dropped; on ES it stays, fuzzy.

- An **all-digit** query ranks a number match above a name that merely holds the digits.
- A query holding **`@`** matches a contact's email at full strength (otherwise it is secondary).
- A **recently viewed** record moves ahead within its tier, never across one.
- **Settings** keep the catalog's own order (`searchSettings` ranks on more than the label).
- An **app** hit (Switch Company, Help, What's New…) is found by its curated terms, each matched from
  the start of a word, so it ranks as a prefix match at worst — by name alone "company" buried
  Switch Company under every settings label holding the word.

## Groups, Top hits and caps

- **Scopes:** a contact folds into its client (or vendor), de-duplicated by record id
  (`recordIdForSearchHit`); the client's own row wins a tie, and a row found only through a contact
  reads as the contact, with its email as the subtitle. Release notes, Getting Started, Rate the app, Help and
  company switching share one `app` scope — five near-empty categories were noise.
- **Group order** is by best tier, ties broken by `kPaletteScopeOrder` (the old fixed order).
- **Top hits:** up to 3 rows of tier ≤ prefix, at most 2 from any one group, for a query of ≥ 2
  characters and only when ≥ 2 groups have hits. "Pro" matches a dozen settings labels at prefix
  strength; without the per-group limit, three of them filled Top hits ahead of the client. Lifted out of their groups, never repeated, but **still counted** in
  their group's number, or "Clients 5" would open to 6 rows.
- **All caps a group at 4** (`kPaletteGroupCap`), ending with "Show all N". **Enter on it switches to
  that category and selects the first row the cap hid**, so the user keeps moving forward.
- **A category view** shows every row of that scope and ends, for an entity, with "Search Clients
  for 'Pro'", which opens the real list with the query applied (`ListFilterIntent.search`) — the
  honest way past the server's caps.
- **A count from a capped answer is a floor** — "23+" in the bar (drawn left to right, or Arabic
  reads "+23"), "at least" when announced: an ES answer of 90 hits or more (`mapResults` drops
  deleted hits after the 100 were chosen, so a capped answer arrives a few short), or a fallback
  group at its limit.
- **No match is never a dead end:** "No records found" sits above "Search Clients / Invoices for
  '…'" (`PaletteNoMatches` + `listScopes`, only lists this company can open). The server's answer
  stops at its caps; the paged list does not — and offline the lists still answer from Drift. The
  list opens with the search **and its filters reset** (`ListFilterIntent` replaces, as every
  dashboard intent does): a status filter left in place could hide the very record being looked for.

## The category bar

`SearchPaletteScopeBar`: All, then every category with hits, each with its count — drawn in a
list's status-strip vocabulary (underline, `SidebarBadge` shape, scroll-gated edge fades), but not
that widget, which is built around live Drift count streams and badge-mode tabs.

- **Hidden at rest and until a query hits two categories; once shown it stays until the field is
  cleared.** One that appeared and vanished as a query narrowed moved the list under the thumb.
- **A category a re-query leaves empty stays in the bar, at 0**, with "Show N results in All" in place
  of the rows — never a silent jump.
- **A tap on it shares the field's `TapRegion` group and its `InkWell` cannot take focus**, so the
  soft keyboard stays up.
- Each tab is `SemanticsRole.tab` + `selected`, labelled "Clients, 23 results".

## Keys

Handled in one `Focus.onKeyEvent` above the field, each returning `ignored` when it has nothing to
do so the field keeps the key.

- **↑ / ↓** move the selection (by key, never by index — a re-rank cannot move it to another record).
- **Tab / Shift+Tab** cycle the categories while the bar is shown — **not while a screen reader is
  on** (`MediaQuery.accessibleNavigation`), where Tab must still reach the page's buttons. The footer
  shows "Tab Category" exactly then.
- **⌘↓ / ⌘↑ (Ctrl elsewhere)** jump to the first row of the next / previous group in All —
  Spotlight's category jump. No footer hint; four hint pairs is clutter.
- **Esc** in a category returns to All, keeping the selected row; in All it closes.
- **Enter** opens what is selected, even inside the debounce; with nothing up and a query on its
  way, the first result opens when it lands — only a record (never "Search Clients for …"), and
  not if the text changed since or the request failed (offline, the first local row would be a
  guess). A hardware Enter is taken in `_onKey`, ahead of the field, so it opens the selection on a
  touch tablet with a keyboard too; never mid-composition, and **not on web at all**, where the
  browser submits the field on Enter whether or not a handler took the key — two paths selected
  twice (touch web included: there `_submit` alone decides). Enter while a search is pending and
  the field no longer matches `_query` sets `_enterPending`, so it opens the new text's first
  result when it lands, never the row the previous query selected; a tapped row still opens at
  once. `_select` is guarded against re-entry as well. ← / → stay with the text caret (a "←/→ after ↓" mode was
  proposed and rejected: hidden, fights the caret, flips in RTL).
- **No Backspace-on-empty-field back to All** (the Slack / GitHub gesture): emptying the field
  already returns the palette to rest, so there is never an empty field inside a category.
- **The pointer selects only when it moves** (`MouseRegion.onHover`, not `onEnter`): rows sliding
  under a resting cursor stole the keyboard's selection.

## On touch

- **The soft keyboard's Search runs the search and lowers the keyboard; it opens nothing** — a
  phone has no visible selection to say what it would open. A pasted link is the exception. A
  hardware keyboard's Enter never reaches this path (see § Keys). On text the results already
  answer it ends the wait the keystroke started, or the progress bar spins with nothing coming.
- **No selection is painted on touch until an arrow key is pressed** — a highlighted first row reads
  as a stuck press. So the first ↑ or ↓ on a touch device with a hardware keyboard only shows the
  selection (row 1, or the first recent) and moves nothing; the next one moves. Rows announce
  `selected` only when it is painted.
- **Counts read in the singular for one** (`show_one_result_in_all` and the six
  `*_one_*_announcement` keys): `searchResultsAnnouncementKey` and `searchScopeAnnouncementKey`
  pick the key.
- Both lists dismiss the keyboard on drag.

## A narrow or short window gets the page, never the card

`paletteUsesPage`: `Breakpoints.isPhone`, **or** width < `Breakpoints.wide`, **or** height <
`kPalettePageBelowHeight` (480). `isPhone` alone asks about the device, so a desktop browser or
window at phone width got the card, hung 120 px down over the screen. The page is the
`Dialog.fullscreen` + `AppBar` field phones already had; on macOS its `MediaQuery.padding.top` is
raised to the traffic lights' caption band, or the back arrow sat under them. **`page` and `touch`
are separate questions:** a narrow desktop page keeps its keyboard hints. The tablet card drops
32 px from the top instead of 120 — `Dialog` already insets by the soft keyboard. One `GlobalKey`
keeps the query across a page ⇄ card flip (a fold, a resize).

## A search on its way is not an empty one

From the first key the palette is `_loading`, not only once the debounce fires: between the two the
field held text while the results were still empty, and `build` took that for "No records found",
flashed on every search started from rest (on a phone, the whole page). The progress bar shows
instead.

## Screen readers

Once a query settles (700 ms, only when the text changed, and only while semantics are on) one
announcement: "23 results in 4 categories" or "No records found". A category switch announces
"Clients, 23 results". Group headers are `header: true` + `headingLevel: 2`; a row's label is its
title, subtitle and category.
