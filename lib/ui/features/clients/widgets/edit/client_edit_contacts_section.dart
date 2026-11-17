import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/contact.dart';
import 'package:admin/data/services/device_contacts_service.dart';
import 'package:admin/domain/contact_email_mode.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';
import 'package:admin/ui/core/edit/entity_custom_fields_section.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/contact_edit_rows.dart';
import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:admin/ui/core/widgets/labeled_switch_group.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/billing_shared/detail/signed_document_pill.dart';

/// "Contacts" card on the client edit screen. Renders every contact as a row
/// that opens one at a time (`ContactEditRows`), the open row carrying its
/// First/Last/Email/Phone block, its email choice (To / CC / None) and the
/// Make primary / Remove buttons (Remove only with 2+ contacts, undone from
/// its toast).
///
/// "+ Add contact" sits at the bottom of the card.
///
/// Each `_ContactEditor` is keyed by the contact's id (or list index when
/// the id is empty — fresh contacts haven't been allocated server-side yet)
/// so adding/removing siblings doesn't recycle a `TextEditingController`
/// onto a different contact's data.
class ClientEditContactsSection extends StatelessWidget {
  const ClientEditContactsSection({super.key, required this.vm});

  final ClientEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final services = context.read<Services>();
    // Drives the per-contact custom fields (gated by the company's
    // `contact1..4` labels), same source the Details card uses for `client*`.
    final companyStream = services.company.watchCompany(vm.companyId);
    final formatter = services.formatterIfReady(vm.companyId);
    final contacts = vm.draft.contacts;
    return DashboardCardShell(
      title: context.tr('contacts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contacts.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: InSpacing.md(context)),
              child: Text(
                context.tr('no_contacts_yet'),
                style: TextStyle(color: tokens.ink3),
              ),
            )
          else
            _ContactList(
              vm: vm,
              companyStream: companyStream,
              formatter: formatter,
            ),
          SizedBox(height: InSpacing.md(context)),
          FilledButton.tonalIcon(
            onPressed: vm.addContact,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: Text(context.tr('add_contact')),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accentSoft,
              foregroundColor: tokens.accentInk,
            ),
          ),
          // Native address-book import (iOS). Hidden on web / non-iOS where the
          // device contacts service reports unavailable.
          if (services.deviceContacts.isAvailable) ...[
            const SizedBox(height: InSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _importFromDevice(context),
              icon: const Icon(Icons.perm_contact_calendar_outlined, size: 18),
              label: Text(context.tr('add_from_contacts')),
            ),
          ],
        ],
      ),
    );
  }

  /// Launch the OS contact picker, merge the chosen contact into the draft
  /// (non-destructively), and report the outcome. The whole import is one draft
  /// mutation, so the toast's Undo restores everything at once.
  Future<void> _importFromDevice(BuildContext context) async {
    final services = context.read<Services>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final DeviceContactImport? picked;
    try {
      picked = await services.deviceContacts.pickContact();
    } catch (e) {
      if (context.mounted) {
        Notify.error(
          context,
          context.tr('add_from_contacts'),
          error: e,
          messenger: messenger,
        );
      }
      return;
    }
    if (picked == null) return; // user cancelled
    if (!context.mounted) return;

    final before = vm.draft;
    final countryId = resolveCountryId(
      services.statics.countries.values,
      iso2: picked.countryIso,
      name: picked.countryName,
    );
    final result = vm.applyImportedContact(picked, countryId: countryId);

    if (result.changedNothing) {
      Notify.warning(
        context,
        context.tr('no_contact_details_found'),
        messenger: messenger,
      );
      return;
    }

    final summary = _importSummary(context, result);
    final undo = NotifyAction(
      context.tr('undo'),
      () => vm.restoreDraft(before),
    );

    if (result.contactWasDuplicate) {
      // The picked person already exists, so don't claim we imported them.
      // Client fields may still have filled — offer Undo + a summary then.
      Notify.info(
        context,
        context.tr('already_a_contact', {'name': picked.displayLabel}),
        detail: result.appliedChanges ? summary : null,
        action: result.appliedChanges ? undo : null,
        messenger: messenger,
      );
      return;
    }

    // Not a duplicate → a person and/or client fields were imported.
    final title = picked.displayLabel.isNotEmpty
        ? context.tr('imported_contact', {'name': picked.displayLabel})
        : context.tr('add_from_contacts');
    Notify.success(
      context,
      title,
      detail: summary,
      action: undo,
      messenger: messenger,
    );
  }

  /// "Name · Address · Contact" — the fields the import filled, for the toast
  /// detail line. Tokens map to existing localization keys.
  String _importSummary(BuildContext context, ContactImportResult result) {
    final parts = <String>[
      for (final field in result.filledClientFields) context.tr(field),
      if (result.contactAdded) context.tr('contact'),
    ];
    return parts.join('  ·  ');
  }
}

/// The contacts as rows that open one at a time (`ContactEditRows`): this
/// supplies each contact's summary and the open row's fields.
class _ContactList extends StatelessWidget {
  const _ContactList({
    required this.vm,
    required this.companyStream,
    required this.formatter,
  });

