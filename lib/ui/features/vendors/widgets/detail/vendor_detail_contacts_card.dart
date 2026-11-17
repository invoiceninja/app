import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/vendor_contact.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/portal_link_action.dart';
import 'package:admin/ui/core/detail/custom_field_detail_rows.dart';
import 'package:admin/ui/core/utils/mail_actions.dart';
import 'package:admin/ui/core/utils/phone_actions.dart';
import 'package:admin/ui/core/widgets/party_contact_row.dart';
import 'package:admin/ui/core/widgets/phone_number_value.dart';
import 'package:admin/ui/features/vendors/widgets/vendor_portal.dart';

/// "Contacts" card on the vendor record screen (`PartyContactsCard`): every
/// contact worth showing, the first three inline and the rest behind "Show N
/// more".
///
/// **No local time.** A vendor has no settings cascade of its own, so the
/// only timezone there is to show is the company's — the user's own clock,
/// which a contact row used to print beside every number as though it were
/// the vendor's.
///
/// Hides entirely when no contact has anything to show. `contacts` is never
/// empty in practice — the server keeps one all-blank contact on a vendor the
/// user never gave contact details to — so the question is
/// [VendorContactIdentity.isBlank] per row, not `contacts.isEmpty`
/// (invoiceninja/flutter#115).
///
/// "Show N more" expands **inline at every width**, and "Show less" puts it
/// back. The
/// client's card opens a sheet on a narrow layout instead; one path is enough
/// here, and in a stacked column there is nothing beside the card for a taller
/// one to push out of line.
///
/// No `LayoutBuilder` anywhere under this: the profile lays this card out in
/// an `IntrinsicHeight` row, and a `LayoutBuilder` cannot answer an intrinsic
/// size query.
class VendorDetailContactsCard extends StatefulWidget {
  const VendorDetailContactsCard({
    super.key,
    required this.contacts,
    required this.vendorId,
    this.company,
    this.countryId = '',
    this.onAdd,
  });

  /// The vendor's `country_id`: the country a contact's number with no `+`
  /// is read in for display. Empty reads it in the company's.
  final String countryId;

  /// Opens the vendor's editor on a new contact (`AddContactRequest`). Null
  /// hides "+ Add" — the user may not edit this vendor, or it is deleted.
  final VoidCallback? onAdd;

  final List<VendorContact> contacts;

  /// The vendor these contacts belong to — a call placed from a row here is
  /// logged against it (invoiceninja/flutter#120).
  final String vendorId;

  /// For contact custom-field labels; null draws none.
  final Company? company;

  /// Whether [build] renders at least one row — the profile gates its entry
  /// for this card on it.
  static bool hasContent(List<VendorContact> contacts, {Company? company}) =>
      visibleVendorContacts(contacts, company: company).isNotEmpty;

  @override
  State<VendorDetailContactsCard> createState() =>
      _VendorDetailContactsCardState();
}

/// The contacts worth rendering. A blank one has nothing to show but
/// `(no name)`, a Primary label, and portal buttons for a link the server mints
/// for it regardless — the portal stays reachable from
/// `VendorAction.vendorPortal`. A deleted one is not this vendor's contact any
/// more.
///
/// **A custom value the company has a label for is content.** The row prints
/// contact custom fields, so a contact whose only entry is one — a
/// "Department" with no name typed — has a line to show, and
/// `VendorContact.isBlank` (which deliberately leaves custom values out) would
/// hide it. Pass [company] to count them; without it the labels are unknown
/// and the narrower test applies.
List<VendorContact> visibleVendorContacts(
  List<VendorContact> contacts, {
  Company? company,
}) => contacts
    .where(
      (c) =>
          !c.isDeleted && (!c.isBlank || _hasLabelledCustomValue(c, company)),
    )
    .toList(growable: false);

List<String> _customValuesOf(VendorContact c) => [
  c.customValue1,
  c.customValue2,
  c.customValue3,
  c.customValue4,
];

