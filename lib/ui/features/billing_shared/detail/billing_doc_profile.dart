import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/billing/billing_doc_fields.dart';
import 'package:admin/data/models/domain/billing/invitation.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/portal_link_action.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/detail/custom_field_detail_rows.dart';
import 'package:admin/ui/core/detail/profile_card_width.dart';
import 'package:admin/ui/core/utils/external_url.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/party_contact_row.dart';
import 'package:admin/ui/core/widgets/party_contacts_builder.dart';
import 'package:admin/ui/core/widgets/party_money_cell.dart';
import 'package:admin/ui/core/widgets/status_pill.dart';
import 'package:admin/ui/core/widgets/user_name_label.dart';
import 'package:admin/ui/core/widgets/watch_builder.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/formatting.dart';

/// A billing document's reference fields — who it went to, its details.
/// Always shown, between the comments card and the tabs.
///
/// In order: Contacts (the people invited to it), Details. Tags are not here;
/// they are drawn under the document's number.
///
/// **What prints on the document is not here either.** Line items, totals,
/// public notes, terms and footer are the document's *content*: they stay on
/// the Overview tab the screen opens on, in the order the page prints them.
/// Putting the three text fields up here was tried — it is what the client
/// screen does with a client's notes — and on an ordinary invoice it put a
/// paragraph of boilerplate terms between the balance and the line items, in
/// the 440–560 px pane where there is one column and every card is a scroll.
/// A private note is different: it is written for whoever opens this screen,
/// and is worth reading before anything else is done with the document — so
/// it is not here either, but higher: the `PrivateNotesCallout` under the
/// standing card (`EntityRecordColumn.alert`; docs/detail-screen-layout.md
/// § Private notes are a callout above the comments).
///
/// **Every entry is gated on having content**, in both layouts — the gap
/// between cards is paid per entry, so a card that drew nothing from its own
/// `build` would leave a doubled gap between its neighbours.
///
/// * **≥ [Breakpoints.entityFormMultiColumn] of its own width**: Contacts and
///   Details side by side as equal cards ending on one line. That width is rare here — beside the PDF pane this column is
///   five elevenths of the window — so in practice it is a very wide monitor.
/// * **below**: one stack. The record column above this has already centred
///   and capped it.
class BillingDocProfile extends StatelessWidget {
  const BillingDocProfile({
    super.key,
    required this.type,
    required this.doc,
    required this.company,
    required this.contacts,
    this.formatter,
    this.detailRows = const [],
  });

  final BillingDocType type;
  final BillingDocFields doc;

  /// For the custom-field labels in Details. Null while it loads.
  final Company? company;

  /// The party's contacts by id — from a [BillingDocPartyContacts] the host
  /// mounts once, above this, so that whether the Contacts card exists is
  /// known before the cards are laid out.
  final PartyContacts contacts;

  final Formatter? formatter;

  /// Rows only this document has, drawn in the Details card after the shared
  /// ones: the invoice a quote became, a recurring invoice's last send, a
  /// project link. Built by the host because some are cross-entity links,
  /// which only the five record screens may mount
  /// (`no_list_tile_name_link_test`) — use [BillingDocDetailsCard.valueStyle]
  /// for a label widget so it reads like the rows around it.
  final List<Widget> detailRows;

