# File downloads

Companion to CLAUDE.md § Strict rules. The rule lives there; this doc holds the
per-platform mechanism behind it, where a download lands on each platform, and
the tests that pin it.

## A desktop download writes to the downloads folder through `bytesSaver` / `downloadPdf`, never `Printing.sharePdf`, and every `PdfPreview` gates `allowSharing` on `pdfShareOpensTempCopy()` — on Windows and Linux both only open a temp copy

**The failure it shipped as.** A beta tester: *"Downloading an invoice as PDF
just launches the PDF file and doesn't seem to save to my downloads folder like
previous app behaviour. No settings option for where to save files either?"*
Every Download PDF action called `Printing.sharePdf`, which in printing 5.15.1
does something different on each desktop, and none of it saves a file:

| Platform | `Printing.sharePdf` |
|---|---|
| Windows | writes `%TEMP%\<name>` and `ShellExecute "open"`s it (`windows/print_job.cpp:334`) — the PDF just opens |
| Linux | writes `/tmp/<name>` and `xdg-open`s it (`linux/print_job.cc:250`) |
| macOS | shows the share picker (`PrintJob.swift:229`) |
| iOS / Android | the share sheet — which is what a phone means by Download |
| web | a browser download |

`PdfPreview`'s built-in **Share** button is `PdfShareAction`, which calls the
same `sharePdf` inside the package (`lib/src/preview/actions.dart`).

**Where a download lands now.**

- **Desktop** — `bytesSaver` (`lib/ui/core/utils/save_bytes.dart`) writes
  straight into the downloads folder via `saveToDownloadsFolder`
  (`save_download.dart`) and toasts *"saved in the downloads folder"* (or the
  chosen folder's path) with the file name as the detail and an **Open**
  action. A name already taken gets ` (1)`, ` (2)`… — created with
  `exclusive: true`, so two quick downloads can't both take the same one. This
  is the old app's behaviour (`admin-portal/lib/utils/files.dart`
  `saveDownloadedFile`).
- **Mobile / web** — unchanged: `downloadPdf` shares the PDF; `bytesSaver`
  opens the save dialog.
- **Fallback** — no usable downloads folder, or a failed write, opens the save
  dialog. A chosen folder that is gone toasts `downloads_folder_does_not_exist`
  first, then opens the dialog, so the download is never dropped.

Every "Download" goes through it — the billing-doc PDF actions, the bulk
single-row download, the PDF pane's Download button, a document's Download, the
client-portal QR code, the e-purchase-order XML. Report and CSV **exports**
call `saveBytesFile` directly and keep the dialog: they are Export, not
Download.

**The folder setting.** Device Settings → *Downloads Folder*
(`DevicePrefKeys.downloadsFolder`, device scope; empty = the OS folder).

- **Windows / Linux** choose one with Select / Reset. No free-text field: a
  typed path is how a folder that doesn't exist gets saved.
- **macOS** shows Downloads read-only, with Open. A folder picked in the
  sandboxed build is granted only for that launch — keeping it needs
  security-scoped bookmarks — so `downloadsFolderEditable()` is false there and
  a stored value is ignored. Downloads itself is always writable through the
  `com.apple.security.files.downloads.read-write` entitlement.
- **Phone / web** — no card.

**Path traps.**

- macOS: `getDownloadsDirectory()` in the sandbox is the container's
  `~/Library/Containers/<bundle>/Data/Downloads`, a link to the real
  `~/Downloads`. Writes work either way; `resolveSymbolicLinks()` (macOS only —
  on Windows it can turn a mapped drive into a UNC path) keeps the Containers
  path out of the toast and the card.
- Linux: `xdg-user-dir DOWNLOAD` prints `$HOME` when no downloads folder is
  configured, and under the snap's strict confinement `HOME` is the snap's own
  data folder. Either is treated as "no downloads folder" (the dialog), as is a
  result under `SNAP_USER_DATA` / `SNAP_USER_COMMON`.

