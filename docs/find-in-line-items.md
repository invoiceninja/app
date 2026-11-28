# Find in line items

Companion to CLAUDE.md § Detail screens. How ⌘F / Ctrl+F finds text in a billing document's line items, on the record screen and in the editor: why the app needs its own find, where the bar lives, where the searched text comes from, and what each piece is for.

## Why the app has its own find

A beta user who checks long invoices, quotes and purchase orders against each other relied on the browser's Ctrl+F in the React web app (November 2026). On Flutter web the browser's find finds nothing: the page is painted on a canvas, so it has no text for the browser to search. Natively there never was one. So the record screen answers the chord itself.

## Find in line items is ⌘F on a billing record, and its bar pins under the tab strip

**⌘F (Apple) / Ctrl+F (elsewhere) on an invoice, quote, credit, recurring invoice or purchase order goes to the Overview tab and opens a find bar pinned under the tab strip; the read-only line-items table supplies the searched texts and highlights them.**

- **The chord is bound in `EntityDetailScaffold`, not in the body.** The activator and the action are shared with the editor (`lib/ui/core/utils/find_chord.dart`: `findChordShortcuts`, `FindChordAction`), so the two cannot disagree about the modifier or about firing from a text field. A key reaches only the focused node and its ancestors, and the scaffold's focus owner sits above the body (`docs/keyboard.md` § A record screen's own keys are a fixed map). The body binds what the chord does through `DetailFindNavigator` (`lib/ui/core/detail/detail_find_navigator.dart`), the same pattern as `DetailTabNavigator` for `[` / `]`. With nothing bound, the action is disabled and the chord falls through to the shell, which focuses the screen's search field (`docs/keyboard.md` § ⌘F where there is no find focuses the search field).
- **One modifier per platform, never both.** ⌘F on macOS and iOS, Ctrl+F elsewhere. ⌃F is Cocoa's forward-a-character inside a text field.
- **The chord fires from inside a text field** (`firesInTextInput: () => true`). It types nothing, and pressed again inside the find field it re-selects the query, as a browser's does.
- **The bar is pinned with the strip.** `BillingDocRecordBody` passes the page a `Column(strip, bar)` as its strip, so the bar is in the `PinnedHeaderSliver` and stays on screen while the page scrolls from hit to hit. Inside the card it would scroll away with the first jump. The `Column` has the same shape open or closed, so opening the bar never remounts the strip.
- **Leaving Overview closes the bar.** Tab bodies stay mounted offstage, with `TickerMode` off (`EntityDetailTabs`). `BillingDocOverview` closes the find when its `TickerMode` turns off, after the frame, because closing rebuilds the strip.
- **From `kLineItemFindButtonMinLines` (5) drawn lines, the table's header carries a Find button, on every platform.** It is the only way in without a keyboard, and it shows a mouse user the feature exists. It sits beside the Item head, because at the end of the Item column it read as a control of the Quantity column. In the stacked layout, which has no column heads, it gets a slim head of its own. Shorter documents fit on one screen, but the chord still opens the bar there.
- **The field's hint carries no chord.** The hint bar and the `?` dialog draw ⌘F as caps, which plain text cannot (`docs/keyboard.md` § A chord is one cap per glyph).

## The table is the source of the searched texts

**The table hands the controller each drawn line's texts exactly as it renders them (`LineItemFindController.updateRows`), so the bar's count and the table's highlights cannot disagree.**

- The searched slots are `LineFindSegment`: item name, description (as displayed, with date keywords expanded), custom values, quantity, unit cost, discount, tax and line total. Figures count because a browser's find matches them, and checking that charges match is part of the use case. A slot the line does not draw (no discount, no tax) is empty and never matches.
- Both layouts render the same slots. In the stacked layout each figure is its own span, so a hit is marked where it is.
- `updateRows` is called from the table's build, so it never notifies there. A change is announced after the frame, and only when the texts actually changed (deep equality), so there is no rebuild loop.
- A line with a hit drops its line caps, in the Item cell and in the numeric cells (a Tax cell holding three named taxes wraps), so no hit sits behind an ellipsis. Once the cap is lifted, the ellipsis has to go too: with no `maxLines`, an ellipsis cuts the text at its first line. In the stacked layout, a line with no item name shows its whole description as the title while it has a hit.

## Matching

`lib/domain/billing/line_item_find.dart` is a leaf over plain strings.

- **Case-insensitive, a phrase, the query trimmed.** This is the browser's find, not the list search's every-word match: someone checking a document looks for the exact text.
- **Matched with a case-insensitive `RegExp` over the original text, never by lowering both sides.** Lowering can change a string's length (`İ` becomes two code units), and every offset after it would point at the wrong characters.
- Hits are ordered line by line, then by slot in the order the chosen layout draws them, then left to right. The stacked layout draws the total on the title line, so it counts the total second (`kStackedFindOrder`). Counted last, Next jumped from the figures at the foot of the line back up to its top. Enter / ↓ steps forward, Shift+Enter / ↑ back, both wrapping. Esc closes and keeps the query for the next open.
- **Enter is a key event and, on the web, a text-input action too.** The engine reports every Return to a focused field as its action, whether or not the framework handled the key, so Enter moved two hits and Shift+Enter (back, then forward) moved none. Enter steps through `stepFromKey`, and `submitted` (the field's action, which is all a soft keyboard's Search key sends) skips a press that has just stepped.
- Every drawn line always carries its own key (`LineItemFindController.rowKey`). A single key moved to the current line changed the widget in two slots on every step, which remounted both lines. After each step, `Scrollable.ensureVisible` puts the current line in the middle of the page, not at the top, because the strip and the bar are pinned over the top.

## The chord reaches a record opened from its list

