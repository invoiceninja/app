import 'package:flutter/widgets.dart';

/// Closes the route it sits in when the window changes size.
///
/// For a popup placed at a **global position captured when it opened** — the
/// sidebar's theme menu and company picker, anchored to a rail button. A
/// foldable opening or closing (or a desktop window being resized) moves or
/// removes that anchor: the rail becomes a drawer below `Breakpoints.wide`, so
/// the popup would float at coordinates that no longer point at anything. A
/// desktop OS closes a menu on a resize for the same reason (docs/foldables.md).
///
/// Only a change of `MediaQuery.size` counts — the keyboard coming up changes
/// `viewInsets`, not the size, and must not close anything.
class DismissOnWindowResize extends StatefulWidget {
  const DismissOnWindowResize({super.key, required this.child});

  final Widget child;

  @override
  State<DismissOnWindowResize> createState() => _DismissOnWindowResizeState();
}

class _DismissOnWindowResizeState extends State<DismissOnWindowResize> {
  Size? _openedAt;
  bool _dismissing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final openedAt = _openedAt;
    if (openedAt == null) {
      _openedAt = size;
      return;
    }
    if (size == openedAt || _dismissing) return;
    _dismissing = true;
    // Not during build: popping here would mutate the navigator mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final navigator = route?.navigator;
      if (route == null || navigator == null || !route.isActive) return;
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
