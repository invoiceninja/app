import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/notes_block.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/notes_html.dart';

/// Private + public notes card. Renders either or both fields depending on
/// which are populated; hides entirely when both are empty.
class ClientDetailNotesCard extends StatelessWidget {
  const ClientDetailNotesCard({super.key, required this.client});

  final Client client;

  /// Whether this card would render anything.
  ///
  /// Both fields are HTML on the wire, so the question is whether they hold
  /// any *words* — markup that renders as nothing (`<p></p>`) must not reserve
  /// a card, and a card that hides itself still costs the caller a gap.
  static bool hasContent(Client client) =>
      plainTextFromHtml(client.privateNotes).isNotEmpty ||
      plainTextFromHtml(client.publicNotes).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Both fields are HTML on the wire — written here, by the React client, or
    // by the pre-v5 apps — so what a reader wants is the words. Gate on the
    // flattened text too: markup that renders as nothing (`<p></p>`) must not
    // open a card with nothing in it.
    final privateNotes = plainTextFromHtml(client.privateNotes);
    final publicNotes = plainTextFromHtml(client.publicNotes);
    final hasPrivate = privateNotes.isNotEmpty;
    final hasPublic = publicNotes.isNotEmpty;
    if (!hasPrivate && !hasPublic) return const SizedBox.shrink();
    final tokens = context.inTheme;
    return DashboardCardShell(
      title: context.tr('notes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPrivate)
            NotesBlock(
              label: context.tr('private_notes'),
              body: privateNotes,
              maxLines: _kNoteLines,
            ),
          if (hasPrivate && hasPublic) ...[
            SizedBox(height: InSpacing.md(context)),
            Divider(height: 1, thickness: 1, color: tokens.border),
            SizedBox(height: InSpacing.md(context)),
          ],
          if (hasPublic)
            NotesBlock(
              label: context.tr('public_notes'),
              body: publicNotes,
              maxLines: _kNoteLines,
            ),
        ],
      ),
    );
  }
}

/// Enough to read a typical note whole, short enough that an essay does not
/// take the page.
const int _kNoteLines = 6;
