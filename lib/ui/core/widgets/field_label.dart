import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';

/// A form field with its label on a line of its own above it — how the app
/// labels a field at the Comfortable density. Under Compact the label goes
/// back inside the box as Material's floating label, which costs no height
/// (`docs/form-fields.md` § Labels sit above the field).
///
/// The floating label is the field's placeholder until it has a value: a
/// half-filled form mixes small labels on some borders with grey names inside
/// other boxes, the grey name reads as a value, and a real hint ("Auto
/// generated") can only show while the field has focus. Above the field the
/// label is always there and always the same size.
///
/// **The field keeps its `labelText`.** This widget hides it (a local
/// [InputDecorationTheme]) rather than asking 200 call sites to drop it, so
/// Compact needs no second code path, the field's screen-reader name is still
/// the decoration's, and the label is found where it always was.
///
/// A null or empty [label] returns [child] untouched, so a shared field whose
/// label is optional (a table cell under a column header) wraps
/// unconditionally.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.fills = false,
  });

  final String? label;
  final Widget child;

  /// The field takes all the height the parent gives (a `TextField` with
  /// `expands: true` in a bounded slot). Without this the column shrink-wraps
  /// and such a field has no height to expand into.
  final bool fills;

  /// The label's text style: the one hand-drawn label rows (the notes editor,
  /// the tag picker, the email composer) are matched to.
  static TextStyle textStyle(BuildContext context) {
    final theme = Theme.of(context);
    // Not `context.inTheme`: a field can sit under a bare `MaterialApp` (a
    // widget test, a preview), and a label is no reason to throw there.
    final color =
        theme.extension<InTheme>()?.ink2 ?? theme.colorScheme.onSurfaceVariant;
    return TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500);
  }

  /// Whether fields under [context] draw their label above — i.e. not
  /// Compact.
  static bool above(BuildContext context) =>
      !ListDensityScope.isCompactOf(context);

  /// The inside label, drawn at no size. `always` with a zero-width label is
  /// the combination that works: the label counts as withdrawn, so an empty
  /// field shows its hint (with `never` the unseen label keeps the hint's
  /// slot), and `OutlineInputBorder` cuts no notch for a gap of zero extent.
  /// The `labelText` itself stays on the decoration, which is where a text
  /// field takes its screen-reader name from.
  ///
  /// The negative letter spacing is what makes the width zero everywhere: on
  /// the web a font size of 0 still measured a pixel or two, and any width at
  /// all gets the border's 8 px of gap padding on top, which showed as a nick
  /// in the top edge of every field.
  static const _hidden = TextStyle(
    color: Color(0x00000000),
    fontSize: 0,
    letterSpacing: -20,
    wordSpacing: -20,
  );

  /// One derived theme per app theme (a `ThemeData` is the same object from
  /// one build to the next), so thirty fields on a form do not each copy it.
  static final Expando<ThemeData> _fieldThemes = Expando<ThemeData>();

  /// [theme] with the two styles Material draws a field's value in set to the
  /// app's field size. A plain `TextField` takes `bodyLarge` (16 px) and a
  /// `DropdownButtonFormField` `titleMedium`, while the shared fields
  /// (`EntityEditField`, the pickers, the date field) pass `bodyMedium` (14):
  /// two sizes of text, and so two heights of box (48 and 44), side by side
  /// in one card. Every labelled field is under this, at either density.
  static ThemeData _fieldTheme(ThemeData theme) {
    return _fieldThemes[theme] ??= () {
      final text = theme.textTheme;
      final size = text.bodyMedium;
      return theme.copyWith(
        textTheme: text.copyWith(
          bodyLarge: size?.copyWith(color: text.bodyLarge?.color),
          titleMedium: size?.copyWith(color: text.titleMedium?.color),
        ),
      );
    }();
  }

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    if (label == null || label.isEmpty) return child;
    final theme = Theme.of(context);
    final sized = Theme(data: _fieldTheme(theme), child: child);
    if (!above(context)) return sized;
    final Widget field = InputDecorationTheme(
      data: theme.inputDecorationTheme.copyWith(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: _hidden,
        floatingLabelStyle: _hidden,
      ),
      // A text field names itself from its decoration. Anything else
      // (a dropdown, a read-only decorator) is named here, since its
      // inside label is no longer drawn.
      child: child is TextField || child is TextFormField
          ? sized
          : Semantics(label: label, child: sized),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            top: InSpacing.xs,
            start: 2,
            bottom: InSpacing.xs,
          ),
          // The field itself still carries the name for a screen reader.
          // `RichText`, not `Text`: the decoration's own label is still a
          // `Text` in the tree, and a second one would double every match.
          child: ExcludeSemantics(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: MediaQuery.textScalerOf(context),
              text: TextSpan(text: label, style: textStyle(context)),
            ),
          ),
        ),
        if (fills) Expanded(child: field) else field,
      ],
    );
  }
}
