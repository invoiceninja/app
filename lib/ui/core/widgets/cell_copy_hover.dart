import 'package:material_ui/material_ui.dart';

import 'package:admin/app/env.dart';
import 'package:admin/domain/columns/column_definition.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';

/// Wraps a table cell with a hover-reveal copy icon.
///
/// When [value] is null or empty the wrapper is a no-op and the [child] is
/// rendered unchanged. Otherwise a small icon chip fades in on mouse hover
/// at the trailing edge (or leading edge for end-aligned cells, so it
/// doesn't overlap the right-justified value). Clicking the icon writes
/// [value] to the system clipboard and surfaces the standard
/// `copied_to_clipboard` snackbar (via [copyToClipboard]).
///
/// Mouse-only by default — `MouseRegion`'s `onEnter`/`onExit` never fire on
/// touch, so iOS/Android render the wrapper transparently with no extra
/// affordance. (Touch copy in detail screens is handled by [CopyableValue];
/// in an entity list a tap navigates to the row and a long-press starts
/// multi-select, so there's deliberately no mobile copy there.)
/// [touchLongPressCopies] opts a cell in where the long-press is free.
class CellCopyHover extends StatefulWidget {
  const CellCopyHover({
    super.key,
    required this.child,
    required this.value,
    this.valueFromChild = false,
    this.align = ColumnAlign.start,
    this.touchLongPressCopies = false,
  });

  final Widget child;
  final String? value;

  /// Take the copy value from the cell's own label instead of [value] — for
  /// a cell whose text is resolved after the row is built: a client's name
  /// behind a `clientId`, which arrives on the stream `ClientNameLabel`
  /// watches. The label reports the name it rendered through
  /// [CellCopyNameScope.report]; the hover is itself a build of this wrapper,
  /// so the icon appears with whatever the label has resolved by the time the
  /// pointer is over it, and not at all while it shows a dash. [value] (the
  /// id) is never copied.
  final bool valueFromChild;
  final ColumnAlign align;

  /// On touch, a long-press on the cell copies the value. For a table whose
  /// rows take a tap but not a long-press (a document's read-only line
  /// items) — never an entity list, whose long-press is multi-select.
  final bool touchLongPressCopies;

  @override
  State<CellCopyHover> createState() => _CellCopyHoverState();
}

class _CellCopyHoverState extends State<CellCopyHover> {
  bool _hovering = false;

  /// What the cell's label last reported ([CellCopyHover.valueFromChild]).
  late final CellCopyName _reported = CellCopyName(onChanged: _nameChanged);

  bool _rebuildScheduled = false;

  /// The label drew a different name. It says so from its own build, so the
  /// icon is refreshed after the frame, never during it — and only while the
  /// pointer is here, the one time the icon is on screen.
  void _nameChanged() {
    if (!_hovering || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CellCopyHover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different [value] is a different related record in this slot. A label
    // under it reports again; a cell that now holds no label (an empty id
    // draws a dash) must not keep the last row's name. Keyed on the id, not
    // on the child: `CellSlot` builds a fresh child on every parent rebuild,
    // and clearing then would hide the icon under a resting pointer.
    if (oldWidget.value != widget.value) _reported.clear();
  }

  String? get _value => widget.valueFromChild ? _reported.value : widget.value;

  @override
  Widget build(BuildContext context) {
    final fromChild = widget.valueFromChild;
    final child = fromChild
        ? CellCopyNameScope(name: _reported, child: widget.child)
        : widget.child;
    final value = _value;
    final hasValue = value != null && value.isNotEmpty;
    // Reading from the child, the hover region stays mounted while there is
    // nothing to copy yet: the name arrives without this widget being
    // rebuilt, and swapping the tree's shape when it does would remount the
    // label.
    if (!hasValue && !fromChild) return child;

    if (Env.isTouchPrimary && widget.touchLongPressCopies) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {
          final now = _value;
          if (now == null || now.isEmpty) return;
          copyToClipboard(context, now);
        },
        child: child,
      );
    }

    final isEnd = widget.align == ColumnAlign.end;

    return MouseRegion(
      onEnter: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: 0,
            bottom: 0,
            start: isEnd ? 0 : null,
            end: isEnd ? null : 0,
            child: IgnorePointer(
              ignoring: !_hovering || !hasValue,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 100),
                opacity: _hovering && hasValue ? 1.0 : 0.0,
                child: Center(
                  // Dense surface: keep Tab walking rows, not cells.
                  child: CopyIconButton(
                    value: value ?? '',
                    canRequestFocus: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The name a label is showing, as that label last reported it. Written
/// during the label's build and read during the hover's; [onChanged] tells the
/// owner a different name arrived, and is called *during a build* — the owner
/// must defer any `setState` past the frame.
class CellCopyName {
  CellCopyName({this.onChanged});

  final VoidCallback? onChanged;

  String? get value => _value;
  String? _value;

  /// A label reporting what it drew.
  void report(String? name) {
    if (name == _value) return;
    _value = name;
    onChanged?.call();
  }

  /// Forget the name without telling the owner — it is the one clearing.
  void clear() => _value = null;
}

/// Lets a `*NameLabel` tell the [CellCopyHover] around it what it rendered,
/// so the cell's copy icon copies the name on screen rather than the id the
/// row carries ([CellCopyHover.valueFromChild]).
class CellCopyNameScope extends InheritedWidget {
  const CellCopyNameScope({
    super.key,
    required this.name,
    required super.child,
  });

  final CellCopyName name;

  /// Called by a label from its build with the name it is drawing, or null
  /// when it draws a placeholder (unresolved, `(no name)`). A no-op outside a
  /// name-copying cell, and it registers no dependency.
  static void report(BuildContext context, String? name) {
    context.getInheritedWidgetOfExactType<CellCopyNameScope>()?.name.report(
      name,
    );
  }

  /// Whether a host above [context] collects the name — and so draws the
  /// copy affordance itself.
  static bool has(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CellCopyNameScope>() != null;

  @override
  bool updateShouldNotify(CellCopyNameScope oldWidget) => false;
}
