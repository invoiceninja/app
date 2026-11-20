import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/vendor.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/notes_block.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/utils/notes_html.dart';

/// The party's notes as plain text — either may be empty.
typedef _PartyNotes = ({String privateNotes, String publicNotes});

/// Lines of a note shown before its More — what v1 showed, enough for a
/// driving distance or a special price without pushing the form down.
const int kBillingDocPartyNoteLines = 3;

/// The client's (a purchase order's vendor's) private and public notes, read
/// only, under the party picker of the billing-doc edit form —
/// invoiceninja/app#201. Users keep invoicing information on the client
/// ("driving distance", "special prices") and need it while they bill; v1
/// showed both notes here, private first, and so does this.
///
/// Shown on a new document and a saved one alike: the notes matter as much
/// when a draft is reopened as when it is started.
///
/// Read from Drift only, so it works offline, and through the party's watch,
/// so a picked client, a `/refresh` top-up or an inline-created client syncing
/// re-renders it. The record is already local: a pick comes from the picker's
/// own Drift rows, and a saved document's locked party row
/// (`ClientNameLabel` / `VendorNameLabel`) hydrates a missing one.
///
/// **Owns its leading [gap].** Nothing is drawn — not even the gap — while no
/// party is picked or neither note holds any words once flattened
/// (`plainTextFromHtml`: `<p></p>` is empty), so a blank note costs the form
/// no height.
class BillingDocPartyNotes extends StatefulWidget {
  const BillingDocPartyNotes({
    super.key,
    required this.party,
    required this.companyId,
    required this.partyId,
    required this.gap,
  });

  final BillingDocParty party;
  final String companyId;

  /// The draft's client id (vendor id on a purchase order); empty = none yet.
  final String partyId;

  /// Space above the notes, drawn only with them.
  final double gap;

  @override
  State<BillingDocPartyNotes> createState() => _BillingDocPartyNotesState();
}

/// Holds the party watch, so a rebuild (every keystroke on the form) re-reads
/// it instead of re-subscribing. Rebuilt only when the party changes.
class _BillingDocPartyNotesState extends State<BillingDocPartyNotes> {
  String? _key;
  Stream<_PartyNotes?>? _notes;

  static _PartyNotes? _ofClient(Client? c) => c == null
      ? null
      : (
          privateNotes: plainTextFromHtml(c.privateNotes),
          publicNotes: plainTextFromHtml(c.publicNotes),
        );

  static _PartyNotes? _ofVendor(Vendor? v) => v == null
      ? null
      : (
          privateNotes: plainTextFromHtml(v.privateNotes),
          publicNotes: plainTextFromHtml(v.publicNotes),
        );

  void _watch(Services services) {
    final w = widget;
    final key = '${w.party.name}|${w.companyId}|${w.partyId}';
    if (key == _key) return;
    _key = key;
    if (w.party == BillingDocParty.client) {
      _notes = services.clients
          .watch(companyId: w.companyId, id: w.partyId)
          .map(_ofClient)
          .distinct();
    } else {
      _notes = services.vendors
          .watch(companyId: w.companyId, id: w.partyId)
          .map(_ofVendor)
          .distinct();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.partyId.isEmpty) return const SizedBox.shrink();
    _watch(context.read<Services>());
    return StreamBuilder<_PartyNotes?>(
      // Keyed on the party, so a pick never paints the previous party's notes
      // for a frame while the new watch starts. No `peek` seed: like the
      // contacts beside it, the notes land with the watch's first event — the
      // form is not a master-detail pane re-mounted on every row click.
      key: ValueKey(_key),
      stream: _notes,
      builder: (context, snapshot) {
        final notes = snapshot.data;
        final hasPrivate = notes?.privateNotes.isNotEmpty ?? false;
        final hasPublic = notes?.publicNotes.isNotEmpty ?? false;
        if (!hasPrivate && !hasPublic) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('billing-party-notes'),
          padding: EdgeInsetsDirectional.only(top: widget.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasPrivate)
                NotesBlock(
                  label: context.tr('private_notes'),
                  body: notes!.privateNotes,
                  maxLines: kBillingDocPartyNoteLines,
                ),
              if (hasPrivate && hasPublic)
                SizedBox(height: InSpacing.md(context)),
              if (hasPublic)
                NotesBlock(
                  label: context.tr('public_notes'),
                  body: notes!.publicNotes,
                  maxLines: kBillingDocPartyNoteLines,
                ),
            ],
          ),
        );
      },
    );
  }
}
