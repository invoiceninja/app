# Line-item order across the Products / Tasks / Expenses tabs

Companion to CLAUDE.md § Architecture — at a glance (the billing-doc editor). Where a line's place in the document is decided when the editor splits it into per-kind tabs: `lib/ui/features/billing_shared/items/billing_doc_items_tabs.dart` and the desktop table's row menu in `lib/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart`.

## Move Top / Move Bottom act on the whole document; Move Up / Down stay in the tab

A document's `line_items` is one list, but the editor shows it as a table per kind, and each table only holds its own lines. Edits go back through `mergeBackByType`, which refills each kind's old slots in order and pins every other kind where it was, so a reorder inside a tab can never pass a line of another kind.

The standard designs print products and tasks in separate tables, so that is invisible to them. A custom design that walks `line_items` in its saved order (a Twig loop over the lines, invoiceninja/app#217) prints exactly that list. Its user had a single service followed by products and no way to put the service last: in its own tab it already was, so Move Bottom wasn't offered.

So the tabs hand each table a `LineItemDocumentMoves`:

- **Move Top / Move Bottom** show whenever the line isn't already first / last of the document's non-blank lines (`isFirst` / `isLast`), not just of its tab.
- The table first moves the line to the top / bottom of its own list, so the row's `_RowState` (controllers, keys, autocomplete overlay) stays bound to it as in `_move`. It then calls `move`, and `moveLineToDocumentEdge` merges back and puts that line object (by identity) at the document's start or end.
- **Move Up / Move Down** are unchanged, one step within the tab.

The flags are part of `_RowInputs`, not derived in the row: they read the whole document, which can change (a product added after the last service) while the tab's own lines don't, and the row cache must see it.

`billing_doc_items_tabs_merge_back_test.dart` covers `moveLineToDocumentEdge`; `line_item_document_moves_test.dart` covers the menu and the hand-off.