**A record opened in the master-detail pane by a click on its row answers ⌘F at once, with no click into the record.** The case looks broken on paper: the list's focus owner holds the focus when the row is clicked, the list is *beside* the pane, and the record's `FocusOwnerKeeper` takes back only focus that went *up* (`docs/keyboard.md` § A keeper reclaims focus only when it escaped upward). What moves it is the pane's navigator: opening a record pushes a page, and a pushed `ModalRoute` calls `setFirstFocus` on its enclosing scope, which, since that scope holds the focus, focuses the new page's scope. That is above the record's own node, so the record's keeper claims, and the chord is offered to the record's `Shortcuts`. It holds for the next row clicked with the pane open, and when the list's search field had the focus.

Checked in November 2026, after beta feedback that Ctrl+F did nothing: the report was about the editor, which had no find at all (below). `test/ui/core/detail/detail_find_in_pane_test.dart` pins the pane case, because nothing at a call site shows it, and a change to how the pane's routes are pushed would leave the chord answering nothing.

## The editor tints the matching lines

**⌘F / Ctrl+F in a billing document's editor opens the same bar over the line items, counts matching lines, and tints them — amber for a line with a hit, the accent fill and a 2 px outline for the current one — because each line there is a row of editable fields, where a hit cannot be marked inside the text.** One implementation for all five documents, in `BillingDocEditLayout`.

- **The editor binds the chord itself and owes itself a focus owner.** `BillingDocEditLayout` wraps the whole editor in `Shortcuts` (the shared `findChordShortcuts`) over a retained `_bodyFocus` behind a `FocusOwnerKeeper`, gated on `TickerMode`. An editor opens with focus on the route's scope or the pane's root, above every `Shortcuts` in it, so without the owner the chord did nothing until the user clicked a field. The owner sits below the edit scaffold's ⌘S too, so ⌘S now fires with no click as well. The keeper takes back only focus that went up: a field, a dialog or a sheet keeps what it took.
- **It fires from inside any field of the form.** `FindChordAction` passes `firesInTextInput`, like the record's; it types nothing. Enter-to-save is untouched: the bar's field handles its own Enter (next hit) before `FormSaveScope` could see it.
- **The layout, not the tables, supplies the searched texts.** `BillingDocEditFindRows` hands the controller one row per line of the draft, blank lines included (they never match), so a row's index is the line's index in the draft. The tables cannot be the source as the record's table is: a client document draws its lines in Products / Tasks / Expenses tabs, each table only its own kind, and find counts across all three. Each tab tells its table which draft line each of its rows is (`LineItemFindRows`). Its `PartyCurrencyBuilder` (for the total's currency) is a zero-size sibling of the editor in a passthrough `Stack`, never its parent: it changes shape when a client is picked, and as a parent it remounted the whole editor, the client picker included. The texts are what the fields show (`editorLineFindTexts`): item, description as text, custom values, the figures as typed (no zero), the taxes, and the line total in the document's currency.
- **One hit per line** (`LineItemFindController.oneHitPerLine`). A tint cannot show which of two hits inside a line is the current one, so stepping between them changed the count and nothing on screen. The editor counts lines ("2 of 4" lines); the record still counts every hit.
- **A step follows the hit onto its tab.** On a phone the chord first moves the edit strip to Items (`BillingDocEditTabSelector`), where the bar sits above the scroll host (`BillingDocEditItemsBody`). On a client document `BillingDocItemsTabs` moves to the Products / Tasks / Expenses tab holding the current hit, but only when `revealGeneration` changes (an open, a step, a new query), so a notification that merely re-counted never drags the user back to a tab they left. On the wide layout the bar is pinned over the scrolling page (`BillingDocEditDesktopShell.findBar`). Leaving the narrow Items tab closes the find, as leaving the record's Overview does.
- **The tint never changes the tree above a field.** `LineItemFindRowMarker` wraps every row of the desktop table (the trailing blank row too, as row -1) and every phone card whenever the editor has a find, and the desktop tint is two `DecoratedBox`es that are always there. A wrapper or a `Container` decoration that came and went would remount the row under the field being typed in (`docs/form-fields.md` § A focused field never changes its place in the tree on state). The marker rebuilds only when its own mark changes, so a step repaints two rows, and it does not break the desktop table's row cache (`line_item_table_row_reuse_test`).
- **The current line is scrolled into view by context, not by key.** Each marker registers its context with the controller (`attachRow`), and `_reveal` centres it. The record's `rowKey` would not do here: the editor's rows reorder, and a `GlobalKey` that followed an index would move the editable row under it from line to line.

## Tests

- `test/domain/billing/line_item_find_test.dart`: offsets, case folding, ordering.
- `test/ui/features/billing_shared/line_item_find_test.dart`: counts, marks, stepping (including the web's doubled Enter), Esc, the lifted cap, the stacked layout and its order, figures, the Find button, and Ctrl+F through `EntityDetailScaffold` with no click first. Its harness aligns the table inside the scroll view: otherwise the scroll view's tight width overrides the test's width, and nothing is laid out stacked.
- `test/ui/core/detail/detail_find_in_pane_test.dart`: Ctrl+F on a record opened in the pane by a row click, with the list's focus owner or its search field holding the focus.
- `test/ui/features/billing_shared/edit/billing_doc_edit_find_test.dart`: the editor. Ctrl+F with no click and from a form field, the line count, stepping and wrapping, the tint and the current outline, Esc keeping the query, a chord bound above the editor still firing with no click, following a hit onto the Tasks tab, a purchase order, and the phone (the Items tab, the cards, closing on leaving the tab).

## Not yet

On the editor there is no way in without a keyboard: the record's Find button has no twin there yet, so on a phone or tablet with no keyboard the editor's find cannot be opened. Hits are not marked inside the editor's fields, only their rows are tinted.
