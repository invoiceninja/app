import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/clamped_text.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/utils/notes_html.dart';

/// Lines of a private note a record screen shows before its More — enough
/// for the usual "call Jane before invoicing" or "special rate: 80/h" whole,
/// short enough that an essay does not decide where the tabs start.
const int kPrivateNotesCalloutLines = 4;

/// A record's private notes as a highlighted callout — a lock and the
/// fixed warning tone (`InTheme.warning` / `warningSoft`) — so the account
/// information users keep there cannot be scrolled past
/// (`docs/detail-screen-layout.md` § Private notes are a callout above the
/// comments). v1 drew the same thing as an `IconMessage` with a lock at the
/// head of the invoice, client and vendor overviews.
///
/// Used on the five billing documents', the client's and the vendor's record
/// screens (the `EntityRecordColumn.alert` slot) and under the party picker
/// of the billing-doc editor (`BillingDocPartyNotes`).
///
/// [notes] is the **stored** value — HTML on the wire — and is flattened here
/// with `plainTextFromHtml`; markup that holds no words (`<p></p>`) draws
/// nothing at all. **Always mount it** and let it hide itself: a slot that
/// came and went with the note would move everything under it in the tree.
///
/// The text is clamped to [maxLines] with an in-place More ([ClampedText]),
/// and copyable through [CopyableValue]: the hover icon with a pointer, a
/// long-press on touch (the tap is the clamp's More). On a record screen it
/// is also inside the page's `AppSelectionArea`, so a pointer can drag-select
/// part of it.
class PrivateNotesCallout extends StatelessWidget {
  const PrivateNotesCallout({
    super.key,
    required this.notes,
    this.maxLines = kPrivateNotesCalloutLines,
  });

  /// The stored private notes, HTML or plain text.
  final String notes;

  final int maxLines;

  /// Whether a callout for [notes] would draw anything.
  static bool hasContent(String notes) => plainTextFromHtml(notes).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final text = plainTextFromHtml(notes);
    if (text.isEmpty) return const SizedBox.shrink();
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final label = context.tr('private_notes');
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        key: const ValueKey('private-notes-callout'),
        decoration: BoxDecoration(
          color: tokens.warningSoft,
          borderRadius: BorderRadius.circular(InRadii.r2),
          border: Border.all(color: tokens.warning.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            InSpacing.md(context),
            InSpacing.sm,
            InSpacing.md(context),
            InSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // Level with the label's cap height rather than its box top.
                padding: const EdgeInsetsDirectional.only(top: 1),
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: tokens.warning,
                ),
              ),
              const SizedBox(width: InSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: InSpacing.xs),
                    CopyableValue(
                      value: text,
                      // The clamp's More is the tap; a long-press copies the
                      // whole note, as on a link-bearing value.
                      enableTapToCopy: false,
                      enableLongPressToCopy: true,
                      child: ClampedText(
                        text: text,
                        maxLines: maxLines,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
