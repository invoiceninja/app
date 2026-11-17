# List density

Companion to CLAUDE.md § Design system (v2). This doc covers the Normal / Compact list
density: what Compact changes, why it is built the way it is, and what it deliberately
leaves alone. The guard is `test/lint/list_row_density_wiring_test.dart`. No CLAUDE.md
bullet is needed, because the lint test enforces the rule; the touch-target Quick Index
row points here.

## Why it exists

A beta tester reported that a full-screen desktop window showed about 12 invoices, where
the old app showed 20 or more.

- **The cause was the row floor.** `kEntityListRowHeight` puts a 72 px floor under every
  row, but a wide row's content needs only 52 px with a pointer: 10 px padding, the 32 px
  action buttons, and 10 px padding.
- **The old app's rows were smaller.** Its `DataTable` rows were 48 px
  (`kMinInteractiveDimension`).
- **The chrome above the rows adds up.** It takes about 222 px on web or macOS: header
  band 69, status tabs ~46, card inset 24 + 1, column headers 57, then 1 + 24 below (the
  card and most of that inset went in Nov 2026: 8 above the header and nothing below).
- **The result:** (1100 − 222) / 72 ≈ 12 rows.

Normal stays the default and is unchanged, because the tester liked the look. Compact is
opt-in.

| Window height (pointer) | Normal | Compact |
|---|---|---|
| 1100 px | 12 rows | about 23 rows |
| 950 px | 10 rows | about 19 rows |

On a phone, the two-line tile goes from 72 px to about 57 px per row.

## Where the setting lives

- **The preference.** It is `DevicePrefKeys.listDensity` (`list_density`), with values
  `normal` and `compact`. Its scope is `PrefScope.device`, like text size: it is how the
  app looks on this screen, so a sign-out keeps it and a desktop can be Compact while the
  phone stays Normal.
- **The controller.** `ListDensityController` (`lib/app/list_density_controller.dart`)
  owns the preference.
  - Read it through `isCompact`. A stored value this build doesn't know, such as one
    written by a newer build, then still resolves to Normal.
  - The settings control's selection is derived from `isCompact`, so it is never empty.
- **The scope.** `ListDensityScope` (`lib/ui/core/list/list_density_scope.dart`) is an
  `InheritedNotifier`. It is mounted once, in `main.dart`'s `MaterialApp.builder`, around
  the router's child inside `WindowFrame`, so it sits above the router's Navigator.
  - Every route, dialog, sheet and master-detail pane is therefore under it. The toast
    host, hint bar and call-log prompter beside it are not, and none of them reads it.
  - It wraps only that one child so its `main.dart` diff is a few lines, not a re-indent
    of the whole builder.
  - A flip rebuilds only the widgets that read it, never `MaterialApp`.
  - With no scope above (most widget tests), every reader gets Normal. That is why the
    lint test pins that `main.dart` mounts it: nothing else would notice it was missing.
- **The one control.** Device Settings → Theme → **Density** (`display_density`), a
  `SegmentedSettingRow` under Font Size, the other "how much fits on screen" control. It
  is searchable and works at every width.
  - It was "List density" until Compact reached past lists. The pref key
    (`list_density`) and the `ListDensity*` names are historical and stay: renaming the
    key would reset everyone's choice. The label needed new keys (`display_density`,
    `display_density_help`) because `_app_pending.json` cannot reword a key that every
    locale had already translated.
  - Two more doors open onto the same preference, never a second setting: the first-run
    Welcome (docs/first-run-welcome.md § The density choice) and the footer of the
    dashboard's Customize → Panels list (`_DensityControl` in
    `manage_dashboard_cards_sheet.dart`), because someone who finds the dashboard too
    loose reaches for Customize, not Settings. That one closes the scrolling panel list
    rather than joining the fixed footer, which has no height for a second run.
  - There is deliberately no toggle in the list toolbar. One shipped briefly beside the
    Columns button and was removed: a setting changed once per device does not earn a
    permanent slot in every list's header, and the slot cost the search field width it
    could not spare (the Tasks toolbar's view switcher left no room below a ~1036 px
    pane).

## What Compact changes

