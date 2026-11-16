import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/vendor_contact.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/entity_custom_fields_section.dart';
import 'package:admin/ui/core/edit/entity_edit_field.dart';
import 'package:admin/ui/core/widgets/contact_edit_rows.dart';
import 'package:admin/ui/core/widgets/labeled_switch_group.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/vendors/view_models/vendor_edit_view_model.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/features/billing_shared/detail/signed_document_pill.dart';

/// "Contacts" card on the vendor edit screen: the contacts as rows that open
/// one at a time, the same list the client edit screen draws
/// (`ContactEditRows`), over `vendor.contacts` (`VendorContact`).
class VendorEditContactsSection extends StatelessWidget {
  const VendorEditContactsSection({super.key, required this.vm});

  final VendorEditViewModel vm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final services = context.read<Services>();
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
        ],
      ),
    );
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

  final VendorEditViewModel vm;
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
      onDelete: vm.removeContact,
      fieldsBuilder: (context, i) => _fields(context, contacts[i], i),
    );
  }

  List<Widget> _fields(BuildContext context, VendorContact c, int i) {
    return [
      EntityEditField(
        label: context.tr('first_name'),
        initial: c.firstName,
        onChanged: (v) => vm.setContactFirstNameAt(i, v),
        textCapitalization: TextCapitalization.words,
      ),
      EntityEditField(
        label: context.tr('last_name'),
        initial: c.lastName,
        onChanged: (v) => vm.setContactLastNameAt(i, v),
        textCapitalization: TextCapitalization.words,
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
      // Portal password. `fromApi` blanks the server's `**********` mask, so
      // an empty field means "unchanged" and is never sent (see kMaskedPassword).
      EntityEditField(
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
      ),
      // Per-contact custom fields (vendor_contact1..4). Renders inline,
      // gated by the company's configured labels — invisible when none set.
      EntityCustomFieldsSection(
        keyPrefix: 'vendor_contact',
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
      StreamBuilder<Company?>(
        stream: companyStream,
        builder: (context, snapshot) {
          // "Authorized to sign" means DocuNinja asks this contact to sign,
          // so it shows only while DocuNinja is on for the company
          // (`enable_modules`), as React's contact form does. The value is
          // kept on save regardless (`VendorContact.toApiJson` still emits `can_sign`).
          // ...and on a plan that still runs DocuNinja.
          final eSignEnabled = docuNinjaSigningActive(context, snapshot.data);
          return LabeledSwitchGroup(
            items: [
              LabeledSwitchItem(
                label: context.tr('add_to_invoices'),
                value: c.sendEmail,
                // CC-only and send_email are mutually exclusive; greyed out
                // (onChanged: null) while CC-only is on.
                onChanged: c.ccOnly
                    ? null
                    : (v) => vm.setContactSendEmailAt(i, v),
              ),
              LabeledSwitchItem(
                label: context.tr('cc_only'),
                value: c.ccOnly,
                onChanged: (v) => vm.setContactCcOnlyAt(i, v),
              ),
              if (eSignEnabled)
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