  @override
  Widget build(BuildContext context) {
    final recipients = billingDocRecipients(doc.invitations, contacts);
    final hasDetails = BillingDocDetailsCard.hasContent(
      context,
      type: type,
      doc: doc,
      company: company,
      formatter: formatter,
      extraRows: detailRows,
    );
    final gap = SizedBox(height: InSpacing.md(context));

    final contactsCard = recipients.isEmpty
        ? null
        : BillingDocContactsCard(type: type, recipients: recipients);
    final lead = <Widget>[
      ?contactsCard,
      if (hasDetails)
        BillingDocDetailsCard(
          type: type,
          doc: doc,
          company: company,
          formatter: formatter,
          extraRows: detailRows,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final inRow =
            constraints.maxWidth >= Breakpoints.entityFormMultiColumn &&
            lead.length > 1;
        // The Contacts card is told its width (`ProfileCardWidthScope`) —
        // the one thing a card in the levelled row cannot measure itself.
        final sized = [
          for (final card in lead)
            identical(card, contactsCard)
                ? ProfileCardWidthScope(
                    width: inRow
                        ? ProfileCardWidthScope.share(
                            constraints.maxWidth,
                            lead.length,
                            InSpacing.md(context),
                          )
                        : constraints.maxWidth,
                    child: card,
                  )
                : card,
        ];
        final rows = <Widget>[
          if (inRow)
            // `IntrinsicHeight` so the two cards end on one line. Legal here
            // because neither contains a `LayoutBuilder`.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sized.length; i++) ...[
                    if (i > 0) SizedBox(width: InSpacing.md(context)),
                    Expanded(child: sized[i]),
                  ],
                ],
              ),
            )
          else
            ...sized,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) gap, rows[i]],
          ],
        );
      },
    );
  }
}

/// A billing document's party contacts, by contact id — its client's, or on a
/// purchase order its vendor's — for the profile's Contacts card.
///
/// `PartyContactsBuilder` with a first-frame seed. That builder starts empty
/// and fills when the party's row arrives, which is right for the two places
/// it was written for (a tooltip, a tab not yet opened) and wrong here: the
/// Contacts card sits above the tab strip, so appearing a frame late it
/// pushed the tabs and everything under them down on every record opened.
/// The seed is whatever the list the user came from already resolved for
/// this party; the watch owns the value from its first event on.
class BillingDocPartyContacts extends StatelessWidget {
  const BillingDocPartyContacts({
    super.key,
    required this.companyId,
    required this.type,
    required this.doc,
    required this.builder,
  });

  /// The screen's own company, captured when it opened — not read off the
  /// session here, which names another company for the length of a switch.
  final String companyId;
  final BillingDocType type;
  final BillingDocFields doc;
  final Widget Function(BuildContext context, PartyContacts contacts) builder;

  @override
  Widget build(BuildContext context) {
    final vendorParty = type.party == BillingDocParty.vendor;
    final partyId = vendorParty ? doc.vendorId : doc.clientId;
    if (companyId.isEmpty || partyId.isEmpty) {
      return builder(context, const {});
    }
    final services = context.read<Services>();
    return WatchBuilder<PartyContacts>(
      cacheKey: (companyId, vendorParty, partyId),
      initialData: vendorParty
          ? contactsOfVendor(
              services.vendors.peek(companyId: companyId, id: partyId),
            )
          : contactsOfClient(
              services.clients.peek(companyId: companyId, id: partyId),
            ),
      create: () => vendorParty
          ? services.vendors
                .watch(companyId: companyId, id: partyId)
                .map(contactsOfVendor)
          : services.clients
                .watch(companyId: companyId, id: partyId)
                .map(contactsOfClient),
      builder: (context, snap) => builder(
        context,
        snap.data ?? const <String, ({String name, String email})>{},
      ),
    );
  }
}

/// One person a document is addressed to: the invitation the server made for
/// them, and how they are named.
@immutable
class BillingDocRecipient {
  const BillingDocRecipient({
    required this.invitation,
    required this.name,
    required this.email,
  });

  final Invitation invitation;
  final String name;
  final String email;
}

/// The invitations worth a row: those whose contact has a name or an address.
///
/// `invitations.isNotEmpty` is the right question here, unlike in Email
/// History — this card is the *recipient set*, and a document that has never
/// been sent still has one. What is filtered is the contact: the server seeds
/// every client and vendor with one all-blank contact and makes an invitation
/// for it, and a row reading `(no name)` beside two buttons is the bug
/// `docs/contacts-and-invitations.md` exists to prevent. A contact that has
/// since been removed is not in [contacts] and drops out the same way.
List<BillingDocRecipient> billingDocRecipients(
  List<Invitation> invitations,
  PartyContacts contacts,
) => [
  for (final invitation in invitations)
    if (contacts[invitationContactId(invitation)] case final contact?)
      if (contact.name.trim().isNotEmpty || contact.email.trim().isNotEmpty)
        BillingDocRecipient(
          invitation: invitation,
          name: contact.name.trim(),
          email: contact.email.trim(),
        ),
];

