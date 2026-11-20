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

## An edit typed while the save was out keeps the form open and dirty

Online, `save()` waits up to 30 s for the server. An edit typed meanwhile was
not sent; latched clean, the reload threw it away and the guard let the user
leave without it. `GenericEditViewModel` counts `updateDraft` calls, and a save
of an existing record that saw one after `performSave` leaves the form dirty
(`editedDuringSave`); the scaffold then keeps that view model instead of
reloading. A new record still latches clean: its form moves to the record's
edit route either way. Test: `generic_edit_view_model_edited_during_save_test.dart`.

## The reload keeps the scroll position

The remount would put a long form back at the top. Just before it, the
scaffold reads the pixels of every vertical scroll view under the form (a
`GlobalKey` per generation) and, after the next frame, jumps the new ones back
— only when the form has the same number of them, matched in tree order, so an
offset never lands on a different list.

## A new record moves to its own edit route, under the real id once its create landed

Staying on `/x/new` would make a second record on the next Save (`isCreate`
stays true), and a restart would restore a blank form. The scaffold resolves
the saved `tmp_` id through `id_remap` (`resolveAnyType`): the real id after an
online save, which waited for the create; the `tmp_` id offline or after a
timeout — an editor on it follows the swap the way a record screen does, and
shows `SyncFirstBanner`. Leaving `/x/new` replaces its history entry
(`isTransientCreateRoute`), and the edit route sits under the record's, so
Back and ✕ land on the record. A new record's Documents tab goes with the
create form: a saved record's files are on its record screen.

## A save rebound from a tmp_ id keeps the number the create got

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

An update queued *before* its record's create lands (offline: create, stay,
Save again) carries the blank number in its payload. When the create lands,
`OutboxDao.rewriteTempIdInPayloads` — which rewrites the queued rows' `tmp_` id
— also drops a blank `number` from such an update, so the server keeps the
number the create got; a number the user typed is sent as is.

## Save is disabled on an unchanged existing record while the editor stays open

With Edit Record, Save on an existing record with nothing to send (no change,
no failed or held save, not a re-create) is disabled — the sign that the save
landed — and ⌘S / Enter on it do nothing (`disableSaveWhenClean`). A focused
text input counts as a possible change: a date, time or notes field commits
only on blur or Enter, so the Save button listens to focus changes and stays
enabled while one is focused; pressing it unfocuses, flushes, and saves only if
something changed — and, when nothing did, hands the focus back to the field.
With no text field focused, ⌘S on a settled record leaves the focus alone. The
scaffold listens to the controller, so a change in Device Settings reaches an
editor already open. SAVE-PARAM actions never need a change.

Tests: `test/ui/core/edit/entity_edit_screen_scaffold_after_saving_test.dart`,
`test/app/after_saving_controller_test.dart`,
`test/ui/core/list/go_after_entity_save_test.dart`,
`test/data/repositories/number_kept_on_rebind_test.dart`,
`test/ui/core/edit/generic_edit_view_model_edited_during_save_test.dart`,
`test/ui/features/billing_shared/edit/reload_skips_one_shot_extras_test.dart`,
`test/ui/features/billing_shared/edit/open_line_item_test.dart`.
