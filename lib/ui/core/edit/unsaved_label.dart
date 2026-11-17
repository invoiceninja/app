import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/generic_edit_view_model.dart';

/// "Unsaved" beside an edit screen's title while the form holds changes the
/// user has not saved. Wide layouts only — the narrow header has no room
/// beside the title, and Save itself is the cue there.
///
/// There is no "Saved" state: an entity save pops the screen, and a settings
/// save leaves the page clean, so the word would only flash. Announced as a
/// live region, so a screen reader hears the form go dirty once rather than
/// finding out at the discard prompt.
///
/// Two drivers: an entity edit screen hands over its view model
/// ([UnsavedLabel.new]); a settings page, whose draft lives on a
/// `SettingsDraftHost` rather than a [GenericEditViewModel], hands over the
/// host as a plain [Listenable] plus a getter ([UnsavedLabel.listening]).
class UnsavedLabel extends StatelessWidget {
  /// Driven by an entity edit view model: dirty and not mid-save.
  UnsavedLabel({super.key, required GenericEditViewModel<Object?> vm})
    : listenable = vm,
      isDirty = (() => vm.isDirty && !vm.isSaving);

  /// Driven by any [Listenable] — [isDirty] is re-read on every notify.
  const UnsavedLabel.listening({
    super.key,
    required this.listenable,
    required this.isDirty,
  });

  final Listenable listenable;

  /// True while the label should show. Fold "not saving" in here: the word
  /// must not sit beside a spinner.
  final bool Function() isDirty;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        if (!isDirty()) return const SizedBox.shrink();
        final tokens = context.inTheme;
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: InSpacing.sm),
          child: Semantics(
            liveRegion: true,
            child: Row(
              key: const ValueKey('unsaved-label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text in the warning ink on the bar, not on `warningSoft`:
                // that pair measures 4.2:1 in the light themes, short of AA
                // for text this small.
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: tokens.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: InSpacing.xs),
                Text(
                  context.tr('unsaved'),
                  maxLines: 1,
                  style: TextStyle(
                    color: tokens.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
