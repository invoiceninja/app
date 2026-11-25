import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// When the user last did something in the app — the one clock both the web's
/// idle sign-out (`IdleTimeoutController`) and the soft lock
/// (`SoftLockController`, docs/soft-lock.md) measure inactivity against.
///
/// Activity arrives from four sources, and only from the user:
///
/// * the root-level pointer `Listener` in `main.dart`, which calls [poke];
/// * every hardware key event ([HardwareKeyboard]);
/// * edits to the focused text field's `TextEditingController` — a soft
///   keyboard sends no key events, so typing a long note on a phone used to
///   count as idle;
/// * the `UserActivityNotification` a `MarkdownTextField` bubbles up to
///   `main.dart` for its `super_editor` document, which is not a
///   `TextEditingController` — `main.dart` calls [poke] for it.
///
/// Deliberately NOT the unsaved-changes guard, a running task timer, or the
/// company row re-emitting: none of those is the user, and each would keep an
/// unattended app awake (a timer runs exactly when nobody touches the app).
///
/// The two key/text sources are listened to only while some consumer has
/// called [attachSources] (ref-counted), so a build that enforces neither
/// timeout installs nothing.
class UserActivityTracker {
  UserActivityTracker({DateTime Function() now = DateTime.now}) : _now = now {
    _last = _now();
  }

  final DateTime Function() _now;
  late DateTime _last;

  final List<VoidCallback> _listeners = [];
  int _attached = 0;

  /// The focused text field's controller, listened to so each edit pokes.
  TextEditingController? _watchedText;

  /// The time of the last activity — or of construction, before any.
  DateTime get lastActivity => _last;

  /// The clock this tracker stamps with, for consumers measuring against it.
  DateTime now() => _now();

  /// Record user activity. Cheap — stamps the clock and tells the listeners;
  /// safe to call on every pointer event.
  void poke() {
    _last = _now();
    if (_listeners.isEmpty) return;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Called on every [poke]. Keep it cheap: pointer moves poke.
  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Start listening to hardware keys and the focused text field. Each call is
  /// matched by one [detachSources].
  void attachSources() {
    if (_attached++ > 0) return;
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_onFocusChanged);
    _onFocusChanged();
  }

  void detachSources() {
    if (_attached == 0) return;
    if (--_attached > 0) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_onFocusChanged);
    // Removing from a controller its owner already disposed is allowed.
    _watchedText?.removeListener(poke);
    _watchedText = null;
  }

  /// Every hardware key event is activity. Returns false so the event carries
  /// on to the shortcut layer and the focused field untouched.
  bool _onKey(KeyEvent _) {
    poke();
    return false;
  }

  /// Follow the primary focus to the [EditableText] it sits in (the focus
  /// node's context is below `EditableTextState`) and listen to that field's
  /// controller, so soft-keyboard typing — which produces no key events —
  /// still counts.
  void _onFocusChanged() {
    final next = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.widget
        .controller;
    if (identical(next, _watchedText)) return;
    _watchedText?.removeListener(poke);
    _watchedText = next;
    next?.addListener(poke);
  }

  /// Drops every source, whatever the count.
  void dispose() {
    if (_attached > 0) {
      _attached = 1;
      detachSources();
    }
    _listeners.clear();
  }
}
