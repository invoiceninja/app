# Line-item table columns

Companion to CLAUDE.md § Architecture — at a glance. Which columns the billing-doc editor's desktop line-item table draws, where they come from, and why a column it leaves out never costs a value. The resolver is `lib/ui/features/billing_shared/line_item_editor/line_item_table_columns.dart`; the config that carries the result is `LineItemColumnConfig.desktopColumns`.

## The desktop table draws the company's Invoice Design columns, as React's editor does

The table used to draw every field a line can hold — Item, Description, every custom field, Unit Cost, Quantity, Discount, one column per item tax rate, Line Total. A beta user with several custom fields and taxes got columns too narrow to type in (invoiceninja/app#216). Hillel's call: match React.

React's invoice editor draws the columns the company picked in Settings → Invoice Design → Product Columns (`settings.pdf_variables.product_columns`), with a few forced in. The spec is `useProductColumns` and `useTaskColumns` in React's `src/pages/invoices/common/hooks/` (`origin/develop`), consumed by every editor's `ProductsTable` (`invoices/`, `recurring-invoices/`, `quotes/`, `purchase-orders/` `create/components/CreatePage.tsx` and `edit/Edit.tsx`, and `credits/common/components/CreditProductsTable.tsx`). `resolveLineItemColumnVariables` ports it step for step:

1. Item (`$task.service` on a task table) leads unless the list places it.
2. A list that was empty also gets Description. It gets no Line Total — React's empty path has none.
3. Unit Cost / Rate and Quantity / Hours are appended when missing.
4. `$product.tax` becomes `tax_rate1..N` (N = `enabled_item_tax_rates`) at its place, or at the end when the list doesn't name it.
5. Discount is dropped when `enable_product_discount` is off, appended when it is on — the list can neither add nor remove it.
6. Every custom field the company defines (`product1..4` / `task1..4`) is shown: at its place if listed, appended if not. One listed but not defined is dropped. So custom fields are not reduced by this — React draws them all.
7. A product table drops Quantity when "Show Product Quantity" (`enable_product_quantity`) is off. A task table keeps Hours.
8. Tax Amount, Gross Line Total and Line Total, when listed, move to the end in that order.
9. Net Cost is dropped (React: "net cost is a read-only label on the unit cost column").

Which list: a task table (the Tasks tab) reads Task Columns; a quote's product table reads Quote Product Columns when `sync_invoice_quote_columns` is off (`quotes/edit/Edit.tsx`: `sync ? productColumns : productQuoteColumns`); everything else — invoice, recurring invoice, credit, purchase order, and the Expenses tab — reads Product Columns. React reads the **company** settings, not the client's cascaded ones, and so does this (`lineItemColumnsSection`).

Pinned by `test/ui/features/billing_shared/line_item_table_columns_test.dart`.

## A hidden column hides a field, never its value

Only the desktop table narrows. The phone card list and the line edit dialog still show every field the line can hold (`customFields`, `taxColumnCount`, `showDiscount` on the config), because they are where anything is edited. React has no dialog to compare with.

The table keeps working on the whole line: every row's `_RowState` still seeds a controller for every field from the line (`syncFrom`), whether or not a cell is drawn, and `buildItem` reads them back. An undrawn controller is never edited, so it round-trips the line's own value. `line_item_table_company_columns_test.dart` saves a line with its Description, Quantity, Discount, taxes and a custom value all off the table and checks each survives.

## What this does differently from React, and why

- **No saved list is the catalog default, not an empty list.** React's `|| []` would take its empty-list path (no Line Total) for a company whose `pdf_variables` lacks the section; the settings screen shows `defaultSelected` there and the server's PDF fills the default (`PdfConfiguration::setPdfVariables`), so the table follows them. An explicitly empty list still takes React's path.
- **Unset `sync_invoice_quote_columns` is synced.** React tests it for truthiness; the server's default is true and the settings shell already reads null as true.
- **A variable listed twice is kept once.** Two cells cannot share one field's controller and focus node.
- **A variable with no line field behind it is skipped** (`$product.tags`). React draws a text input bound to a property no line item has.
- **A purchase order now offers the per-line discount** (`LineItemColumnConfig.vendorDocument`). It used `minimal`, which kept discount off a purchase order everywhere; React's purchase-order editor uses `useProductColumns`, so it shows Discount whenever the company enables it, and the server applies it there as on any document.

## Tax Amount and Gross Line Total are read-only figures

React draws them as formatted money from the line's own `tax_amount` / `gross_line_total`. This app's `LineItem` doesn't carry those, so the table computes them from the document the way the server stores them (`InvoiceItemSum::calcTaxes`): `computeLineTaxAmount` — the line's share of the line taxes, the tiers the totals card adds up — and the line total plus that tax (the line total alone with inclusive taxes). They need the document's discount and inclusive-tax setting, so the editor passes `totalsInput`; without one the lines are read alone. They follow the committed line, so they move a debounce after a typed figure.

The table's own Line Total still shows quantity × cost, before the line's discount, as it always has; React shows the post-discount `line_total`. Left alone here.

## Edit Columns sits over the rows' menu

The header's trailing slot (over each row's ⋮) holds an **Edit Columns** button (`line_item_edit_columns`) that goes to the Invoice Design tab the columns came from. It shows only once a company has resolved the columns, and only to an admin or owner — company settings are theirs to change. `go`, not `push`: Settings is its own shell branch, and the editor stays mounted in its own (`StatefulShellRoute.indexedStack`), draft and all.

An optional line's "Optional" caption sits under the last money column drawn — Line Total, unless the company's list leaves it out, then Gross Line Total or Tax Amount; with none of them the row menu's Optional toggle is the only sign.
