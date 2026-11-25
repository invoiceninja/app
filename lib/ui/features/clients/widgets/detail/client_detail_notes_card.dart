import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/clamped_text.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/utils/notes_html.dart';

/// The client's public notes; hides entirely when they hold no words.
///
/// **The private notes are not here.** They are the `PrivateNotesCallout`
/// under the standing card (`EntityRecordColumn.alert`), where they cannot be
/// scrolled past; drawing them here as well would show the same words twice
/// on one screen (docs/detail-screen-layout.md § Private notes are a callout
/// above the comments).
class ClientDetailNotesCard extends StatelessWidget {
  const ClientDetailNotesCard({super.key, required this.client});

  final Client client;

  /// Whether this card would render anything.
  ///
  /// The field is HTML on the wire, so the question is whether it holds any
  /// *words* — markup that renders as nothing (`<p></p>`) must not reserve a
  /// card, and a card that hides itself still costs the caller a gap.
  static bool hasContent(Client client) =>
      plainTextFromHtml(client.publicNotes).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // HTML on the wire — written here, by the React client, or by the pre-v5
    // apps — so what a reader wants is the words.
    final publicNotes = plainTextFromHtml(client.publicNotes);
    if (publicNotes.isEmpty) return const SizedBox.shrink();
    // Titled for what it holds: with the private notes gone to the callout,
    // a "Notes" card over a "Public Notes" label said the same thing twice.
    return DashboardCardShell(
      title: context.tr('public_notes'),
      child: ClampedText(
        text: publicNotes,
        maxLines: _kNoteLines,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.inTheme.ink),
      ),
    );
  }
}

/// Enough to read a typical note whole, short enough that an essay does not
/// take the page.
const int _kNoteLines = 6;