/// The people the document is addressed to, each with where their copy has
/// got to and the two things most often done with it: copy the link they
/// were sent, and look at what they see.
///
/// The link is the *document's* page in the portal for *that contact* — the
/// thing to paste into a chat when an email has gone astray — which until now
/// could only be reached by starting to send the document again.
class BillingDocContactsCard extends StatefulWidget {
  const BillingDocContactsCard({
    super.key,
    required this.type,
    required this.recipients,
  });

  final BillingDocType type;
  final List<BillingDocRecipient> recipients;

  @override
  State<BillingDocContactsCard> createState() => _BillingDocContactsCardState();
}

class _BillingDocContactsCardState extends State<BillingDocContactsCard> {
  /// How many rows show before the rest wait behind "+N more". Most documents
  /// go to one or two people; a client with a dozen contacts on every invoice
  /// must not put a dozen rows between the balance and the line items.
  static const int _inlineLimit = 3;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.recipients;
    if (all.isEmpty) return const SizedBox.shrink();
    final showAll = _expanded || all.length <= _inlineLimit;
    final visible = showAll ? all : all.take(_inlineLimit).toList();
    final hidden = all.length - visible.length;
    // Where every copy has got exactly as far as the others, that is said
    // once, beside the title, with how many there are — six rows each
    // carrying the same "Sent" pill was the tallest thing on the screen and
    // said one thing. A lone recipient keeps their own pill.
    final shared = _sharedState(all);
    final sharedPill = shared == null
        ? null
        : _RecipientRow.statePill(context, shared);
    final avatars = PartyContactRow.showAvatars(
      context,
      emails: all.map((r) => r.email),
    );
    // No local time (the rows have no number to call) and no "+ Add": a
    // document's recipients are edited on the document, its contacts on the
    // party.
    return PartyContactsCard(
      count: all.length,
      extraTrailing: [?sharedPill],
      rows: [
        for (final r in visible)
          _RecipientRow(
            type: widget.type,
            recipient: r,
            showState: shared == null,
            avatar: avatars,
          ),
      ],
      hiddenCount: hidden,
      // An expansion has to be undoable, or the card stays its full length
      // until the screen is rebuilt.
      expanded: _expanded && all.length > _inlineLimit,
      onShowMore: () => setState(() => _expanded = true),
      onShowLess: () => setState(() => _expanded = false),
    );
  }
}

/// The one invitation that stands for all of [recipients], when there are
/// several and every copy is in the same state; null otherwise.
Invitation? _sharedState(List<BillingDocRecipient> recipients) {
  if (recipients.length < 2) return null;
  final first = _RecipientRow.stateKey(recipients.first.invitation);
  if (first == null) return null;
  for (final r in recipients.skip(1)) {
    if (_RecipientRow.stateKey(r.invitation) != first) return null;
  }
  return recipients.first.invitation;
}

