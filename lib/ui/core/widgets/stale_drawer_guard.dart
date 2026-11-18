import 'package:material_ui/material_ui.dart';

/// Wraps a `Scaffold.drawer` so a drawer taken away while open comes back
/// closed.
///
/// A foldable opening while the drawer is out removes the drawer — each
/// top-level screen passes `drawer: globalNav ? null : const AppDrawer()` — but
/// its `Scaffold` keeps believing it is open, and `closeDrawer()` is a no-op
/// once there is no drawer. Folding closed again brought the drawer back
/// already open (docs/foldables.md).
///
/// The tell is the guard being **disposed while its Scaffold says "open"**: a
/// normal close disposes it only after the close finished (a closed
/// `DrawerController` stops building its child). That Scaffold is remembered,
/// and the next guard mounted under it closes the drawer it comes back as.
/// "Mounted while open" alone would not do — opening a drawer is exactly what
/// mounts it. A workaround for material_ui's `Scaffold`: `docs/upstream-workarounds.md`
/// entry 29.
class StaleDrawerGuard extends StatefulWidget {
  const StaleDrawerGuard({super.key, required this.child});

  final Widget child;

  @override
  State<StaleDrawerGuard> createState() => _StaleDrawerGuardState();
}

/// Scaffolds whose drawer was removed while open. Weak, so a Scaffold that
/// goes away takes its entry with it.
final Expando<bool> _removedWhileOpen = Expando<bool>('removedWhileOpen');

class _StaleDrawerGuardState extends State<StaleDrawerGuard> {
  ScaffoldState? _scaffold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaffold = Scaffold.maybeOf(context);
    if (identical(scaffold, _scaffold)) return;
    _scaffold = scaffold;
    if (scaffold == null || _removedWhileOpen[scaffold] != true) return;
    _removedWhileOpen[scaffold] = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scaffold = _scaffold;
      if (scaffold != null && scaffold.mounted && scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
      }
    });
  }

  @override
  void dispose() {
    final scaffold = _scaffold;
    if (scaffold != null && scaffold.mounted && scaffold.isDrawerOpen) {
      _removedWhileOpen[scaffold] = true;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
