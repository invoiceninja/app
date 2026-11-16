import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/adaptive.dart';

/// The width from which an address card pairs City / State and Postal Code /
/// Country: low enough for the two address cards sitting side by side.
const double kAddressPairWidth = 340;

/// Lays out two edit fields side-by-side on wide widths, stacked on narrow.
///
/// Used inside the edit-screen cards to pair semantically-related fields
/// (e.g. first_name + last_name, city + state) so a desktop card reads as
/// half as tall as one stacked column.
///
/// Below [minPairWidth] the two children stack as a `Column` so each
/// gets the full card width.
class ClientEditFieldPair extends StatelessWidget {
  const ClientEditFieldPair({
    super.key,
    required this.left,
    required this.right,
    this.minPairWidth = Breakpoints.wide,
  });

  final Widget left;
  final Widget right;

  /// The width from which the two sit side by side. The address cards pass a
  /// lower one: beside each other they are each under [Breakpoints.wide], and
  /// City / State and Postal Code / Country are short enough to share a row.
  final double minPairWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minPairWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              SizedBox(width: InSpacing.md(context)),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [left, right],
        );
      },
    );
  }
}
