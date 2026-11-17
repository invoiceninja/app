# The activity timeline — what `/activity` can draw, and from what

Companion to CLAUDE.md § Design system, which carries the rule in one line. This doc carries the evidence: why the timeline covers only the loaded window, which filters each count leaves out, and why the chart is one colour.

The screen is `lib/ui/features/activity/views/activity_screen.dart`. The bucket and run arithmetic is a pure leaf, `lib/domain/activity/activity_timeline.dart`, so it is unit-tested without a widget (`test/domain/activity/activity_timeline_test.dart`).

## The `/activity` timeline charts only the loaded window, and each count leaves out its own filter

**The window is all there is.** The feed is `GET /api/v1/activities?reactv2&rows=N`: 250 rows (`kActivityFeedRows`), grown by Load more up to 1000 (below). The `reactv2` branch of `ActivityController::index` is `orderBy(created_at)->take($rows)` and nothing else: no page, no offset, no date filter (BACKEND.md § F3). The Activity report (`/reports/activities`) does take a date range, but `ActivityExport::buildActivityRow` returns rendered text (date, sentence, address, notes) with no `activity_type_id` and no record ids, so it can't draw a category or open a record. Everything on this screen is therefore computed on the device over the rows held. The resting readout says so: "N events since <oldest day>".

**Bucket width follows the window.** 250 rows is a morning on a busy account and years on a quiet one, so `bucketSizeFor` picks 15 minutes (≤ 12 hours), 30 minutes (≤ 24 hours), hour (≤ 2 days), day (≤ 62 days), week (≤ 1 year), month (≤ 5 years) or year, which keeps the bar count at or under about 63. The sub-hour widths came from an outside redesign (2026-11-17): on a busy morning hour bars drew three or four slabs with nothing to read between them. A time-of-day tick goes through `Formatter.date(showDate: false, showTime: true)`, so the axis follows the company's 12 / 24-hour setting; dates stay `DateFormat` skeletons (`activityAxisLabel`). Three rules hold the axis steady:

- **Empty periods are zero bars, never missing ones.** A quiet month is the thing the chart exists to show.
- **The axis is computed from the whole window (`spanOf`), not the filtered rows.** Ticking a filter must not rescale the bars under the pointer.
- **Week bars start on the company's first day of week**, else the locale's (`calendarFirstDayOfWeek`). Boundaries are built with `DateTime(y, m, d)`, never by subtracting a `Duration`, so a DST change can't move one off midnight.

**Each count leaves out its own filter — the facet rule.** `ActivityViewModel._recompute` makes one pass and fills three outputs:

| Output | Passes every filter except | Why |
|---|---|---|
| `timeline` | the date range | The bars keep their context while you pick a period; a picked range highlights its bars instead of deleting the rest. |
| `categoryCounts` | the categories | An unticked chip says what ticking it would add, rather than reading 0. |
| `recordTypeCounts` | the record type | The Record type picker offers only the types that would keep a row, each with its count. |
| `entries` / `matchCount` | nothing | This is the feed. |

A category chip whose count is 0 and that isn't already on is disabled, because ticking it could only empty the feed.

**One series, one colour.** Stacking the bars by category would need seven separable hues. The tone palette paints `draft` and `neutral` the same grey (`ink3`), and the rest are status colours, which a chart may not reuse as series colours. Instead, the category filter redraws the bars as just that category. The feed underneath is the chart's table view.

**The readout line replaces a tooltip.** Hovering or dragging rewrites the line above the plot: a big total and a caption naming the period ("7 events since 16/Nov/2026", "3 events · 9:00 AM – 9:15 AM"). A finger mid-drag can still read it, where a floating tooltip would sit under the finger. A screen reader gets it as the one sentence it always was (`activity_timeline_since`, `activityEventCount`); the four caption keys (`activity_readout_*`) are app-local, English-only until translated.

**The category chips sit under the chart on a pane ≥ 600 px** (`kActivityChipsUnderChartMinWidth`), because ticking one redraws the bars and that is where the change is read. The filter rail or dialog then leaves them out (`ActivityFilterPanel.showCategories`) and the header strip drops its category chip — the lit chips are the state. Below 600 px, or wherever the chart is dropped for height, they stay in the filters and the header strip keeps only the removable applied chip.

**The chart sits outside the `SelectionArea`.** A mouse drag across the bars is a range pick. Inside the region it would race text selection for the same drag.

**On a short pane the chart is dropped, never the feed.** Below `kActivityTimelineMinBodyHeight` (420 px of body), the strip goes. That threshold is a landscape phone, which already spends half its height on the app bar, search and chips.