| Surface | Normal | Compact |
|---|---|---|
| Entity-list row floor (`EntityListRowFloor`) | 52 (was 72 until Nov 2026, the list designs' row) | 40 pointer / 52 touch |
| Entity-list tile padding (`listRowPadding`), vertical | 10; 14 embedded; Client and Vendor 14 | 4 |
| Detail record rows (`listRowVerticalPadding`): activity, document history, pending comment, sends, email history — vertical padding | 14 | 4 |
| The same detail rows' floor (`entityListRowHeight`) | 52 | 40 pointer / 52 touch |
| Column-header strip, vertical (no fill, a rule under it) | 4 | 2 |
| Status-tab strip (`dense:`), vertical | `InSpacing.md` | `InSpacing.sm` |
| Group section header, top / bottom | `lg` / `sm` | `sm` / `xs` |
| Standalone table inset (`entityListTableInset`; no card since Nov 2026) | 24 horizontal, 8 top, 0 bottom | 24 horizontal, 4 top |
| Record screen quick-action tile (`EntityQuickActions`): floor / vertical padding | 56 / 8 | 48 / 4 |
| Form field label (`LabeledField`, `docs/form-fields.md` § Labels sit above the field) | on its own line above the field | inside the field (floating) |
| Record screen standing card (`StandingCard`) padding, vertical only | `InSpacing.lg` | `InSpacing.md` |
| Record screen cards above the tabs — profile and Comments (`DashboardCardShell` inside `RecordColumnScope`): title band top / bottom, body vertical | `lg` / `md`, `md` | `md` / `sm`, `sm` |

The detail record rows also tighten in the overview's Comments card, which hosts the same
row widgets. That is intended: the card shows the same records.

The record-screen rows are the one place Compact reaches above a record's tabs
(invoiceninja/flutter#187). The phone layout already removes what was wasted there for
everyone (`docs/detail-screen-layout.md` § The phone record layout); what is left is taste —
a tile 8 px shorter and tighter cards — so it rides the preference rather than being a
default. The profile cards are `DashboardCardShell`s, the same widget as the dashboard's,
so the trim is gated on `RecordColumnScope` (mounted by `EntityRecordColumn`) or
`DashboardScope` (§ The dashboard), never on the edit forms that share the shell. The compact tile is still above the 44 px touch target. The content sets a tile's
height at normal text, not the floor, so the padding has to tighten with it or the lower
floor does nothing.

## The dashboard

Compact reaches the dashboard too (5.1.26), after a long-time desktop user reported that the
dashboard took more scrolling to show what one glance at 5.0 used to show. Every dashboard
widget reads the preference through `dashboardDense(context)`
(`lib/ui/features/dashboard/widgets/dashboard_density.dart`), so one grep finds them all.

**`dense`, never `compact`.** On the dashboard `compact:` already means the phone form
(`NeedsAttentionBand.compact`, `DashboardRecordRow.compact`, each panel card's `compact:`).
Reusing the word would put two meanings on one parameter.

**`DashboardScope` keeps the forms out.** `DashboardCardShell` is also the section card of
several edit forms. Its dense branch runs only inside `RecordColumnScope` (the record
screen's profile) or `DashboardScope` (mounted around each dashboard body's `ListView`), so
an edit form keeps its size. The shadow comes off only inside `DashboardScope`.

Measured at 1440×900 on the demo company:

| | 5.0 | 5.1 Normal | 5.1 Compact |
|---|---|---|---|
| Needs-attention band | none | 155 px | 87 px |
| Figures | 3 tiles, 108 px | 4 figures, 104 px | 4 figures, ~68 px |
| Chart plot | ~137 | ~245 | ~190 |
| List rows above the fold | 6 (side panel) | 0 | 5 (Invoices & Quotes) |

What changes, Normal → Compact (pointer first, touch in brackets where it differs):

| Surface | Normal | Compact |
|---|---|---|
| Page inset / zone gaps / group gaps | 24 / 24 / 16 | 16 / 12 / 12; period bar → figures 8 |
| Card corner radius (`dashboardCardRadius`) | `r3` (14) | `r2` (10) |
| `DashboardCardShell` header top / bottom, body vertical | `lg` / `md`, `md` | `md` / `sm`, `sm` (the record screen's dense branch) |
| Band list header and failed-saves line floors | 40 [44] | 32 [44] |
| `DashboardRecordRow` action box / vertical padding | 32 / 6 [44 / 6] (the floor also holds the wide form's two-line cells, 32 + 12) | 28 / 2 [44 / 0] → a 32 px row [44]; second lines fold onto the first |
| Stacked band row | 64 [76] | 52 [64] |
| Phone-form row (`compact: true`) | 60, padding `sm` | 52, padding `xs` |
| Figure cards (`OutstandingFigureCard`, `PeriodSummaryCard`, `PeriodFiguresCard`, `KpiCard`) floor | 104 | 64 (`kFigureCardMinHeightDense`); a phone's period card 72 |
| Figure padding / value sizes | `lg` all round; wide 24, phone 30 / 16 (configured 24) | `lg` × `md`; wide 20, phone 26 / 16 (configured 20) |
| Figure sub-line ("17 unpaid", the trend) | its own line | on the value's line (`_InlineSubline`); a phone's three narrow cells keep their trend line |
| Chart legend | its own line in the body | in the header row on the wide layout (a `Wrap`, so it can answer `IntrinsicHeight`); a phone keeps it in the body |
| Chart plot floor beside Activity / stacked aspect | 220 / 2.4 | 168 / 3.2 (phone 3.0) |
| Activity rows (`ActivityRowDensity.cardDense`) | 26 px avatar, 10 px padding, 2-line title | 22 px avatar, 4 px padding, 1-line title |
| Invoices and Quotes strips | `md` padding | the list's own `dense:` form, `sm` padding |
| Invoices and Quotes rows | 5 `DashboardRecordRow`s | 8, like the other wide list panels |
| Mini task calendar cells | 32 [38] | 26 [38] |
| "Nothing booked this month" | its own line under the grid | beside the month in the nav row |
| Wide list panels' rows (`DashboardListCard.preview` null) | 5 | 8 (`kDensePanelRows`); the lists already fetch 50, so no fetch changes. The phone keeps 3. |
| Phone band with one tab and no sum | View All in a 44 px footer | View All on the tab's line (a `Wrap`, so a long locale drops it to its own line) |
| Phone section gaps | `lg` | `sm` |

**Changed for both densities in the same pass** (the designer's "cards in cards"
proposals, signed off by Hillel):

- Dashboard cards paint no shadow (`shadow1`): the 1 px border carries the edge. Inside
  `DashboardScope` only — a record screen's profile cards and the edit forms keep theirs.
- The needs-attention band has no outer title: it was a header stacked on the list headers
  inside it. A `Semantics` label keeps the region named.
- Count badges inside the band's tabs and the wrapped (dashboard) status strip are fill-only
  (`SidebarBadge.bordered: false`); the rail and the entity lists' strip keep the hairline.
- The dashboard table's first and last columns take the card's own inset (`lg`), so the
  first column starts under the card title.

Left alone: the top bar (it shares `InSizes.headerBand` with the sidebar), the setup
checklist's content (a new account's first screen),
and type sizes other than the figures'.

`test/ui/features/dashboard/widgets/dashboard_density_test.dart` measures the rows (32
pointer, 44 touch, 52 / 64 stacked), the inline figure caption, the figure floor growing
at 2× text, and the shell staying unchanged outside `DashboardScope`; the band test pins
the dropped title and the kept semantics label.

## Why it is built this way

**`ThemeData.visualDensity` is not the lever.** No list row is a `ListTile` or a
`DataTable`, and the row action buttons pin their own `fixedSize` with `shrinkWrap`
(`entity_actions_popup_button.dart`), because their width feeds `colWMoreMenu()`. Changing
the theme density would move nothing in a row.

**The Compact floor is derived, not chosen.** `entityListRowHeight` returns
`max(40, actionButtonSize() + 2 × 4)`.
- **Pointer: 40.** Compact keeps the floor's original job, so a row does not reflow when
  its leading slot swaps between avatar and checkbox: the tallest thing a row always holds
  is a 32 px button, and 32 + 8 = 40.
- **Touch: 52.** The 44 px touch target wins (CLAUDE.md § Design system — touch targets
  are gated on the platform). The floor says so, so that the scaffold's scroll-to-row
  estimate is not 12 px short per row on a tablet.

**The table inset loses only vertical space.** The standalone table has had no card since Nov
2026 (docs/entity-lists.md § A standalone table has no card), so what is left is a gutter. Its
horizontal 24 lines the table up with:
- the header band's row (`entity_list_app_bar.dart`, "aligns … with the table card below")
- the status-tab strip's start (`_statusTabsFor`, `start: wide ? 24`)
- the frameless desktop title bar's nav arrows

The header band is out of scope, so cutting the horizontal inset would break that alignment.

**The status tabs take a `dense` parameter instead of reading the scope.** The dashboard's
Invoices and Quotes panels use the same widget in its `wrap: true` form. Two callers set it —
the list scaffold, and those panels through `dashboardDense` — and the lint pins both, which
keeps the widget presentational and any other reuse at its own size.

**Floors, never heights.** Every change is padding or a `minHeight`. A larger text scale,
or a two-line tile, still grows the row instead of clipping it (CLAUDE.md § Design system,
rule 1).

## Out of scope

- **The header band (search row).** Its height is shared with the sidebar's company row
  across the seam (`InSizes.headerBand`).
- **The embedded list toolbar.** It keeps its 16 / 16 gap.
- **Forms' spacing, the sidebar, and reports.** That includes the edit forms that reuse
  `DashboardCardShell` (`DashboardScope` is what keeps them out). The one thing Compact
  does change on a form is where a field's label is drawn (the table above).
- **The settings-hosted lists** (tax rates, payment terms, groups, users, …). They are
  `ListTile`s in a `FormSection` (`SettingsEntityListScaffold`), with no 72 px floor to
  remove.

## The guard

`test/lint/list_row_density_wiring_test.dart` fails the build if:
- a `*_list_tile.dart` hard-codes its vertical padding (`fromSTEB(16, 10|14, …)`) instead
  of calling `listRowPadding`
- code anywhere in `lib/` outside `entity_list_constants.dart` reads `kEntityListRowHeight`
  (comments excepted) — as a `minHeight:`, a `SizedBox(height:)`, an `itemExtent:` or
  anything else — instead of `entityListRowHeight(context)` / `EntityListRowFloor`
- `lib/main.dart` stops mounting `ListDensityScope` (a commented-out mount counts as
  missing)
- any `EntityListStatusTabs(` call other than the list scaffold's passes `dense:` — the
  one exception is `billing_pipeline_card.dart`, and only as `dense: dashboardDense(…)`

`test/ui/core/list/list_density_test.dart` measures the actual rows: 72 under Normal, 40
with a pointer and 52 on touch under Compact. It also checks that a dense strip is 8 px
shorter, and that the table inset keeps its horizontal 24. The column-header,
section-header and activity-row tests each carry a Compact case of their own.
