import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
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
/// The space above and below a labelled field: with the label's own line that
/// puts about 20 px between one field and the next label, the rhythm the
/// form designs use. Shared by the fields that pad themselves
/// (`EntityEditField`, `SearchableDropdownField`, the locked row, the client
/// and tag pickers) and by [LabeledField] for the ones that do not.
const double kFieldVerticalGap = 8;

/// Between a field's label and its box.
const double kLabelGap = 6;

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.fills = false,
    this.padded,
    this.trailing,
  });

  final String? label;
  final Widget child;

  /// The field takes all the height the parent gives (a `TextField` with
  /// `expands: true` in a bounded slot). Without this the column shrink-wraps
  /// and such a field has no height to expand into.
  final bool fills;

  /// Whether to add the shared fields' 4 px of space above and below.
  ///
  /// `EntityEditField`, `SearchableDropdownField` and the locked row pad
  /// themselves and pass false; a field that does not (a raw `TextField`, a
  /// `DropdownButtonFormField`, the date and settings fields) gets it here.
  /// Without it, a padded and an unpadded field side by side in a
  /// `FormFieldPair` put their labels 4 px apart. Null decides by type: true
  /// for the raw Material fields.
  final bool? padded;

  /// A small icon button at the end of the label's line — an action on the
  /// field that the field's own box has no room for (the narrow invoice due
  /// date's payment terms, `InDateField`). Drawn only with the label above
  /// (Comfortable); ignored under Compact, where there is no label line.
  ///
  /// It costs the line no height, so a field beside this one keeps its box
  /// level. The button is laid over the line in a square of the platform's
  /// target size (44 px on touch, 28 with a pointer), from the top of the
  /// field's own space, so on touch the square reaches a few pixels into the
  /// top of the box below it; its icon — expected to be 16 px — is centred on
  /// the label's line, at the end edge, through an [IconButtonTheme] the
  /// button inherits (so it must not set its own `alignment`). The label is
  /// kept clear of the square. Null leaves the field exactly as it was.
  final Widget? trailing;

  bool get _padded =>
      padded ??
      (child is TextField ||
          child is TextFormField ||
          child is DropdownButtonFormField ||
          child is InputDecorator);

  /// The label's text style: the one hand-drawn label rows (the notes editor,
  /// the tag picker, the email composer) are matched to.
  static TextStyle textStyle(BuildContext context) {
    final theme = Theme.of(context);
    // Not `context.inTheme`: a field can sit under a bare `MaterialApp` (a
    // widget test, a preview), and a label is no reason to throw there.
    // Between `ink2` and `ink3`: a label names the value, it should not
    // compete with it. `ink2` alone put labels nearly as bright as the
    // values under them (the form designs' labels sit at about #A8A6A1 on
    // a #F6F4EF value).
    final tokens = theme.extension<InTheme>();
    final color = tokens == null
        ? theme.colorScheme.onSurfaceVariant
        : Color.lerp(tokens.ink2, tokens.ink3, 0.4)!;
    return TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500);
  }

  /// Whether fields under [context] draw their label above — i.e. not
  /// Compact.
  static bool above(BuildContext context) =>
      !ListDensityScope.isCompactOf(context);

  /// The inside label, drawn at no size. `always` with a zero-width label is
  /// the combination that works: the label counts as withdrawn, so an empty
  /// field shows its hint (with `never` the unseen label keeps the hint's
  /// slot). The `labelText` itself stays on the decoration, which is where a
  /// text field takes its screen-reader name from.
  ///
  /// The negative spacing keeps the width under a pixel (on the web a font
  /// size of 0 alone once measured a pixel or two), but it is not zero: a
  /// label holding a space lays out at `FLT_MIN` wide on every engine, and
  /// any width at all gets a bare `OutlineInputBorder`'s 8 px of gap padding,
  /// a nick in the top edge. The whole edge is kept by the border
  /// (`InFieldOutlineBorder` ignores a gap under a pixel), not by this style
  /// (`docs/form-fields.md` § A label above the box cuts no notch in its
  /// border).
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
    if (!above(context)) return _pad(sized);
    // Full height at Comfortable: the desktop theme's compact density took
    // 8 px off every field (36 px), which with a label above read as
    // cramped. 44 px, the touch floor, on every platform. Compact keeps the
    // app's density, with the label inside.
    final roomy = Theme(
      data: _fieldTheme(theme).copyWith(visualDensity: VisualDensity.standard),
      child: child,
    );
    final Widget field = InputDecorationTheme(
      data: theme.inputDecorationTheme.copyWith(
        // A dropdown's button sets a 24 px floor under its text where a text
        // field's line is 20, so with the same padding it came out 48 px
        // beside 44 px fields. Two pixels less padding, one height.
        contentPadding: child is DropdownButtonFormField
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : null,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: _hidden,
        floatingLabelStyle: _hidden,
      ),
      // A text field names itself from its decoration. Anything else
      // (a dropdown, a read-only decorator) is named here, since its
      // inside label is no longer drawn.
      child: child is TextField || child is TextFormField
          ? roomy
          : Semantics(label: label, child: roomy),
    );
    final trailing = this.trailing;
    final target = Env.isTouchPrimary ? InSizes.touchTarget : 28.0;
    final column = _pad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: kLabelGap,
              end: trailing == null ? 0 : target,
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
      ),
    );
    if (trailing == null) return column;
    return Stack(
      children: [
        column,
        PositionedDirectional(
          top: 0,
          end: 0,
          width: target,
          height: target,
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: ButtonStyle(
                alignment: AlignmentDirectional(
                  1,
                  _iconOffset(context, label, target),
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            child: trailing,
          ),
        ),
      ],
    );
  }

  /// The vertical alignment that puts a 16 px icon's centre on the label's
  /// line, inside a [target]-sized square starting at the top of the
  /// field's space (its 8 px pad included).
  double _iconOffset(BuildContext context, String label, double target) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle(context)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final centre = (_padded ? kFieldVerticalGap : 0) + painter.height / 2;
    painter.dispose();
    const icon = 16.0;
    return ((centre - target / 2) / ((target - icon) / 2)).clamp(-1.0, 1.0);
  }

  Widget _pad(Widget w) => _padded
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: kFieldVerticalGap),
          child: w,
        )
      : w;
}
