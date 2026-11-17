import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';

/// What the task form's time log shows with no entries — on both layouts, in
/// place of the column headers, which head nothing.
///
/// [EmptyStateBody], not [EmptyState]: the form already scrolls, and the
/// scrolling host [EmptyState] brings would be a viewport inside a viewport.
/// No button: Add time sits in the card's header and Start in the timer card
/// above. An invoiced task ([locked]) keeps the title and drops the line
/// inviting the user to log time, which they cannot.
class TimeLogEmptyState extends StatelessWidget {
  const TimeLogEmptyState({super.key, required this.locked});

  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: InSpacing.lg(context),
        vertical: InSpacing.xl,
      ),
      child: Center(
        child: EmptyStateBody(
          icon: Icons.schedule,
          title: context.tr('no_time_logged_cta'),
          subtitle: locked ? null : context.tr('no_time_logged_help'),
        ),
      ),
    );
  }
}