**The date range is stored as instants, not days.** A bar can be fifteen minutes, and a day-granular range could not say "the 3 PM bar". The range is `[from, until)` in local time, persisted as local ISO with no `Z` inside the shared `nav_state` filters blob, so no schema change is needed. The filters offer it as a 2 × 2 grid of toggles — Today, Last 7 Days, Last 30 Days, All Time (`ActivityQuickRange`) — plus a Custom Range button opening the dashboard's period popover (`openDateRangePicker`), and the chart's tap and drag. A quick range is resolved to whole days **when it is picked** (`activityQuickRange`, the last-N ranges through the dashboard's presets), so the filter has one shape and its chip prints the dates it is actually applying. A toggle is lit only while the held range equals what it resolves to today (`activityQuickRangeOf`); a bar, a drag, a calendar pick or yesterday's "Today" lights none, and the Custom Range button carries the dates with a ✕. "All Time" is how the filter says "no range", and the default.

**Runs fold, and only safe ones.** `collapseRuns` folds consecutive rows that share an actor, activity type, target record (`activityDeepLinkTarget`) and local day into one row plus a `+N more` / `Collapse` toggle. Two kinds of row never fold:

- **A row with no target.** "Same type, same user" with no record to agree on is two different events that share a verb.
- **A comment.** Each one is different text.

**The edits that are part of creating a record are not rows.** "Created invoice 0029" then "updated invoice 0029" seconds later by the same person is one act: the app saves a new record and then saves it again, and on a busy afternoon those pairs were half the feed. `absorbCreateEdits` (run before `collapseRuns`) drops an update when the same actor created the same record at most `kCreateEditWindow` (10 minutes) earlier, and the create row's meta line says "also updated" (`activity_also_updated`). It is not a run: a pair folded under a `+1 more` toggle is still two lines. A payment is excluded (`kCreateActivityOfUpdate` has no 10 → 11), since an edit to money already entered is news. The absorbed edits stay on the record's own Activity tab, which is one tap from the row. From an outside redesign of this screen, 2026-11-16.

The day header still counts every row in a run.

## The feed reads like the dashboard card, with the time on each row

**Rows group under the dashboard card's day headers** — "Today", "Yesterday", then the company date, counted in calendar days through `Date` (`activityDayLabel` in `activity_card.dart`, behind `dayHeaderLabel`) — with the day's event count beside the label. The old header counted days with `DateTime.difference(...).inDays`, which a 23-hour DST day turns into "Today" for yesterday. The timeline spine and its day nodes are gone: a leading time column took the space, and the card the rows now match has neither.

**`ActivityFeedRow` sets the filled values apart.** It draws `ActivityRender.segments` as the card does: template words in `ink2`, values (the actor, the record's number, the client) in `ink` at w600, so "Theron Hermiston Dixie Schaefer" reads as one name (`docs/dashboard-panels.md` § The activity card reads who did what, under day headers). User Details shares the row and gets the same weight.

**One line where the row has room, measured on the row.** At `kActivityRowInlineMinWidth` (600 px of row) a page row is the time in a fixed leading column (`LtrText`, tabular figures, width scaled with the text), the icon, the sentence, then the meta (note, IP) at the end. A loopback IP (`127.x`, `::1`) is left out (`displayableActivityIp`, `lib/domain/activity/activity_ip.dart`, also used by the record Activity tab's `ActivityRecordRow`): the server stamps `request()->ip()` on every activity (`Ninja::eventVars`), and a queued job — a reminder, a recurring send, an email — has no request, so it read as "someone at 127.0.0.1" on most rows. Narrower, the time leads the meta line under the sentence. The gate used to read the *window* (`Breakpoints.slideOver`), so a 1024 px window with the sidebar and the filter rail drew one-line rows in a 500 px feed. The card densities never measure: a card can sit in an `IntrinsicHeight` row, where a `LayoutBuilder` throws. Until the company `Formatter` has loaded, the relative time stands in on the meta line (`activityAuditMeta(showTime: false)`).

**A token the row has no value for is an em dash** (`kActivityMissingValue`), not the localized noun. The template's own word already labels the slot, and the noun read as a value: `QuoteRestoredActivity` never sets `quote_id` (BACKEND.md § F3g), so every restore read "restored quote Quote". It now reads "restored quote —", on the record tabs' `buildActivitySpans` too (`activity_record_row_test`).

## The search sits in the title row on a wide pane, and `/` focuses it

From `kActivitySearchInTitleMinWidth` (720 px of pane) the search box sits in the app bar beside refresh, and the feed gets back the row it took; narrower it keeps its full-width row under the title. Either way the box claims `SearchFocusRegistry` in `didChangeDependencies` under the `TickerMode` gate and releases it offstage and on dispose, as `TokenSearchField` does, so the shell's `/` focuses it. With a pointer, its empty unfocused box shows the bound key as a `KeyCapRow`. The header strip keeps "Updated just now" and adds no event count: the chart's big total says it.

## The filters: source, record type and activity type

**Source** is the lens (All / Comments / Calls), now labelled. **Record type** is single-select and derived on the device, since `GET /activities` takes no filters: `activityRecordTypeFor` (`lib/domain/activity/activity_record_types.dart`) maps each `activity_type_id` to the record it is about (`kActivityRecordTypes`, from the server's `Activity` constants), and a type that names none — a comment, written on whatever record it is about — falls back to the most specific record the row references, in `activityDeepLinkTarget`'s order. The type wins over the references because a row's references can be incomplete (a restored quote names only the client). Options leave out their own filter (the facet table above), so a type with no rows under the other filters is not offered. It persists as `record` in the filters blob and has its own removable chip. **Type** (the activity type) is a `MultiEntityPicker`, whose title is now the field's own label and "Add Item" its hint (`docs/pickers.md` § A multi-select has one label). Whether a run is open is view state: it isn't persisted, and it lasts across a refresh only while the run's newest row does.

## The activity cache row is merged, not replaced, and Load more grows it to 1000

**One row, two readers.** The `(company, activities)` row in `dashboard_cache` feeds both the dashboard's 5-row card and this screen. Every fetch used to replace it, so the card's next 250-row refresh would shrink a window the screen had grown. `DashboardRepository.refreshActivities` now merges each fetch into the row through `mergeActivityWindow` (`lib/data/repositories/activity_window.dart`). Older cached rows survive a fetch under two conditions:

- **The fetch must reach back to the newest cached row.** Otherwise both windows are missing something in between, and keeping the old rows would draw a quiet stretch that wasn't quiet. The fetch replaces the row instead.
- **Inside its own time span, the fetch wins.** A cached row there that the fetch no longer returns is dropped. Only rows older than everything fetched carry over, plus rows tied with its oldest second, which the fetch may have cut through.

The result is newest first, trimmed to `kActivityCursorWindowMax` (2500). That is the larger cap on purpose: a window paged back with the cursor (below) must survive the card's next refresh, and a fetch without the cursor never asks for more than `kActivityWindowMax` anyway.

**One refresh at a time.** Each refresh reads the row, merges and writes it back. Two interleaved refreshes would each merge onto the row as it was before the other, and the later write would drop the earlier one's rows. So `refreshActivities` chains its calls, and a failed call doesn't block the chain. `dashboard_repository_test` › activity window pins this with `peakInFlight == 1`.

**Without the server cursor, Load more grows the window.** On a server without `before` (below), `DashboardRepository.loadOlderActivities` asks for the newest `N + 250` rows, capped at `kActivityWindowMax` (1000). Each step re-sends every row before it, which is why the cap exists. The button appears both under the feed and in the timeline's header, since the chart is where the window visibly ends. It is offered only while the window is full: `canLoadMore`. Two things turn it off:

- **A short fetch.** Any fetch that returns fewer rows than it asked for means the history is complete, and the flag stays set.
- **The cap.** At the cap (`ActivityViewModel.windowMax`: 1000 without the cursor, 2500 with it) the footer points to the Activity report instead, and only when `openableReport` would let the route open.

**What the server offers, probed against `demo.invoiceninja.com` on 2026-10-18:**

- **`?reactv2&rows=N` takes any `N`** (`take($rows)` has no cap), at about 120 bytes per row on the demo.
- **The flat `?per_page=N&page=P` branch really pages** (`meta.pagination`), but it carries no labels. A sentence would read "User created invoice" with no number or name, unless every row also asks for `include=client,invoice,…`.
- **That flat branch likely errors for a restricted user** (BACKEND.md § F3, the `assigned_user_id` note). Not probed; the demo token is an admin.

The real fix is a keyset cursor on the `reactv2` branch (BACKEND.md § F3f), which the app already uses where the server has it — next section.

## With the server cursor, Load more pages back instead of re-downloading

**The cursor names an activity.** `GET /activities?reactv2&before=<hashed id>` returns the activities after that one in feed order (BACKEND.md § F3f). `loadOlderActivities` sends the hashed id of the oldest row held (`oldestActivityRow`) and appends the reply with `appendOlderActivities`, which skips rows already held by id. Each Load more then costs one page, so the cap rises to `kActivityCursorWindowMax` (2500), bounded by the cache row's size — every emission of it is decoded whole — rather than by re-download cost.

**Picking the cursor row inside a second is safe.** The payload's `created_at` is whole seconds; the server orders by the stored microseconds. Within the oldest second the app may name a row that isn't the feed's last, and the server then answers with a few rows already held. They are dropped by id; nothing older can be skipped, because everything older is after any row of that second.

**Support is read from the reply, not a version.** A server without the cursor ignores `before` and answers with the newest rows. `pageHonouredCursor` checks that no returned row is newer than the cursor row's second. If one is, the company is remembered as cursor-less for the session and Load more falls back to the growing window. Unknown counts as paged, so the first Load more past 1000 rows still asks. A reply that isn't a list falls back once without being remembered.

**A cursor row the server no longer has is dropped, not re-fetched around.**
- The server answers a `before` naming a deleted activity with a 422, `before: record_not_found`. Purging a client force-deletes all of its activities, so a run of tail rows often goes at once.
- `loadOlderActivities` drops the vanished row from the cache, keeping its `fetchedAt`, and asks again from the next oldest row, up to `DashboardRepository.kActivityCursorGoneHops` (5) times per call. Past that it rethrows, so the footer shows the failure, and the next tap continues from the smaller window.
- It used to re-fetch the newest window instead and let the merge drop the vanished row. A window deeper than that fetch (≥ ~1000 rows) carried every older row over, the vanished one included, so every Load more 422'd on the same row and the button never went away.

**Tests:** `activity_window_test` › paging back with the cursor, `dashboard_repository_test` › loadOlderActivities, `activity_view_model_test` › load more.
