import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';

/// Canonical compact field decoration for the desktop billing-doc edit
/// cards. Mirrors `SearchableDropdownField`'s look (dense, md/14
/// padding, rounded outline, accent focus) so plain `TextField`s, the
/// Client/Design pickers, and `InDateField` all render at the SAME
/// height. Without this the screen mixed three field heights.
InputDecoration billingFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? errorText,
}) {
  final tokens = context.inTheme;
  final border = inFieldBorder(tokens, radius: InRadii.r1);
  return InputDecoration(
    // lint: allow-inside-label every caller wraps its field in LabeledField
    labelText: label,
    hintText: hint,
    errorText: errorText,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: InSpacing.md(context),
      vertical: InSizes.fieldPadV,
    ),
    border: border,
  );
}
