# Document thumbnails

Companion to CLAUDE.md § Detail screens. Why a document list draws photos and PDFs as thumbnails on the device, what limits that, and where the switch is.

## A thumbnail is drawn on the device, kept in memory only, and capped

**`DocumentThumbnail` (`lib/ui/core/widgets/document_thumbnail.dart`) shows a photo, or a PDF's first page, in place of the type icon on a record's Documents tab, a record's edit form and the company Documents list; the bytes come from `DocumentsApi.download` and are scaled to at most `kDocumentThumbnailPixels` before they are kept.** invoiceninja/app#206 asked for them to recognise which file is which before renaming.

- **The server makes none.** `UploadFile::generatePreview` is commented out, so every `preview` it sends is empty; v1's grid drew that field and now shows nothing. React fetches the file too, png / jpg only, behind its opt-in `show_document_preview`.
- **Never `Image.network(doc.url)`** — the url is a token-gated API route (`docs/document-urls.md`).
- **Memory only.** The database is encrypted; a folder of scaled-down receipts beside it would not be. A thumbnail therefore costs one download per file per session.
- **The limits, each pinned in `document_thumbnail_test.dart`:** only a type the app can draw (`previewKindForType`: png, jpg, gif, webp, bmp, pdf), at most `maxBytes` (12 MB); two downloads at a time, the rest queued; the 150 most recent kept; a failure not asked again for a minute, so a list scrolled offline makes no request storm; keyed by `id|hash`, so a rename does not fetch again.
- **One cache per account** (`DocumentThumbnailCache.of`, an `Expando` on `Services`): it empties when the session ends or another account signs in.
- **Never a spinner.** The type icon shows until the picture arrives and whenever it can't be drawn.

Tapping the thumbnail opens the file, like View.

## "Show Document Preview" is a device preference, on by default

**`DevicePrefKeys.documentThumbnails` (`DocumentThumbnailsController`, Device Settings → Lists and dashboard), read with `watchDocumentThumbnails(context)`; off means no download at all, not merely no picture.** Per device because the cost is this device's connection; on by default, unlike React, because the cache keeps it to one capped download per file. The title reuses the server's own `show_document_preview` string.

## Renaming a file from its record

**A record's Documents tab and edit form offer Rename on each row, through `DocumentRepository.renameAttached`: it seeds the Documents table from the record's copy if the file isn't cached there, sends only `name` (never a cached `is_public`), and renames the record's own copy at once, so the tab shows it offline.** The dialog (`showRenameDocumentDialog`) shows the thumbnail, opens with the words before the extension selected, and allows dropping the extension — a download puts it back from the file's type (`documentFileName`). `docs/documents-list.md` § A change here is a change to the parent's copy too has the server side.