/// The portal's own view of a link, without the visit counting as the
/// contact's: the server stamps `viewed_date` on the first request that does
/// not carry `silent` (`ClientPortal/InvitationController`), which would flip
/// the document to Viewed because the *sender* looked.
String _silentPortalLink(String link) =>
    '$link${link.contains('?') ? '&' : '?'}silent=true';

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.type,
    required this.recipient,
    this.showState = true,
    this.avatar = false,
  });

  final BillingDocType type;
  final BillingDocRecipient recipient;

  /// Lead with an initials avatar seeded on the contact's id
  /// (`PartyContactRow.showAvatars` decides, for the whole card).
  final bool avatar;

  /// False when the card's title already says it for every row.
  final bool showState;

  @override
  Widget build(BuildContext context) {
    final link = recipient.invitation.link;
    final hasLink = link.isNotEmpty;
    final vendor = type.party == BillingDocParty.vendor;
    final pill = showState ? statePill(context, recipient.invitation) : null;
    final contactId = invitationContactId(recipient.invitation);
    return PartyContactRow(
      name: recipient.name,
      email: recipient.email,
      phone: '',
      avatarSeed: !avatar
          ? null
          : (contactId.isNotEmpty ? contactId : recipient.email),
      pills: [?pill],
      actions: [
        PartyContactAction(
          // The record menu's portal-link item, for this contact: the same
          // words, and the share sheet on touch (`portal_link_action.dart`).
          icon: portalLinkButtonIcon(),
          label: portalLinkActionLabel(context, vendor: vendor),
          onTap: hasLink
              ? () => sharePortalLink(
                  context,
                  vendor: vendor,
                  targets: [PortalLinkTarget(link: link)],
                )
              : null,
        ),
        PartyContactAction(
          icon: Icons.open_in_new,
          label: context.tr('view_portal'),
          onTap: hasLink
              ? () => openExternalUrl(context, _silentPortalLink(link))
              : null,
        ),
      ],
    );
  }

  /// The furthest this contact's copy has got — one pill, or none for a
  /// document that has not been sent to them.
  ///
  /// A delivery failure outranks everything: it is the answer to "why have
  /// they not paid", and `sendState` already encodes which of the server's
  /// fields can be trusted to say so. After that, the latest good news wins.
  /// Dates and the error text stay on the Email History tab.
  static Widget? statePill(BuildContext context, Invitation invitation) {
    final key = stateKey(invitation);
    if (key == null) return null;
    final tokens = context.inTheme;
    final (Color fg, Color bg) = switch (key) {
      'bounced' || 'spam' || 'error' => (tokens.overdue, tokens.overdueSoft),
      'viewed' || 'opened' => (tokens.sent, tokens.sentSoft),
      'delivered' => (tokens.paid, tokens.paidSoft),
      _ => (tokens.draft, tokens.draftSoft),
    };
    return StatusPill(label: context.tr(key), fgColor: fg, bgColor: bg);
  }

  /// The translation key of the state [statePill] shows, or null for a copy
  /// that has not been sent.
  static String? stateKey(Invitation invitation) =>
      switch (invitation.sendState) {
        InvitationSendState.bounced => 'bounced',
        InvitationSendState.spam => 'spam',
        InvitationSendState.errored => 'error',
        InvitationSendState.delivered || InvitationSendState.none =>
          invitation.hasBeenViewed
              ? 'viewed'
              : invitation.hasBeenOpened
              ? 'opened'
              : invitation.sendState == InvitationSendState.delivered
              ? 'delivered'
              : invitation.hasBeenSent
              ? 'sent'
              : null,
      };
}

/// The facts about the document that are not money, a date in the header, or
/// its line items.
///
/// Blank rows are left out entirely, in every layout, and a document with
/// none of them gets no card. There is deliberately no Created / Updated pair
/// at the foot, as the client's Details card has: a document's own date is in
/// its header and every change to it is on the History and Activity tabs, so
/// here the pair would be a card of its own on most invoices — two rows of the
/// least-wanted facts, above the line items.
class BillingDocDetailsCard extends StatelessWidget {
  const BillingDocDetailsCard({
    super.key,
    required this.type,
    required this.doc,
    required this.company,
    this.formatter,
    this.extraRows = const [],
  });

  final BillingDocType type;
  final BillingDocFields doc;
  final Company? company;
  final Formatter? formatter;
  final List<Widget> extraRows;