/// Whether [contact]'s row will print at least one custom field — the same
/// `customFieldDetailRows` the row itself uses, so "worth showing" and "has
/// something to show" cannot disagree.
bool _hasLabelledCustomValue(VendorContact contact, Company? company) {
  if (company == null) return false;
  final values = _customValuesOf(contact);
  if (values.every((v) => v.isEmpty)) return false;
  return customFieldDetailRows(
    company: company,
    prefix: 'vendor_contact',
    values: values,
    yes: '',
    no: '',
  ).isNotEmpty;
}

class _VendorDetailContactsCardState extends State<VendorDetailContactsCard> {
  static const int _inlineLimit = 3;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Filter BEFORE the early return, and count "+N more" off the filtered
    // list: an overflow button offering to reveal rows that paint nothing is
    // the same bug as the blank row itself.
    final all = visibleVendorContacts(widget.contacts, company: widget.company);
    if (all.isEmpty) return const SizedBox.shrink();
    final showAll = _expanded || all.length <= _inlineLimit;
    final visible = showAll ? all : all.take(_inlineLimit).toList();
    final hiddenCount = all.length - visible.length;
    // "Primary" only says something beside another contact.
    final labelPrimary = all.length >= 2;
    final avatars = PartyContactRow.showAvatars(
      context,
      emails: all.map((c) => c.email),
    );
    final region = phoneDisplayRegion(context, countryId: widget.countryId);

    return PartyContactsCard(
      count: all.length,
      onAdd: widget.onAdd,
      rows: [
        for (final c in visible)
          VendorContactRow(
            c,
            widget.vendorId,
            company: widget.company,
            labelPrimary: labelPrimary,
            avatar: avatars,
            phoneRegion: region,
          ),
      ],
      hiddenCount: hiddenCount,
      // An expansion has to be undoable: a vendor with thirty contacts
      // otherwise stays thirty rows tall until the screen is rebuilt.
      expanded: _expanded && all.length > _inlineLimit,
      onShowMore: () => setState(() => _expanded = true),
      onShowLess: () => setState(() => _expanded = false),
    );
  }
}

/// One vendor contact, as a [PartyContactRow].
///
/// This is the vendor half of the split that widget's doc describes: it turns
/// a [VendorContact] into strings and callbacks, and decides which actions
/// exist.
///
/// **Action order** is Call, Email, Copy portal link, then Message and View
/// Portal — the client row's, so a contact works the same on either party.
/// The row gives the first two available their own button, so a phone gets
/// Call + Email and a desktop with tap-to-call off gets Email + Copy portal
/// link.
class VendorContactRow extends StatelessWidget {
  const VendorContactRow(
    this.contact,
    this.vendorId, {
    super.key,
    this.company,
    this.labelPrimary = false,
    this.avatar = false,
    this.phoneRegion,
  });

  final VendorContact contact;

  /// The country the number is read in for display (`phoneDisplayRegion`).
  final String? phoneRegion;
  final String vendorId;

  /// Mark the primary contact "Primary" — true only where the vendor has two
  /// or more contacts worth showing (`PartyContactRow.isPrimary`).
  final bool labelPrimary;

  /// Lead with an initials avatar seeded on the contact's id
  /// (`PartyContactRow.showAvatars` decides, for the whole card).
  final bool avatar;

  /// For contact custom-field labels; null draws none.
  final Company? company;

  // `PhoneActionsScope` wraps the WHOLE row, not just the number: the Call /
  // Message actions are built here, one level above `PhoneNumberValue`'s own
  // scope, so without this they hold whatever the preference was when the card
  // was last built. A detail screen stays mounted behind `/settings/**`.
  @override
  Widget build(BuildContext context) => PhoneActionsScope(builder: _buildRow);