**The Share gate.** On Windows and Linux the package's Share is the same temp
copy, so every `PdfPreview` passes `allowSharing: … && !pdfShareOpensTempCopy()`
and the billing pane and client statement add a **Download** button on desktop
(hidden while the render is stale, like Print and Share). The billing pane draws
its own toolbar (`useActions: false`), so its Share is `sharePdfBytes`
(`save_bytes.dart`, the one other caller of `pdfShare`) behind the same
`!pdfShareOpensTempCopy()` gate, and its Print is `Printing.layoutPdf`; each
also needs `Printing.info()` to say the platform can. macOS keeps Share —
there it is a real share picker. Both platform predicates check `Env.isDesktop`
first: on web `defaultTargetPlatform` is the browser's OS, and Share is the
web's download. Logged in `docs/upstream-workarounds.md` #15.

**What pins it.**

- `test/lint/desktop_downloads_test.dart` — no `Printing.sharePdf` outside
  `save_bytes.dart`; every `PdfPreview(` passes the gate.
- `test/ui/core/utils/save_download_test.dart` — folders, ` (1)`, the missing
  folder, the platform predicates (plain `test()`: file IO inside
  `testWidgets`' fake-async zone can hang).
- `test/ui/core/utils/save_bytes_test.dart` — the toast, the fallbacks, mobile
  unchanged.
- `test/ui/features/settings/widgets/downloads_folder_section_test.dart`,
  `test/ui/features/billing_shared/billing_doc_pdf_view_test.dart`.

## A billing document is saved under the name the server gave it, and the app's own name is only the fallback

The server names a document's file in every place the client gets it — the email
attachment, the client portal, the admin download route — as `Invoice_0042.pdf`
(`BaseModel::numberFormatter()`; the type is in the contact's language on the
invoice, quote and credit routes, which set the contact's locale first, and in the
request's on the purchase-order and delivery-note routes), and by the company's
file-name pattern once the server supports one (invoiceninja discussion #12610).
The app used to build its own `invoice_0042.pdf` instead, so the same document had
two names depending on where it came from.

**How the name travels.** `ApiClient.getRaw(keepServerFileName: true)` parses the
response's `Content-Disposition` (`fileNameFromContentDisposition`,
`lib/utils/file_names.dart`) and remembers it for the returned bytes in an
`Expando` (`rememberServerFileName` / `serverFileNameOf`). No signature between
the API and the screen changes: the name rides on the `Uint8List` itself, and a
copy of the bytes (`Uint8List.fromList`, `sublist`) carries no name, which falls
back safely to the caller's. Three routes ask to keep it — the stored render
(`fetchStoredPdf`), the delivery note and the e-purchase-order XML. A saved
version (History) deliberately does not: its caller suffixes the version's date
and time, so two versions of one document cannot save over each other.
`live_preview` (`preview.pdf`) and `bulk_print` (`print.pdf`) are `postRaw` and
never named; the two generic names are refused by `rememberServerFileName` too.

**Who reads it.** `BillingDocPdfView` (Print, Share, Download, `PdfPreview`), the
five row actions' Download / Print, the e-PO XML save, and the list screens' bulk
Download of one document (`downloadPdf(preferServerName:)`, because that name is
bound before the bytes arrive). Each asks with the extension it expects
(`serverFileNameOf(bytes, extension: 'pdf')`), which is appended if the name lacks
it. Everything else keeps its own name.

**Never for a document with no number.** The server names one
`class_basename($this)_<Str::random(5)>` — `Invoice_k3J9a.pdf`, a new name on every
fetch — so every reader skips the server name when the number is empty
(`counter_number_applied = when_sent` makes that an ordinary saved draft).

**The fallback** — a `live_preview` after an unsynced edit or a design override, a
draft on the edit screen, a recurring invoice (the server has no stored route for
it), a document with no number, an old server — is the server's default shape,
`billingDocFileBase`: the type in the app's language, `_`, the number, whitespace
as `_` (`Purchase_Order_0042`; a delivery note `Delivery_Note_Invoice_0042`; no
number `Invoice_preview` in the pane, `Invoice_<id>` from a row action). It is
close to the server's, not identical: the server also drops characters such as `/`
and transliterates to ASCII (`Str::ascii`), where the app turns `/` into `-` and
keeps the script.

**A server name is sanitized by `sanitizeServerFileName`, not `sanitizeFileName`.**
The latter collapses separator runs to tidy names the app assembles; on
`Acme Ltd - Invoice - 0042.pdf` it would produce `Acme Ltd-Invoice-0042`, a third
name for the document. The server-name sanitizer removes only what a platform
refuses: illegal characters, a leading dot or space, a trailing one only where
nothing follows it (`Invoice_5..pdf` is a legal name), bidi controls
(they can disguise an extension), a base past 96 UTF-8 bytes, a Win32 device name.

**Why a header is allowed under "the UI reads only Drift".** The PDF bytes are
online-only and never Drift state; the name is metadata of that same response,
used at the moment of saving, sharing or printing.

Tests: `test/utils/file_names_test.dart` (the header shapes Symfony writes —
quoted names with spaces and `;`, lower-case `utf-8''`, a bad `%FF` — and the
server-name sanitizer), `test/data/services/api_client_raw_file_name_test.dart`,
`test/ui/core/utils/save_bytes_test.dart`,
`test/ui/features/billing_shared/billing_doc_pdf_view_test.dart`,
`test/ui/features/billing_shared/billing_doc_file_name_test.dart`.

## A file name pattern is the email-template field with a file name scope, and its tab appears only once the server carries the keys

Settings → Generated Numbers → **File Names** edits `invoice_filename_pattern`,
`quote_filename_pattern`, `credit_filename_pattern`,
`purchase_order_filename_pattern` and `filename_slug` (server PR
invoiceninja/invoiceninja#13474, discussion #12610).

**When it shows.** `fileNamePatternsSupported` (`lib/domain/file_name_pattern.dart`):
the company's raw settings carry `invoice_filename_pattern`. The server's
`CompanySettingsSaver` rebuilds settings from `CompanySettings::defaults()` plus
the input on every company save, so a server with the feature has the keys after
the company's next settings save, and a server without it never does. No version
check: hosted reports a version that lags, and `ServerFeatures.supports` is
always true there. The settings search gates the fields on the same fact
(`SettingsSearchScope.supportsFileNamePatterns`).

**The field is the email-template one.** Each pattern is an
`OverridableTextField(templateVariables:)` with a file name
`TemplateVariableScope` (`invoiceFileName` … `purchaseOrderFileName`): chips at
rest, Insert variable, the override box. The variables are the HtmlEngine names
the server's `FileNamePattern` substitutes — the client ones for invoices,
quotes and credits, the vendor ones for purchase orders — held as each scope's
own groups, not in `_kEngines` (the PHP engine oracle cannot see one class's two
branches). Two things differ from an email field:

- **Tokens are split by the longest known variable** (`findTemplateVariables(text, scope)`),
  as the server's `strtr` reads them: `$date_$client.name_$number` is three
  variables, where the email grammar reads `$date_` as one unknown token.
- **No space is added after an inserted variable** (`_needsSpaceBefore`): it
  would end up in the file name.

**The rules.** A pattern must contain `$number` (the server ignores one without
it): the field shows the error once it is left, and a company-scope save of a
shown field is blocked (`GeneratedNumbersViewModel.preSaveError`; at group /
client scope it warns only, like the number patterns). The purchase order field
is company only (vendors have no client or group settings), so at those scopes a
purchase-order-only company has no tab. Blank is the server's default name,
shown as its example (`Invoice_0042.pdf`); Presets → Default writes it, and is
not offered at group / client scope, where blank means inherit. The switch's
subtitle says when there is nothing for it to change: the server simplifies only
custom names.

**The example is a port, not the name.** The "e.g." line under each field and
the switch's subtitle come from `fileNameExample` over sample values (only that document's variables), mirroring the server's resolver
and pinned by the server test's own expectations
(`test/domain/file_name_pattern_test.dart`). It is close, not identical: Latin
accents fold to plain letters, where the server folds by the client's language
(ü → ue in German), and other scripts (Cyrillic, Greek…) are dropped where the
server transliterates them — so a type label with no Latin letters shows in
English. A real download takes the server's name (the section above).

**A tab can appear while the page is open.** The first company save on an
upgraded server brings the keys in through the save echo, so the tab list grows
under a mounted shell; `CascadeTabbedSettingsShell.didUpdateWidget` replaces
the `TabController` (its length is fixed) and keeps the user on their tab.
