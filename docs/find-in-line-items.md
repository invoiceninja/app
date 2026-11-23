# Find in line items

Companion to CLAUDE.md § Detail screens. How ⌘F / Ctrl+F finds text in a billing document's line items: why the app needs its own find, where the bar lives, where the searched text comes from, and what each piece is for.

## Why the app has its own find

A beta user who checks long invoices, quotes and purchase orders against each other relied on the browser's Ctrl+F in the React web app (November 2026). On Flutter web the browser's find finds nothing: the page is painted on a canvas, so it has no text for the browser to search. Natively there never was one. So the record screen answers the chord itself.

## Find in line items is ⌘F on a billing record, and its bar pins under the tab strip

**⌘F (Apple) / Ctrl+F (elsewhere) on an invoice, quote, credit, recurring invoice or purchase order goes to the Overview tab and opens a find bar pinned under the tab strip; the read-only line-items table supplies the searched texts and highlights them.**

- **The chord is bound in `EntityDetailScaffold`, not in the body.** A key reaches only the focused node and its ancestors, and the scaffold's focus owner sits above the body (`docs/keyboard.md` § A record screen's own keys are a fixed map). The body binds what the chord does through `DetailFindNavigator` (`lib/ui/core/detail/detail_find_navigator.dart`), the same pattern as `DetailTabNavigator` for `[` / `]`. With nothing bound, the action is disabled and the chord falls through.
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

## Tests

- `test/domain/billing/line_item_find_test.dart`: offsets, case folding, ordering.
- `test/ui/features/billing_shared/line_item_find_test.dart`: counts, marks, stepping (including the web's doubled Enter), Esc, the lifted cap, the stacked layout and its order, figures, the Find button, and Ctrl+F through `EntityDetailScaffold` with no click first. Its harness aligns the table inside the scroll view: otherwise the scroll view's tight width overrides the test's width, and nothing is laid out stacked.

## Not yet

The edit screen has no find. Each line there is an editable field, so marking a word in place needs a different approach (tinting the matching rows is the likely shape).
