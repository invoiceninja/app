# Where a record's documents are attached

Companion to CLAUDE.md § Detail screens. The main file carries the rule; this doc carries why, how the files reach the server, and where each screen puts the card.

## A new record's edit screen attaches documents itself, uploaded on Save

A saved record's files are uploaded on its record screen's Documents tab (`buildStandardDocumentsTab` → `EntityDocumentsTab`). A record that was never saved has no record screen, so New Invoice / New Quote had no Documents anywhere, and users coming from admin-portal (whose invoice edit screen had a Documents tab) concluded attachments had been removed (support question, 2026-11).

So every document-bearing entity's create form takes files, the way New Expense has since invoiceninja/flutter#173: pick, drop, or (on a phone) photograph them on the form, and Save uploads them as the new record's documents. It works offline.

**How the files reach the server** — all of it in `GenericEditViewModel`, switched on by overriding `documentUploadRepository` (a `PendingUploadsRepository`):

- The form's list (`documents`) is the truth for every create attempt. Each Save snapshots it before `performSave`, then — once the subclass has queued the create and called `rememberCreateTempId` — queues one `documentUpload` per file under the record's `tmp_` id (`replaceUnsentDocumentUploads`, which first drops whatever an earlier attempt left unsent). The outbox holds an upload behind its record's create and rewrites the id when the create lands.
- A rejected save keeps the list; the next attempt queues it again. A successful (or optimistic) one clears it.
- A file added while a save is out (the 30 s online wait) follows that attempt's record when its create row stands, and otherwise stays for the next attempt (`_settleDocuments`).
- An edit form re-sending a failed create holds no files: it moves the earlier attempt's uploads behind the new create (`requeueUnsentDocumentUploads`).
- A file picked with the camera is an app-owned copy in `shared_intake/`; the form hands it back (`discardDocumentFiles` → `SharedIntakeFiles.delete`, wired by `EntityEditScreenScaffold`) on remove, Discard, or leaving unsaved — never mid-save.
- Files are unsaved content: a form holding any is dirty, even right after Discard.

Subclasses keep their own `performSave` exactly as before; the base does the uploads around it. New Expense adds only receipt reading on top (`onDocumentsAdded` / `onDocumentRemoved`, the `receipt:` slot) and its share-sheet target.

**Where the card goes** (`FormDocumentsCard` / `FormDocumentsPanel`, `lib/ui/core/edit/create_form_documents.dart`), gated on `vm.showsDocuments` — a new record of an entity that takes documents, or a saved one (its own documents — the last section below):

- **Billing documents** (invoice, quote, credit, recurring invoice, purchase order): a `Documents` tab after Settings in the narrow strip (`_Tab.documents`, `billing_doc_edit_layout.dart`) and a `Documents` sub-tab after Settings in the desktop notes card. Both read one gate, so they agree.
- **Expense**: first in the sidebar on wide, straight after Identity on narrow, so a shared receipt is in view at once.
- **Client, vendor, product, project, task, payment, recurring expense**: after the notes card (product: first in the side column, before custom fields; task: after the identity card on wide, at the end on narrow). The layout owns the gap — the card never hides itself.

**The plan gate decides what the card says, never whether it is there.** On a hosted plan without attachments (`AuthSession.canAttachDocuments` false) the panel shows the Enterprise `PlanGateBanner` the record screen's tab shows; hiding the card would leave the user as lost as before. (New Expense used to hide it — "no upsell on every new expense" — and now follows the same rule.) The session is read defensively (try/catch → ungated), because many widget tests pump an edit layout over a fake `Services` whose unimplemented members throw.

A record screen whose create has not synced yet (a `tmp_` id) still says "Save the record to upload documents" on its Documents tab (`DocumentsSaveFirstNotice`).

Pinned by `test/ui/core/edit/create_form_documents_test.dart`, `test/ui/features/expenses/expense_edit_view_model_test.dart` (the retry, share and hand-back paths), `test/ui/features/expenses/expense_edit_documents_section_test.dart`, and `test/ui/features/billing_shared/edit/billing_doc_edit_layout_characterization_test.dart`.

## An existing record's edit form shows the record's own documents, acted on at once

**On an existing record, the form's Documents card (a tab on billing documents) is the record screen's Documents tab — upload, view, download, rename, public / private and delete, each through the outbox the moment it is made, never held for Save.** `FormDocumentsCard` / `FormDocumentsPanel` (`create_form_documents.dart`) pick the create panel or `SavedRecordDocumentsPanel`, which renders `entityDocumentsTabFor` (`build_standard_documents_tab.dart`) — the same builder as the record tab, so the two can't drift. Gate a layout on `vm.showsDocuments`. (invoiceninja/app#205: "documents only can be added after the task has been saved and closed" — the reporter asked for both ways to stay.)

Why not upload on Save, like a create form: the record already exists, its record tab acts at once, and v1 and React both upload at once from an existing record's edit screen. A file held for Save would be a second model for the same record, and lost on Discard. A line under the drop zone says files are attached right away (`documents_added_immediately`).

**The form follows the record's stored list and folds it into the draft and the baseline alike** (`GenericEditViewModel.watchSavedDocumentsLive`, `SavedDocumentsBinding`). Every entity's save writes the draft's `documents` back to its Drift row, so a draft still holding the list the form opened with would undo, locally, a file uploaded, renamed or deleted on the form — until the next server copy. Adopting into both sides keeps the form exactly as dirty as it was; a list that arrives while a save is out waits until it ends, or it would read as an edit made during the save (`editedDuringSave`). Each edit view model supplies the binding in a few lines (`repo.watch(...).map((r) => r?.documents)` and `copyWith(documents:)`).

The subscription starts when the panel mounts, and that is enough: the list can change from the form only through the panel. It is not read again at Save — opening and closing a Drift stream there leaves Drift's close timer pending (widget tests fail on it), and `peek` is a first-frame seed, not a source of truth. A record whose create hasn't synced (`tmp_`) still gets "Save the record to upload documents", as on its record screen.

Pinned by `test/ui/core/edit/generic_edit_view_model_saved_documents_test.dart`.