  /// The value style of a [DetailInfoRow], for a host row whose value is a
  /// widget (a name resolved from an id) — the row hands a `child` nothing.
  static TextStyle? valueStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.inTheme.ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      );

  /// Whether the card draws anything. **Derived from [rowsFor]**, the list
  /// [build] renders, so the two cannot drift.
  static bool hasContent(
    BuildContext context, {
    required BillingDocType type,
    required BillingDocFields doc,
    required Company? company,
    Formatter? formatter,
    List<Widget> extraRows = const [],
  }) => rowsFor(
    context,
    type: type,
    doc: doc,
    company: company,
    formatter: formatter,
    extraRows: extraRows,
  ).isNotEmpty;

  /// The rows, in display order. Which rows exist never depends on the
  /// currency — only what the two money rows print — so [hasContent] can ask
  /// before the party's currency has resolved.
  static List<Widget> rowsFor(
    BuildContext context, {
    required BillingDocType type,
    required BillingDocFields doc,
    required Company? company,
    Formatter? formatter,
    List<Widget> extraRows = const [],
  }) {
    final f = formatter;
    final partialDue =
        doc is BillingDocPartialFields && doc.partial != Decimal.zero
        ? doc.partialDueDate
        : null;
    // The server's "no rate" is 1, and a row saying so is noise.
    final hasRate =
        doc.exchangeRate != Decimal.zero && doc.exchangeRate != Decimal.one;
    return [
      // A purchase order's own number is its PO number.
      if (type.hasPoNumberField && doc.poNumber.isNotEmpty)
        DetailInfoRow(label: context.tr('po_number'), value: doc.poNumber),
      if (doc.discount != Decimal.zero && f != null)
        _DiscountRow(type: type, doc: doc, formatter: f),
      // The amount is on the standing card; this is when it falls due.
      if (partialDue != null && f != null)
        DetailInfoRow(
          label: context.tr('partial_due_date'),
          value: f.date(partialDue.toIso()),
          copyable: false,
        ),
      if (hasRate && f != null)
        DetailInfoRow(
          label: context.tr('exchange_rate'),
          value: f.decimal(doc.exchangeRate.toDouble(), maxDecimals: 6),
          copyable: false,
        ),
      ...extraRows,
      if (doc.assignedUserId.isNotEmpty)
        DetailInfoRow(
          label: context.tr('assigned_user'),
          value: '',
          copyable: false,
          child: UserNameLabel(
            userId: doc.assignedUserId,
            style: valueStyle(context),
          ),
        ),
      ..._customRows(context, doc, company, f),
    ];
  }

  /// The configured, type-formatted custom-field rows. All five documents
  /// read the `invoice` slots — the server has no separate keys for the
  /// others.
  static List<Widget> _customRows(
    BuildContext context,
    BillingDocFields doc,
    Company? company,
    Formatter? formatter,
  ) {
    final rows = customFieldDetailRows(
      company: company,
      prefix: 'invoice',
      values: [
        doc.customValue1,
        doc.customValue2,
        doc.customValue3,
        doc.customValue4,
      ],
      formatter: formatter,
      yes: context.tr('yes'),
      no: context.tr('no'),
    );
    return [
      for (final r in rows) DetailInfoRow(label: r.label, value: r.value),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = rowsFor(
      context,
      type: type,
      doc: doc,
      company: company,
      formatter: formatter,
      extraRows: extraRows,
    );
    if (rows.isEmpty) return const SizedBox.shrink();
    return DashboardCardShell(
      title: context.tr('details'),
      child: DetailRowStack(children: rows),
    );
  }
}

/// A Details row whose value is a widget — a name resolved from an id, which
/// is a stream and cannot be a string. For a host's
/// [BillingDocProfile.detailRows]; style the widget with
/// [BillingDocDetailsCard.valueStyle].
Widget billingDocLabelRow(
  BuildContext context,
  String labelKey,
  Widget value,
) => DetailInfoRow(
  label: context.tr(labelKey),
  value: '',
  copyable: false,
  child: value,
);

/// A discount is a percentage or an amount, and only the document says which.
/// As an amount it is money in the party's currency, so it resolves that the
/// way the standing card does.
class _DiscountRow extends StatelessWidget {
  const _DiscountRow({
    required this.type,
    required this.doc,
    required this.formatter,
  });

  final BillingDocType type;
  final BillingDocFields doc;
  final Formatter formatter;

  @override
  Widget build(BuildContext context) {
    final label = context.tr('discount');
    if (!doc.isAmountDiscount) {
      return DetailInfoRow(
        label: label,
        value: formatter.percent(doc.discount.toDouble()),
        copyable: false,
      );
    }
    final vendorParty = type.party == BillingDocParty.vendor;
    return PartyCurrencyBuilder(
      clientId: vendorParty ? null : doc.clientId,
      vendorId: vendorParty ? doc.vendorId : null,
      builder: (context, currencyId) => DetailInfoRow(
        label: label,
        value: formatter.money(doc.discount, clientCurrencyId: currencyId),
        copyable: false,
      ),
    );
  }
}
