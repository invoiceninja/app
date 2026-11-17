import 'package:flutter/widgets.dart';

/// Open/closed state, query text and keyboard selection for the `/settings`
/// index search.
///
/// Lives outside `SettingsListSidebar` because the *field* and the *results*
/// don't share a parent. On narrow the field sits, always visible, in
/// `SettingsScreen`'s pinned AppBar — the search used to be the `trailing:` of
/// the in-list "Basic Settings" header, so it scrolled away (issue #42) — while
/// the results render in the list body below.
///
/// Ownership rule: **whoever creates the controller renders the field.** The
/// wide 280 px pane has no AppBar, so it creates its own and pins the field
/// above its list; `SettingsScreen` passes one down and owns the chrome itself.
class SettingsSearchController extends ChangeNotifier {
  SettingsSearchController() {
    query.addListener(_onQueryChanged);
  }

  /// The live query. A `Listenable` in its own right, so the results list binds
  /// to it directly and a keystroke rebuilds the hits and nothing else — the
  /// AppBar must not rebuild per character.
  final TextEditingController query = TextEditingController();
  final FocusNode focus = FocusNode(debugLabel: 'settings search');

  /// The keyboard-selected result row. Back to the top on every keystroke —
  /// the rows under it just changed.
  final ValueNotifier<int> selected = ValueNotifier<int>(0);

  /// How many rows the results list last rendered, for [moveSelection]'s
  /// wrap-around. Written by the list as it builds; deliberately not a
  /// notifier, since the list is its only reader and writer.
  int resultCount = 0;

  /// Opens the selected row. Set by whoever renders the results — the field
  /// that receives Enter doesn't know what the rows are.
  VoidCallback? onSubmit;

  bool get isActive => _isActive;
  bool _isActive = false;
  bool _disposed = false;
  String _lastQuery = '';

  void _onQueryChanged() {
    // The controller also notifies on caret moves; only a text change resets.
    if (query.text == _lastQuery) return;
    _lastQuery = query.text;
    selected.value = 0;
  }

  void open() {
    if (_disposed || _isActive) return;
    _isActive = true;
    notifyListeners();
    // Defer until the TextField is mounted. Explicit `requestFocus` rather than
    // `autofocus: true`: a `FocusScope` skips its autofocus request when
    // something in the scope already holds focus, and on desktop/web that is
    // exactly the IconButton the user just clicked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_isActive) return;
      focus.requestFocus();
    });
  }

  /// What the `/` shortcut does here: open the search, or put the caret back
  /// in a search that is already open.
  void activate() {
    if (_disposed) return;
    if (_isActive) {
      focus.requestFocus();
    } else {
      open();
    }
  }

  /// ↑ / ↓ in the field. Wraps at both ends, like the command palette.
  void moveSelection(int delta) {
    final n = resultCount;
    if (_disposed || n == 0) return;
    selected.value = (selected.value.clamp(0, n - 1) + delta) % n;
  }

  void submit() {
    if (_disposed) return;
    onSubmit?.call();
  }

  void close() {
    // A search hit's `onTap` awaits the unsaved-changes guard, navigates, and
    // only then closes — by which point a redirect may have disposed the host.
    if (_disposed) return;
    query.clear();
    if (!_isActive) return;
    _isActive = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    query.removeListener(_onQueryChanged);
    query.dispose();
    focus.dispose();
    selected.dispose();
    super.dispose();
  }
}
