import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// The count beside a tab label — a record screen's "Invoices 3", the billing
/// editor's "Items 2". A zero stays muted whatever the tab: it is the one
/// number that means there is nothing to look at.
///
/// Draws no semantics of its own worth reading: the tab that holds it merges
/// label and count into one node ("Invoices, 3").
class TabCountBadge extends StatelessWidget {
  const TabCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(InRadii.r1),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: count == 0 ? tokens.ink3 : tokens.ink2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
