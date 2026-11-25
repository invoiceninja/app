import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/clamped_text.dart';

/// One read-only note under a small label — "Private notes" over the words —
/// held to [maxLines] with an in-place More / Less ([ClampedText]).
///
/// [body] is already plain text: the stored value is HTML on the wire, so the
/// caller flattens it with `plainTextFromHtml` and gates on the result being
/// non-empty (markup that renders as nothing must not draw a label over
/// nothing).
///
/// The billing-doc edit form's party public notes. (Private notes are a
/// `PrivateNotesCallout` everywhere they are shown.)
class NotesBlock extends StatelessWidget {
  const NotesBlock({
    super.key,
    required this.label,
    required this.body,
    required this.maxLines,
  });

  /// Already resolved through `tr()`.
  final String label;

  /// Plain text, never the stored HTML.
  final String body;

  /// A note has no length limit; unclamped, one long one decides where
  /// everything below it starts.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.ink2,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: InSpacing.xs),
        ClampedText(
          text: body,
          maxLines: maxLines,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.ink),
        ),
      ],
    );
  }
}