  Widget _buildRow(BuildContext context) {
    final subject = _contactSubject(context, contact);
    // Titled with the contact, filed against the vendor: this row is the one
    // place the app knows *which person* was rung.
    final CallLogTarget logTarget = (
      type: EntityType.vendor,
      id: vendorId,
      subject: subject,
    );
    final dialable = canDialPhone(context, contact.phone);
    final hasEmail = mailtoUri(contact.email) != null;
    final portalUrl = vendorPortalUrl(contactLink: contact.link);
    final hasPortal = portalUrl.isNotEmpty;
    return PartyContactRow(
      name: '${contact.firstName} ${contact.lastName}'.trim(),
      email: contact.email,
      phone: contact.phone,
      isPrimary: labelPrimary && contact.isPrimary,
      avatarSeed: !avatar
          ? null
          : (contact.id.isNotEmpty
                ? contact.id
                : '${contact.email}|${contact.firstName} ${contact.lastName}'),
      phoneRegion: phoneRegion,
      phoneSubject: subject,
      // No `clientId`: a vendor has no settings cascade of its own, so the
      // out-of-hours check falls back to the company's timezone — and the
      // card shows no local time at all.
      logTarget: logTarget,
      pills: [
        // Its own key, not `cc_only`, which the German, French and Dutch
        // bundles translate as "credit card only".
        if (contact.ccOnly)
          PartyContactPill(label: context.tr('contact_cc_only_label')),
      ],
      details: _details(context),
      actions: [
        PartyContactAction(
          icon: Icons.call_outlined,
          label: context.tr('call'),
          onTap: dialable
              ? () => callPhoneNumber(
                  context,
                  contact.phone,
                  subject: subject,
                  logTarget: logTarget,
                )
              : null,
        ),
        PartyContactAction(
          icon: Icons.mail_outline,
          label: context.tr('email'),
          onTap: hasEmail ? () => composeEmail(context, contact.email) : null,
        ),
        PartyContactAction(
          // The record menu's portal-link item, for this contact: the same
          // words, and the share sheet on touch (`portal_link_action.dart`).
          icon: portalLinkButtonIcon(),
          label: portalLinkActionLabel(context, vendor: true),
          onTap: hasPortal
              ? () => sharePortalLink(
                  context,
                  vendor: true,
                  // Bare: `portalUrl` is the admin's own silent form.
                  targets: [PortalLinkTarget(link: contact.link)],
                )
              : null,
        ),
        PartyContactAction(
          icon: Icons.sms_outlined,
          label: context.tr('send_sms'),
          onTap: dialable
              ? () => messagePhoneNumber(context, contact.phone)
              : null,
        ),
        PartyContactAction(
          icon: Icons.open_in_new,
          label: context.tr('view_portal'),
          onTap: hasPortal
              ? () => launchVendorPortal(context, portalUrl)
              : null,
        ),
      ],
    );
  }

  /// Read-only extras: the last portal login, and any contact custom fields
  /// the company has labelled. `Services` is touched only when there is one of
  /// these to format, so the row still builds under a stub in tests.
  List<String> _details(BuildContext context) {
    final lastLogin = contact.lastLogin;
    final values = _customValuesOf(contact);
    final hasCustom = company != null && values.any((v) => v.isNotEmpty);
    if (lastLogin == null && !hasCustom) return const [];
    final services = context.read<Services>();
    final formatter = services.formatterIfReady(
      services.auth.session.value?.currentCompanyId ?? '',
    );
    return [
      // The local calendar day, as the header does for created/updated.
      if (lastLogin != null && formatter != null)
        '${context.tr('last_login')}: '
            '${formatter.date(lastLogin.toLocal().toIso8601String().split('T').first)}',
      if (hasCustom)
        for (final r in customFieldDetailRows(
          company: company,
          prefix: 'vendor_contact',
          values: values,
          formatter: formatter,
          yes: context.tr('yes'),
          no: context.tr('no'),
        ))
          '${r.label}: ${r.value}',
    ];
  }
}

/// Who the confirmation prompt names when this contact is called. Falls back
/// through name → email → the "blank contact" label, so the dialog never asks
/// the user to confirm calling nobody.
String _contactSubject(BuildContext context, VendorContact contact) {
  final name = ('${contact.firstName} ${contact.lastName}').trim();
  if (name.isNotEmpty) return name;
  if (contact.email.isNotEmpty) return contact.email;
  return context.tr('no_name_fallback');
}
