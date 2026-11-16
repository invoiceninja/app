import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// A small heading that splits one form card into groups of related fields
/// (Edit Client's Settings: Ownership, Defaults, Profile, Tax).
///
/// For a card whose fields are several kinds of thing: twelve fields in one
/// undivided grid made the user read all twelve to find one. Not a card of its
/// own — a group of two or four fields does not earn a border, a title bar and
/// a gap. [first] drops the space above, for the group that opens the card.
class FormGroupHeading extends StatelessWidget {
  const FormGroupHeading(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: first ? 0 : InSpacing.lg(context),
        bottom: InSpacing.xs,
        start: 2,
      ),
      // Level 3: the card's own title is the section (level 2).
      child: Semantics(
        header: true,
        headingLevel: 3,
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.inTheme.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
