import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/widgets/overridable_field.dart';

/// One choice of a [SegmentedChoiceField].
typedef SegmentedChoice<T> = ({T value, String label});

/// What a segment costs beyond its label: Material 3's 12 px side padding
/// twice, the 1 px divider, and room for the label to breathe so it never
/// ends up touching the border.
const double _kSegmentChrome = 12 * 2 + 1 + 8;

/// Below this field width (a phone, a slide-over) segments that fit are
/// stretched to the card's width, as the inputs above and below them are,
/// rather than sitting as a short strip at the start edge.
const double _kFillBelowWidth = 520;

/// Whether [labels] fit as segments of one [SegmentedButton] in [maxWidth],
/// at the theme's segment text style and the device's text scale. Each
/// segment is as wide as its own label (`SegmentedButton` sizes segments to
/// their content), so the sum is what has to fit.
///
/// This is the question [SegmentedSettingRow] answers by width alone; here
/// the labels are translated, so the same field can fit in English and not
/// in German at the same width — measured, never a px threshold.
bool segmentsFit(BuildContext context, List<String> labels, double maxWidth) {
  if (!maxWidth.isFinite) return true;
  final theme = Theme.of(context);
  final style =
      theme.segmentedButtonTheme.style?.textStyle?.resolve(const {}) ??
      theme.textTheme.labelLarge ??
      const TextStyle(fontSize: 14);
  final scaler = MediaQuery.textScalerOf(context);
  var total = 2.0; // the outer border
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    total += painter.width + _kSegmentChrome;
    painter.dispose();
  }
  return total <= maxWidth;
}

/// A short fixed choice (two to four options) as a [SegmentedButton] under
/// its label — one tap, every option visible — that turns into a radio group
/// when a translated label would not fit the width it has.
///
/// The label is drawn above at both densities (the reveal of a settings
/// search hit looks for it), and the control reads as one named group to a
/// screen reader.
///
/// [value] may be null (a setting the company never picked, like Email
/// Alignment): no segment is selected, and nothing is written until the user
/// picks one. Tapping the selected segment does nothing — a choice can't be
/// un-made here. A null [onChanged] disables the control (VeriFactu's locked
/// Generate Number).
class SegmentedChoiceField<T> extends StatelessWidget {
  const SegmentedChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.fullLabelOf,
  });

  final String label;
  final T? value;
  final List<SegmentedChoice<T>> options;
  final ValueChanged<T>? onChanged;

  /// The long name of an option whose segment [SegmentedChoice.label] is a
  /// short form ("1" for "One Tax Rate"): the segment's tooltip and the
  /// title of its radio row when the segments don't fit. Null when the
  /// segment labels already say everything.
  final String Function(T)? fullLabelOf;

  /// One line of explanation under the control.
  final String? helperText;

  /// A server validation message, which replaces [helperText] while shown.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final note = errorText ?? helperText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kFieldVerticalGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: kLabelGap),
            child: ExcludeSemantics(
              child: Text(label, style: LabeledField.textStyle(context)),
            ),
          ),
          Semantics(
            label: label,
            container: true,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fits = segmentsFit(context, [
                  for (final o in options) o.label,
                ], constraints.maxWidth);
                return fits
                    ? _segments(fill: constraints.maxWidth < _kFillBelowWidth)
                    : _radios();
              },
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: InSpacing.xs),
              child: Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: errorText != null
                      ? theme.colorScheme.error
                      : tokens.ink3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segments({required bool fill}) {
    final selected = value;
    final onChanged = this.onChanged;
    final fullLabelOf = this.fullLabelOf;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SegmentedButton<T>(
        expandedInsets: fill ? EdgeInsets.zero : null,
        showSelectedIcon: false,
        // A setting that was never picked selects nothing.
        emptySelectionAllowed: true,
        segments: [
          for (final o in options)
            ButtonSegment<T>(
              value: o.value,
              label: Text(o.label),
              tooltip: fullLabelOf?.call(o.value),
            ),
        ],
        selected: selected == null ? <T>{} : {selected},
        onSelectionChanged: onChanged == null
            ? null
            : (s) {
                // Tapping the selected segment empties the set; a choice
                // stays made.
                if (s.isNotEmpty) onChanged(s.first);
              },
      ),
    );
  }

  Widget _radios() {
    final onChanged = this.onChanged;
    final fullLabelOf = this.fullLabelOf;
    return IgnorePointer(
      // `RadioGroup.onChanged` is non-nullable; a disabled field ignores
      // taps and dims, as `OverridableRadioField` does.
      ignoring: onChanged == null,
      child: Opacity(
        opacity: onChanged == null ? 0.5 : 1,
        child: RadioGroup<T>(
          groupValue: value,
          onChanged: (v) {
            if (v != null) onChanged?.call(v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in options)
                RadioListTile<T>(
                  value: o.value,
                  title: Text(fullLabelOf?.call(o.value) ?? o.label),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [SegmentedChoiceField] for a cascade setting (`company.settings.*`): the
/// override checkbox at group / client scope, the 422 message under the
/// control. Reading and writing stay with the caller ([value] /
/// [onChanged]), as on `OverridableDropdownField`, so freezed `copyWith`
/// keeps its types.
class OverridableSegmentedField<T> extends StatelessWidget {
  const OverridableSegmentedField({
    super.key,
    required this.label,
    required this.apiKey,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final String apiKey;
  final T? value;
  final List<SegmentedChoice<T>> options;
  final ValueChanged<T>? onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final host = context.watch<SettingsDraftHost>();
    final errors = host.fieldErrors[apiKey];
    return OverridableField.bind(
      apiKey: apiKey,
      label: label,
      // The shown value, or the first option when nothing is inherited — a
      // null seed collapses straight back to "not overridden" and the
      // checkbox could never be ticked (`OverridableDropdownField.seedOnEnable`).
      cascadedValueOnEnable: () =>
          (value ?? (options.isEmpty ? null : options.first.value))?.toString(),
      child: SegmentedChoiceField<T>(
        label: label,
        value: value,
        options: options,
        onChanged: onChanged,
        helperText: helperText,
        errorText: (errors != null && errors.isNotEmpty) ? errors.first : null,
      ),
    );
  }
}
