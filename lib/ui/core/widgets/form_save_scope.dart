import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Provides the surrounding form's save callback to descendant fields so a
/// single-line `TextField` can submit the form when the user presses Enter.
///
/// Wrap an edit/settings screen body in `FormSaveScope` and reusable field
/// widgets (e.g. `OverridableTextField`) pick up the callback through their
/// `onSubmitted` automatically — no prop drilling. Multi-line fields should
/// keep Enter for newlines, so they ignore the scope.
class FormSaveScope extends InheritedWidget {
  const FormSaveScope({
    super.key,
    required this.onSubmit,
    this.enabled = true,
    required super.child,
  });

  final VoidCallback onSubmit;

  /// When false, [trySubmit] is a no-op. Mirror the screen's `canSave` flag
  /// so Enter doesn't fire saves while the form is busy or invalid.
  final bool enabled;

  static FormSaveScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormSaveScope>();

  void trySubmit() {
    if (!enabled) return;
    // A held Enter repeats, and each repeat submits the field again — one
    // save per repeat now that Save is always enabled. Only the press
    // submits; a repeat of it is ignored until the key comes back up. A
    // submit with no Enter held (a soft keyboard's Done) always goes.
    if (_enterHeld()) {
      if (_submittedThisPress) return;
      _submittedThisPress = true;
      _watchRelease();
    }
    onSubmit();
  }

  static bool _submittedThisPress = false;
  static bool _watching = false;

  static bool _enterHeld() {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isPhysicalKeyPressed(PhysicalKeyboardKey.enter) ||
        keyboard.isPhysicalKeyPressed(PhysicalKeyboardKey.numpadEnter);
  }

  static void _watchRelease() {
    if (_watching) return;
    _watching = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent && !_enterHeld()) _submittedThisPress = false;
    return false;
  }

  @override
  bool updateShouldNotify(FormSaveScope oldWidget) =>
      oldWidget.onSubmit != onSubmit || oldWidget.enabled != enabled;
}
