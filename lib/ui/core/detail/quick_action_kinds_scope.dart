import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Which actions a record screen's quick-action strip (`EntityQuickActions`)
/// is showing as tiles, for the header's action bar to leave under More.
///
/// On a wide record screen the bar spread every action that fit, so View
/// Statement and Client Portal were on screen twice: as a tile and as a bar
/// button a few pixels above it. The tiles are the place for them; the bar
/// keeps them in More, where they are still within reach once the tiles have
/// scrolled away.
///
/// The strip publishes after its frame, never during build: the header is
/// another subtree, and notifying it mid-build is the crash
/// `ShortcutHintController` once hit. The bar takes them one frame later.
class QuickActionKinds extends ChangeNotifier {
  Set<Object?> _kinds = const {};

  /// What the bar leaves under More: the tiled kinds, and the kinds whose
  /// result is already on screen (`EntityQuickAction.onScreen` — the PDF
  /// beside a billing document).
  Set<Object?> get kinds => _kinds;

  /// [tiled] are the strip's tiles; [onScreen] the kinds no button should
  /// offer, because what they open is already showing.
  void publish(Set<Object?> tiled, {Set<Object?> onScreen = const {}}) {
    final kinds = onScreen.isEmpty ? tiled : {...tiled, ...onScreen};
    if (setEquals(kinds, _kinds)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (setEquals(kinds, _kinds)) return;
      _kinds = kinds;
      notifyListeners();
    });
  }
}

/// Puts a [QuickActionKinds] above a record screen's header and body.
class QuickActionKindsScope extends InheritedNotifier<QuickActionKinds> {
  const QuickActionKindsScope({
    super.key,
    required QuickActionKinds super.notifier,
    required super.child,
  });

  /// The kinds the strip shows, subscribing; empty outside a record screen.
  static Set<Object?> watch(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<QuickActionKindsScope>()
          ?.notifier
          ?.kinds ??
      const {};

  /// The notifier to publish to, without subscribing.
  static QuickActionKinds? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<QuickActionKindsScope>()?.notifier;
}