  final ClientEditViewModel vm;
  final Stream<Company?> companyStream;
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    final contacts = vm.draft.contacts;
    return ContactEditRows(
      contacts: [
        for (final c in contacts)
          ContactRowData(
            id: c.id,
            firstName: c.firstName,
            lastName: c.lastName,
            email: c.email,
            phone: c.phone,
            isPrimary: c.isPrimary,
            isBlank: c.isBlank,
          ),
      ],
      onMakePrimary: vm.setContactPrimary,
      onDelete: (i) {
        final removed = vm.removeContact(i);
        if (removed == null) return null;
        return () => vm.restoreContact(i, removed);
      },
      fieldsBuilder: (context, i) => _fields(context, contacts[i], i),
    );
  }

  List<Widget> _fields(BuildContext context, Contact c, int i) {
    return [
      // Side by side wherever the card has room — the 360 px sidebar card
      // included — stacked below that.
      FormFieldPair(
        minPairWidth: kSidebarPairWidth,
        left: EntityEditField(
          label: context.tr('first_name'),
          initial: c.firstName,
          onChanged: (v) => vm.setContactFirstNameAt(i, v),
          textCapitalization: TextCapitalization.words,
        ),
        right: EntityEditField(
          label: context.tr('last_name'),
          initial: c.lastName,
          onChanged: (v) => vm.setContactLastNameAt(i, v),
          textCapitalization: TextCapitalization.words,
        ),
      ),
      EntityEditField(
        label: context.tr('email'),
        initial: c.email,
        onChanged: (v) => vm.setContactEmailAt(i, v),
        keyboardType: TextInputType.emailAddress,
      ),
      EntityEditField(
        label: context.tr('phone'),
        initial: c.phone,
        onChanged: (v) => vm.setContactPhoneAt(i, v),
        keyboardType: TextInputType.phone,
      ),
      // Portal password is only meaningful when the company enables portal
      // passwords — React + admin-portal both gate this field on
      // `enable_client_portal_password`. Hidden until the company resolves,
      // so it never flickers in for a workspace that has the feature off.
      // (An already-set password is preserved on save regardless — it stays
      // in the draft and `Contact.toApiJson` still emits it.)
      StreamBuilder<Company?>(
        stream: companyStream,
        builder: (context, snapshot) {
          final portalPasswordEnabled =
              snapshot.data?.settings.enableClientPortalPassword ?? false;
          if (!portalPasswordEnabled) return const SizedBox.shrink();
          return EntityEditField(
            label: context.tr('password'),
            initial: c.password,
            onChanged: (v) => vm.setContactPasswordAt(i, v),
            // The contact's portal credential, not the signed-in user's:
            // obscured behind a reveal toggle, and deliberately NO
            // autofillHints — the OS must not offer the admin's own saved
            // password here, nor offer to save this one as theirs.
            obscureText: true,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
          );
        },
      ),
      // Per-contact custom fields (contact1..4). Renders inline, gated by
      // the company's configured labels — invisible when none are set.
      EntityCustomFieldsSection(
        keyPrefix: 'contact',
        companyStream: companyStream,
        formatter: formatter,
        wrapInCard: false,
        values: [
          c.customValue1,
          c.customValue2,
          c.customValue3,
          c.customValue4,
        ],
        onChanged: [
          (v) => vm.setContactCustomValue1At(i, v),
          (v) => vm.setContactCustomValue2At(i, v),
          (v) => vm.setContactCustomValue3At(i, v),
          (v) => vm.setContactCustomValue4At(i, v),
        ],
      ),
      // "Add to invoices" and "CC only" as the one choice they are: To, CC
      // or no email. The server keeps the primary out of CC and a CC-only
      // contact out of To (`ContactEmailMode`).
      ContactEmailModeField(
        value: contactEmailModeOf(
          sendEmail: c.sendEmail,
          ccOnly: c.ccOnly,
          isPrimary: c.isPrimary,
        ),
        isPrimary: c.isPrimary,
        onChanged: (mode) => vm.setContactEmailModeAt(i, mode),
      ),
      StreamBuilder<Company?>(
        stream: companyStream,
        builder: (context, snapshot) {
          // "Authorized to sign" means DocuNinja asks this contact to sign,
          // so it shows only while DocuNinja is on for the company
          // (`enable_modules`), as React's contact form does. The value is
          // kept on save regardless (`Contact.toApiJson` still emits `can_sign`).
          // ...and on a plan that still runs DocuNinja.
          final eSignEnabled = docuNinjaSigningActive(context, snapshot.data);
          if (!eSignEnabled) return const SizedBox.shrink();
          return LabeledSwitchGroup(
            items: [
              LabeledSwitchItem(
                label: context.tr('authorized_to_sign'),
                value: c.canSign,
                onChanged: (v) => vm.setContactCanSignAt(i, v),
              ),
            ],
          );
        },
      ),
    ];
  }
}
