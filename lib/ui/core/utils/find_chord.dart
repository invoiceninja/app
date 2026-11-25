import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:admin/ui/core/utils/text_input_focus.dart';

/// ⌘F / Ctrl+F — the find chord, shared by the two surfaces that answer it:
/// a record screen (`EntityDetailScaffold`, through `DetailFindNavigator`) and
/// a billing document's editor (`BillingDocEditLayout`). Both open find in
/// line items (`docs/find-in-line-items.md`).
class FindChordIntent extends Intent {
  const FindChordIntent();
}

/// ⌘F on Apple platforms, Ctrl+F elsewhere — one modifier each, never both:
/// ⌃F is Cocoa's forward-a-character inside a text field.
///
/// Build the map once per surface (a `late final` field), never in `build`:
/// a new `SingleActivator` has no `==`, so a map rebuilt every frame reads to
/// `ShortcutManager` as a change — a re-index and a notify from every rebuild.
Map<ShortcutActivator, Intent> findChordShortcuts() {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyF, meta: apple, control: !apple):
        const FindChordIntent(),
  };
}

/// Runs [onFind]. It fires from inside a text field too — it types nothing,
/// and pressed again in the find field it re-selects the query, as a
/// browser's does — but stands down mid leader sequence, and is disabled
/// (so the chord falls through) while [canFind] says there is nothing to
/// search.
class FindChordAction extends GuardedShortcutAction<FindChordIntent> {
  FindChordAction({required VoidCallback onFind, bool Function()? canFind})
    : _canFind = canFind ?? _always,
      super(
        onInvoke: (_) {
          onFind();
          return null;
        },
        firesInTextInput: () => true,
      );

  final bool Function() _canFind;

  static bool _always() => true;

  @override
  bool isEnabled(FindChordIntent intent) =>
      _canFind() && super.isEnabled(intent);

  @override
  bool consumesKey(FindChordIntent intent) =>
      _canFind() && super.consumesKey(intent);
}
