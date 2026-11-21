# After saving: stay in the editor or go to the record

Companion to CLAUDE.md § Forms. The rule lives there; this doc carries what
Save does next on an entity edit screen, why, and the offline-first traps that
shaped it (invoiceninja/app#202).

## Save stays in the editor only where After Saving says so; an action's save goes to the record

"After Saving" is a device preference (`DevicePrefKeys.afterSaving`,
`AfterSavingController`, Device Settings → Forms): **Edit Record** keeps the
editor open after Save, **View Record** goes to the record. No stored value
means automatic: Edit Record on a tablet or a desktop, View Record on a phone
(`Breakpoints.isPhone`, read through `staysInEditorByDefault`, the pattern
"Hide empty panels" uses). Choosing the automatic answer stores nothing, so a
foldable keeps adapting until the user overrides it. Device scope: a sign-out
keeps it, like the theme.

The decision is `EntityEditScreenScaffold`'s, not each screen's. A screen
passes `basePath:` (the entity's route); the scaffold then:

| Save | After Saving = Edit Record | View Record |
|---|---|---|
| Plain Save (button, Enter, ⌘S) on an existing record | stays; the form reloads from the stored record | the record (`pop`, else `go('/x/:id')`) |
| Plain Save on a new record | `go('/x/<id>/edit')`, keeping `?view=full` | the record |
| A SAVE-PARAM action (Mark Sent, Mark Paid, Cancel, …) | the record | the record |
| An AFTER-SAVE action (Email, Clone, …) | the action's own navigation, as before | same |

Why an action's save leaves: it finishes the job, as in v1, where a save
carrying an action went to the view; and a status change can lock the record
(`lock_invoices`), so reopening its editor would only show the lock dialog.
`EntityEditScaffold.onSavedByAction` carries that path; `onSaved` the plain
one.

What the references do:

- **admin-portal (v1)**: `prefState.editAfterSaving`, default true, shown on
  desktop only ("After Saving: Edit Record / View Record",
  `lib/ui/settings/device_settings.dart`). On desktop, for the full-width
  editors (invoice, quote, credit, recurring invoice, purchase order, task,
  expense, recurring expense) a save reopened the editor on the saved record
  (`invoice_edit_vm.dart` — `viewEntity` then `editEntity`); on mobile it
  always went to the view.
- **React**: an edit stays on the page and refetches the record
  (`useInvoiceSave.ts`); a create navigates to the new record's edit page
  (`useHandleCreate.ts`, tasks, products, expenses, projects, payments).

`onSaved:` still exists for an editor that is not on an entity route of its
own (the company gateway under Settings) and for tests; passing it opts the
screen out of all of this.

## Staying on an existing record reloads the form from the stored copy, never keeps the draft it saved

`GenericEditViewModel._original` is final and never rebased, and a save only
latches the form clean (`_savedClean`). Kept open as it was, the form would
hold a draft that never saw the server's reply — totals, the assigned number,
invitation keys, line ids — and the next Save would send it back. A change
reverted after the save would also read as dirty, against the stale original.

So after a plain Save the scaffold re-runs `fetchExisting` and `reloadVm`
(`buildVm` where a screen has none) and swaps the new view model in
(`_reloadAfterSave`). An online save's row is
deleted only after its reply is applied, so the stored record is the server's
copy by the time `save()` returns; offline or after the wait timed out it is
the local copy, which is the draft. The form below remounts on the new view
model (`_generation` keys it), so no field keeps a value seeded from the old
one; the old view model is disposed after that frame. What the form shows
about itself — the selected tab — rides across in
`GenericEditViewModel.formUiState`, which the scaffold copies into the new
view model.

`canKeepEditing` is asked first: an invoice that is now locked, or an invoiced
task, goes to the record instead, with no dialog. A record that can no longer
be read back goes there too.

## A reload never re-applies an edit route's one-shot extras

Three edit routes carry a one-shot `extra` that `buildVm` applies to the form
it opens: invoice "Add to invoice" (`cloneFrom`, the invoice with the task's or
expense's line appended, for review), the record screen's Contacts "+ Add"
(`addContact`, a blank contact on a client or vendor) and a tapped line
(`openLineItem`, the billing documents). The record a Save just wrote already
holds what the extra asked for, so applying it again was a bug each time: the
reloaded invoice showed the stale handoff draft, dirty, and the next Save
reverted the user's later edits; every Save added another blank contact; the
line's dialog reopened and the narrow strip jumped to Items after every Save.

So a screen with such an extra passes `reloadVm` — `buildVm` without it
(invoice, client, vendor) — and `BillingDocEditLayout` consumes
`openLineItem` once per form through `formUiState`
(`billing_doc_edit.opened_line`), which the reload carries across; the
reloaded strip opens on Details, like any strip mounted after the request was
served. Tests: `reload_skips_one_shot_extras_test.dart`,
`open_line_item_test.dart`.

## An edit typed while the save was out is kept

Online, `save()` waits up to 30 s for the server. An edit typed meanwhile was
not sent; latched clean, the reload threw it away and the guard let the user
leave without it. `save()` keeps the draft it sent and compares it, by value
(freezed `==`), with the draft at the end (`editedDuringSave`) — an edit typed
and undone is no edit. The draft is taken before the local write, which awaits
too, so a keystroke during it counts. And the scaffold looks once more right
before it swaps the reloaded view model in: an edit typed while the record was
read back keeps the form as it is, dirty, rather than going under the reload.

- **An existing record**: the form stays dirty with the edit, and the scaffold
  keeps that view model instead of reloading.
- **A new record**: its form still latches clean (it leaves `/x/new` either
  way, and the route's exit guard must not ask), and the edit rides to the
  record's editor. The scaffold parks the draft the save sent
  (`lastSentDraft`) beside the form's draft, by company and
  `<basePath>/<id>`; the editor that opens there takes it and adopts
  (`adoptUnsavedDraft`), dirty, the screen's `carryEdit` of the two over the
  stored record. An entry is one-shot — taken, or dropped when the record
  can't be read — and stale after a minute. A screen without `carryEdit`
  loses the edit, as before.

**Only what changed is carried.** The first version laid the whole create
form's draft over the record the server had just made, and the next Save
sent what that form never had: client and vendor contacts without ids (the
server's `ClientContactRepository::save` deletes and recreates them, so ids
and keys churn and queued references dangle), invitations without keys
(`BaseRepository::save` soft-deletes and recreates them, losing the keys and
the DocuNinja signing state), and blanks where the server had filled a value
(a due date from the payment terms). `carryChangedFields` (`carry_edit.dart`)
compares the sent and the edited draft on the wire (`toApiJson`) and lays
only the changed top-level keys over the stored record's. The record is
rebuilt from that map (`fromApi`), and each entity's function in
`carry_edit_entities.dart` puts back what the wire does not carry — the id,
local state, timestamps, documents, as its repository's decode overlays them
— and every list the edit left alone, as the stored objects themselves. An
edit that changed nothing on the wire carries nothing.

A list the edit did change keeps the server's identity the way the server
matches it, never by a place where an item may have been added or removed:

- **Invitations** by contact (`keepStoredInvitations`): the server finds an
  invitation by its key alone (`getInvitation`), so a key handed to the wrong
  contact would be that contact's link. An invitation for a contact the
  stored record already invites is that stored invitation (key, signing
  state, history); one newly ticked carries no key, and the server makes it;
  one unticked is gone.
- **Contacts** by place only while their number is unchanged
  (`CarriedList.byPosition`): the server updates a contact by `id` and
  deletes the stored ones a save leaves out (`ClientContactRepository::save`).
  A contact added or removed while the create was out can't be matched
  safely, so the stored contacts stay and the editor says so once ("Contacts
  changed while saving weren't kept. Add them again.").
- **Line items** carry no identity: the server drops a line's `id` / `_id`
  (`CleanLineItems::cleanItem`) and matches nothing by it, so the edited lines
  go as they are.

Tests: `generic_edit_view_model_edited_during_save_test.dart`, `carry_edit_test.dart` and the
scaffold cases in `entity_edit_screen_scaffold_after_saving_test.dart`.

## The reload keeps the scroll position

The remount would put a long form back at the top. Just before it, the
scaffold records the form's own scrolled vertical scroll views (a `GlobalKey`
per generation) — the outermost ones, never one inside a text field, whose
offset could otherwise land on another field when a sibling comes or goes —
each keyed by its place in the tree — the widget type
and child index of each element on the way down. After the remount it jumps
the scroll view at the same path back. Matching by count or by order failed on
the wide billing documents: the PDF pane's spinner turns into a preview with
scroll views of its own a frame later, and a multi-line field brings one too.
An offset past the extent the content has so far waits up to ten frames for
late content (a stream, a fetch) before settling for the end.

## The PDF preview keeps its last render across the reload

The remount also took the preview's last good render with it, so it flashed
to a spinner after every Save. The billing layout keeps a `BillingDocPdfMemo`
in `formUiState`; `BillingDocPdfView` writes it on every good render (and
clears it when it drops its PDF), and a new view that finds bytes in it shows
them at once and refreshes quietly — the `contentRevision` path of
docs/pdf-preview-refresh.md, so a failed refresh keeps them, marked stale.

## A new record moves to its own edit route, under the real id once its create landed

Staying on `/x/new` would make a second record on the next Save (`isCreate`
stays true), and a restart would restore a blank form. The scaffold resolves
the saved `tmp_` id through `id_remap` (`resolveAnyType`): the real id after an
online save, which waited for the create; the `tmp_` id offline or after a
timeout. An editor on a `tmp_` id stays on that route when the create lands
— it does not reload onto the server's copy — and shows `SyncFirstBanner`; its
next Save is rebound to the real id by the repository, which then takes what
the server gave the record and the draft lacks (the next section). Leaving `/x/new` replaces its history entry
(`isTransientCreateRoute`), and the edit route sits under the record's, so
Back and ✕ land on the record. A new record's Documents tab goes with the
create form: a saved record's files are on its record screen.

## A save rebound from a tmp_ id keeps the number the create got, and the ids of its contacts and invitations

`toApiJson` always sends `number`. A form opened on a record before its create
landed holds the blank number the create was sent with; when that record is
then saved as an update, the server's `TrimStrings` /
`ConvertEmptyStringsToNull` middleware turns `""` into null, `fill()` stores it
(`BaseRepository::save`), and `ApplyNumber::run` sees a blank number and takes
the next one from the counter — so the number the create got is skipped
(server `app/Services/Invoice/ApplyNumber.php`, with
`counter_number_applied` = `when_saved`, the default; the demo company reads
`when_saved`). Read-only probe on 2026-11-20: the demo's
`/api/v1/companies` settings carry `counter_number_applied: when_saved`; the
write itself was not probed, so the skipped number is the server source's
answer, not a measured one.

The repositories' `save()` already rebinds a `tmp_` id whose create landed;
`BaseEntityRepository.numberKeptOnRebind` now also keeps the stored record's
number there when the draft's is blank (invoice, quote, credit, recurring
invoice, purchase order, task, expense, recurring expense, project, client,
vendor, payment). Only on a rebind: a blank number on a record the form opened
with a number is the user clearing it, which does ask the server for a new
one.

The same draft names its contacts without ids and its invitations without
keys. The server deletes and recreates contacts a save sends without ids
(`ClientContactRepository::save`), so the rebind also gives the draft's
contacts the stored ids — by place, and only while the lists are as long
(`idsByPosition`, `lib/domain/record_identity.dart`); a contact added or
removed meanwhile can't be matched, and that list goes as it is. Invitations
take the stored invitation for the same contact, key and signing state
(`invitationsByContact`): the key goes on the wire only with `can_sign`, which
the server applies with it (client and vendor, and the five billing
documents).

An update queued *before* its record's create lands (offline: create, stay,
Save again) carries the blank number in its payload. When the create lands,
`OutboxDao.rewriteTempIdInPayloads` — which rewrites the queued rows' `tmp_` id
— also drops a blank `number` from such an update, so the server keeps the
number the create got; a number the user typed is sent as is. Its contacts get
the ids from the create's reply, by place on the same rule
(`BaseEntityRepository.fillQueuedListIds`, from the client and vendor
`applyCreateResponse`). Its keyless invitations are left: the server soft-
deletes the invitations whose keys a save leaves out and then restores the
trashed one for the same contact (`BaseRepository::save`), so the key — and,
unless the request says otherwise, `can_sign` — survive.

## Save stays enabled, gives the focus back, and never creates twice

Save is enabled on an unchanged record too, as in React: a re-save makes the
server recalculate, and a click during a line-item cell's 250 ms commit is not
swallowed (a first version disabled it while the editor stayed open).

The save takes the focus away to commit the field the user was in; a Save
that keeps the editor open gives it back. The scaffold notes the focused node
when the save begins (`focusAtSaveOf`); on a form that stays, that node gets it
again, and on a reloaded one the focus node at the same place in the new tree
— the same path the scroll restore uses — a few frames given for it to build.

A new record's form, once its create succeeded, refuses another Save
(`save()` returns null): `onSaved` awaits a few reads before it navigates away,
and a Save in that window made the record twice.

Tests: `test/ui/core/edit/entity_edit_screen_scaffold_after_saving_test.dart`,
`test/app/after_saving_controller_test.dart`,
`test/ui/core/list/go_after_entity_save_test.dart`,
`test/data/repositories/number_kept_on_rebind_test.dart`,
`test/ui/core/edit/generic_edit_view_model_edited_during_save_test.dart`,
`test/ui/features/billing_shared/edit/reload_skips_one_shot_extras_test.dart`,
`test/ui/features/billing_shared/edit/open_line_item_test.dart`.
