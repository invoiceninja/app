import 'package:flutter/widgets.dart';

/// Lets `EntityDetailScaffold`'s ⌘F / Ctrl+F open a find that lives in the
/// record's body, without the scaffold knowing what there is to find.
///
/// The same shape as `DetailTabNavigator`, for the same reason: the key has
/// to be bound in the scaffold's `Shortcuts` map (its focus owner is the node
/// a key reaches from), but the thing it drives — the billing documents' find
/// in line items — is built several layers down. A body binds itself on mount
/// and unbinds on dispose; on a screen nothing bound, the chord falls through.
class DetailFindNavigator {
  VoidCallback? _find;

  /// Whether a body has bound a find. The scaffold reads this so the chord is
  /// left alone on a record with nothing to search.
  bool get hasFind => _find != null;

  void bind(VoidCallback find) => _find = find;

  /// Only clears the binding it was handed: when a body is replaced, the new
  /// one binds before the old one's `dispose` runs.
  void unbind(VoidCallback find) {
    if (_find == find) _find = null;
  }

  void find() => _find?.call();
}

/// Publishes the scaffold's [DetailFindNavigator] to the body below it.
class DetailFindNavigatorScope extends InheritedWidget {
  const DetailFindNavigatorScope({
    super.key,
    required this.navigator,
    required super.child,
  });

  final DetailFindNavigator navigator;

  /// Non-subscribing: the navigator never changes for the scaffold's lifetime.
  static DetailFindNavigator? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<DetailFindNavigatorScope>()
      ?.navigator;

  @override
  bool updateShouldNotify(DetailFindNavigatorScope oldWidget) =>
      !identical(oldWidget.navigator, navigator);
}
