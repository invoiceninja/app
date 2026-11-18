import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/adaptive.dart';

/// The width from which an address card pairs City / State and Postal Code /
/// Country: low enough for the two address cards sitting side by side.
const double kAddressPairWidth = 340;

/// The width from which a fixed-width sidebar card (360–400 px) pairs two
/// short fields: Number beside Status on a task, say.
const double kSidebarPairWidth = 300;

/// Two related form fields side by side where the card has room, stacked
/// below [minPairWidth] — the app's one way to pair fields
/// (`docs/form-fields.md` § Related fields share a row).
///
/// Used inside the edit-screen cards to pair semantically-related fields
/// (e.g. first_name + last_name, city + state) so a desktop card reads as
/// half as tall as one stacked column.
///
/// Below [minPairWidth] the two children stack as a `Column` so each
/// gets the full card width.
class FormFieldPair extends StatelessWidget {
  const FormFieldPair({
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
        final paired = constraints.maxWidth >= minPairWidth;
        // One `Flex` whose direction flips, with the two fields in the same
        // `Flexible` slots either way — never a `Row` of `Expanded`s in one
        // branch and a `Column` of bare children in the other. A foldable
        // opening or closing moves the card across [minPairWidth] while a
        // field is being typed in; with two tree shapes that field remounted
        // and lost its focus, caret and keyboard (docs/foldables.md). A flex
        // of 0 lays a child out as an ordinary, unflexed one in the column.
        return Flex(
          direction: paired ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: paired
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
          mainAxisSize: paired ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Flexible(flex: paired ? 1 : 0, fit: FlexFit.tight, child: left),
            SizedBox(width: paired ? InSpacing.md(context) : 0),
            Flexible(flex: paired ? 1 : 0, fit: FlexFit.tight, child: right),
          ],
        );
      },
    );
  }
}

/// [fields] two to a row, in order; an odd one out takes the left half of the
/// last row, so it lines up with the column above instead of stretching the
/// width of the card. For a run of fields whose number depends on settings
/// (Cost and Quantity on a product show only where the company uses them).
List<Widget> pairFields(
  List<Widget> fields, {
  double minPairWidth = Breakpoints.wide,
}) {
  return [
    for (var i = 0; i < fields.length; i += 2)
      FormFieldPair(
        minPairWidth: minPairWidth,
        left: fields[i],
        right: i + 1 < fields.length ? fields[i + 1] : const SizedBox.shrink(),
      ),
  ];
}

/// Between the cards of an edit form, down a column and across the gutter:
/// 16 px. It was 12, which ran the cards together; the form designs leave
/// about 20.
const double kFormCardGap = 16;

/// Around an edit form's cards: 24 px where the window is wide, 12 on a
/// phone, where the margin is width the fields need.
double formPagePadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.wide ? InSpacing.xl : 12;
