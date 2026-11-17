import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/detail/entity_detail_header.dart';
import 'package:admin/ui/core/detail/record_details_cards.dart';
import 'package:admin/ui/core/detail/record_profile_layout.dart';
import 'package:admin/ui/features/tasks/widgets/detail/task_detail_description_card.dart';
import 'package:admin/ui/features/tasks/widgets/detail/task_detail_details_card.dart';
import 'package:admin/utils/formatting.dart';

/// A task's reference fields — the details, and the description when it is
/// longer than the header can show. Always shown, between the comments card
/// and the tabs.
///
/// A task has little to put here, by design: who it is for is the header's
/// subtitle, how it stands is the standing card, and what was done is the
/// Time Log tab. What is left is Details — when it is due, the invoice that
/// billed it — and Additional Info — who it is assigned to, custom fields,
/// created and updated — as two level cards on a wide window
/// (`RecordProfileLayout`, `recordDetailsCards`), stacked below it, and one
/// Details card when only one half has rows. The description is prose, so it
/// takes the full width beneath.
///
/// **Every entry is gated on having rows**: the gap between cards is paid
/// per entry, so a card that returned `SizedBox.shrink()` from its own
/// `build` would leave a doubled gap.
class TaskDetailProfile extends StatelessWidget {
  const TaskDetailProfile({
    super.key,
    required this.task,
    required this.company,
    this.formatter,
  });

  final Task task;

  /// For the custom-field labels in Additional Info — see
  /// `TaskDetailDetailsCard.bookkeepingRows`.
  final Company? company;
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    final lead = recordDetailsCards(
      context,
      facts: TaskDetailDetailsCard.factRows(
        context,
        task,
        formatter: formatter,
      ),
      bookkeeping: TaskDetailDetailsCard.bookkeepingRows(
        context,
        task,
        company,
        formatter: formatter,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= Breakpoints.entityFormMultiColumn;
        // The header shares this column below the breakpoint, and takes the
        // lead side of the band (11 of 20, across one large gap) above it.
        final band = InSpacing.lg(context);
        final headerWidth = wide ? (width - band) * 11 / 20 : width;
        final hasDescription = TaskDetailDescriptionCard.truncatedInHeader(
          context,
          task,
          nameWidth: headerWidth - detailHeaderLeadingInset(context),
        );
        return RecordProfileLayout(
          lead: lead,
          tail: [if (hasDescription) TaskDetailDescriptionCard(task: task)],
        );
      },
    );
  }
}
