import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:admin/app/search_focus_registry.dart';
import 'package:admin/ui/core/utils/text_input_focus.dart';

/// ⌘F / Ctrl+F — the find chord, shared by the surfaces that answer it: a
/// record screen (`EntityDetailScaffold`, through `DetailFindNavigator`) and a
/// billing document's editor (`BillingDocEditLayout`) open find in line items
/// (`docs/find-in-line-items.md`); anywhere else the shell focuses the screen's
/// search field (`ScaffoldWithNav`, with an intent of its own).
class FindChordIntent extends Intent {
  const FindChordIntent();
}

/// ⌘F on Apple platforms, Ctrl+F elsewhere — one modifier each, never both:
/// ⌃F is Cocoa's forward-a-character inside a text field.
///
/// [intent] defaults to [FindChordIntent]. The shell's fallback passes its own:
/// `Actions` resolves an intent from the focused node upward, so a shell
/// binding to [FindChordIntent] would find a record's disabled find action
/// again instead of its own.
///
/// Build the map once per surface (a `late final` field), never in `build`:
/// a new `SingleActivator` has no `==`, so a map rebuilt every frame reads to
/// `ShortcutManager` as a change — a re-index and a notify from every rebuild.
Map<ShortcutActivator, Intent> findChordShortcuts({
  Intent intent = const FindChordIntent(),
}) {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyF, meta: apple, control: !apple):
        intent,
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

/// The shell's ⌘F / Ctrl+F: focus the on-stage search field, as `/` does.
/// Bound in `ScaffoldWithNav` above every record and editor, so a find in line
/// items lower down wins wherever it is enabled. A distinct intent from
/// [FindChordIntent] — see [findChordShortcuts].
class FindFocusSearchIntent extends Intent {
  const FindFocusSearchIntent();
}

/// Runs [SearchFocusRegistry.activate]. Fires from inside a text field (the
/// chord types nothing), and is disabled — so the key falls through, to the
/// browser on the web — while no search field is on stage, or while the focus
/// is in another route of the search field's navigator
/// ([focusIsInAnotherRoute]): a bottom sheet over a list, where the list's
/// field stays registered, and focusing it would put the typing behind the
/// sheet's barrier.
class FindFocusSearchAction
    extends GuardedShortcutAction<FindFocusSearchIntent> {
  FindFocusSearchAction(SearchFocusRegistry registry)
    : _registry = registry,
      super(
        onInvoke: (_) {
          registry.activate();
          return null;
        },
        firesInTextInput: () => true,
      );

  final SearchFocusRegistry _registry;

  bool get _hasTarget {
    final node = _registry.current;
    return node != null &&
        !focusIsInAnotherRoute(node, FocusManager.instance.primaryFocus);
  }

  @override
  bool isEnabled(FindFocusSearchIntent intent) =>
      _hasTarget && super.isEnabled(intent);

  @override
  bool consumesKey(FindFocusSearchIntent intent) =>
      _hasTarget && super.consumesKey(intent);
}

/// Whether [focus] is inside a route of [search]'s navigator other than the
/// one [search] is in — a sheet or another page pushed over it. Focus above
/// that navigator (the shell's own node, the navigator's scope), in a route
/// nested inside the field's (a master-detail pane), or anywhere else is not.
///
/// Read off the focus tree, never `ModalRoute.of`: that would subscribe the
/// search field to its route, and a field re-runs its registry claim in
/// `didChangeDependencies`, so a sheet opening would reorder the registry. A
/// route's `FocusScope` is a direct child of its navigator's scope.
bool focusIsInAnotherRoute(FocusNode search, FocusNode? focus) {
  final context = search.context;
  if (focus == null || context == null) return false;
  final navigatorScope = context
      .findAncestorStateOfType<NavigatorState>()
      ?.focusNode;
  if (navigatorScope == null || identical(focus, navigatorScope)) {
    return false;
  }
  FocusNode? routeScope;
  for (final ancestor in search.ancestors) {
    if (identical(ancestor.parent, navigatorScope)) {
      routeScope = ancestor;
      break;
    }
  }
  if (routeScope == null) return false;
  final chain = [focus, ...focus.ancestors];
  return chain.contains(navigatorScope) && !chain.contains(routeScope);
}
