import 'dart:async';

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// The one place in `lib/` that reads `MediaQuery.displayFeatures` — a
/// foldable's fold or hinge (docs/foldables.md). `fold_geometry_lint_test`
/// holds that line.
///
/// Three pieces:
///  * [separatingFold], a pure read of one `MediaQueryData`, built on the same
///    rule Material's dialogs use ([DisplayFeatureSubScreen.avoidBounds] —
///    a feature with area, or a half-open fold), so our layout and Material's
///    sub-screens never disagree about where the fold is;
///  * [FoldPostureHost], which debounces **book posture** (a half-open device
///    with a vertical fold) so the split doesn't flash while a phone is being
///    opened through half-open, and publishes it through [FoldPostureScope];
///  * [rebaseDisplayFeatures], which the shell uses to move the features into
///    its content layer's coordinates, past the rail.
///
/// Book posture lights up on Android today. On iOS it waits on Flutter
/// reporting the iPhone Duo's hinge (flutter/flutter#193025); until then
/// `displayFeatures` is empty there and none of this does anything.

/// Which way a fold runs. A vertical fold splits the window into a left and a
/// right half (book posture); a horizontal one into top and bottom (tabletop).
enum FoldAxis { vertical, horizontal }

/// A fold that runs the full height (or width) of the window, splitting it in
/// two. Every rect is in the coordinates of the `MediaQuery` it was read from.
///
/// [start] / [end] are **physical** — left / right for a vertical fold — never
/// directional: the fold is a physical feature of the device, so a right-to-
/// left locale mirrors what goes in each half, not where the halves are.
@immutable
class FoldSplit {
  const FoldSplit({
    required this.axis,
    required this.fold,
    required this.start,
    required this.end,
  });

  final FoldAxis axis;

  /// The fold itself — on an iPhone Duo a 40 pt band, on most Android
  /// foldables a zero-width line.
  final Rect fold;

  /// The half before the fold: left of a vertical one, above a horizontal one.
  final Rect start;

  /// The half after the fold: right of a vertical one, below a horizontal one.
  final Rect end;

  @override
  bool operator ==(Object other) =>
      other is FoldSplit &&
      other.axis == axis &&
      other.fold == fold &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(axis, fold, start, end);

  @override
  String toString() => 'FoldSplit($axis, fold: $fold)';
}

/// The fold in [data] that splits the window in two, or null.
///
/// A feature counts when Material's sub-screens would avoid it (it has area,
/// or it is a fold in its half-open posture) **and** it spans the whole window
/// on one axis — a camera cutout has area too, but splits nothing.
FoldSplit? separatingFold(MediaQueryData data) {
  final window = Offset.zero & data.size;
  for (final bounds in DisplayFeatureSubScreen.avoidBounds(data)) {
    final spansHeight =
        bounds.top <= window.top && bounds.bottom >= window.bottom;
    final spansWidth =
        bounds.left <= window.left && bounds.right >= window.right;
    // rtl: physical — a fold is where it is on the device.
    if (spansHeight &&
        bounds.left > window.left &&
        bounds.right < window.right) {
      return FoldSplit(
        axis: FoldAxis.vertical,
        fold: bounds,
        start: Rect.fromLTRB(
          window.left,
          window.top,
          bounds.left,
          window.bottom,
        ),
        end: Rect.fromLTRB(
          bounds.right,
          window.top,
          window.right,
          window.bottom,
        ),
      );
    }
    if (spansWidth &&
        bounds.top > window.top &&
        bounds.bottom < window.bottom) {
      return FoldSplit(
        axis: FoldAxis.horizontal,
        fold: bounds,
        start: Rect.fromLTRB(window.left, window.top, window.right, bounds.top),
        end: Rect.fromLTRB(
          window.left,
          bounds.bottom,
          window.right,
          window.bottom,
        ),
      );
    }
  }
  return null;
}

/// [data] with every display feature moved [dx] logical pixels along x.
///
/// The shell's content layer starts past the rail, while `displayFeatures`
/// are in window coordinates. Everything under the content — the master-
/// detail split, a sheet's `DisplayFeatureSubScreen` on a nested navigator, a
/// menu on the nested overlay — measures itself from the content's origin, so
/// the shell re-bases the features there (`dx` = minus the rail's physical
/// left offset). `size` is deliberately left as the window: `Breakpoints`
/// reads it as the window, and a sub-screen computed against it still lands on
/// the right side of the fold (docs/foldables.md).
MediaQueryData rebaseDisplayFeatures(MediaQueryData data, double dx) {
  if (dx == 0 || data.displayFeatures.isEmpty) return data;
  return data.copyWith(
    displayFeatures: [
      for (final f in data.displayFeatures)
        DisplayFeature(
          bounds: f.bounds.shift(Offset(dx, 0)),
          type: f.type,
          state: f.state,
        ),
    ],
  );
}

/// The `MediaQuery` for one half of a split at a fold: the fold gone (each half
/// is a whole screen to what it holds — a sheet on its navigator fills it, and
/// nothing in it splits again), and the side safe-area insets kept only on the
/// edges the half actually touches. [half] and [boxWidth] are in the split's
/// own box; [data] is the box's `MediaQuery` (the shell's content layer).
///
/// Not `MediaQueryData.removeDisplayFeatures`: that measures the half against
/// `data.size`, the window, while the box starts past the rail — it would
/// drop the right-hand inset of a half that does reach the right edge.
MediaQueryData foldHalfMediaQuery(
  MediaQueryData data,
  Rect half,
  double boxWidth,
) {
  final touchesLeft = half.left <= 0;
  final touchesRight = half.right >= boxWidth;
  // rtl: physical — safe-area insets are physical edges of the screen.
  EdgeInsets sides(EdgeInsets e) => EdgeInsets.only(
    left: touchesLeft ? e.left : 0,
    top: e.top,
    right: touchesRight ? e.right : 0,
    bottom: e.bottom,
  );
  return data.copyWith(
    padding: sides(data.padding),
    viewPadding: sides(data.viewPadding),
    displayFeatures: [
      for (final f in data.displayFeatures)
        if (half.overlaps(f.bounds)) f,
    ],
  );
}

/// [child] as one half of a split at a fold ([foldHalfMediaQuery]) when
/// [half] is set, and unchanged otherwise — always under a `MediaQuery`, so a
/// fold coming and going never changes the tree's shape (and never remounts
/// what is inside).
class FoldHalf extends StatelessWidget {
  const FoldHalf({
    super.key,
    required this.half,
    required this.boxWidth,
    required this.child,
  });

  /// The half within the split's box, or null when nothing is split.
  final Rect? half;
  final double boxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final half = this.half;
    return MediaQuery(
      data: half == null ? data : foldHalfMediaQuery(data, half, boxWidth),
      child: child,
    );
  }
}

/// Where a dialog opened from [context] should anchor on a folded screen: the
/// caller's centre in window coordinates, so `showDialog`'s
/// `DisplayFeatureSubScreen` opens it in the half it came from. Null only for a
/// context that is gone (a call after an `await`) or not laid out.
///
/// Returned with no fold too — Material ignores it there — because the
/// sub-screen is chosen again whenever the display features change: a dialog
/// opened while the device was flat jumped to the list's half the moment it
/// was half-opened, when it had no anchor to stay by.
///
/// Without it every dialog opens in the start half: in a book-posture split
/// that is the list, so a delete confirmation for the record in the end half
/// came up over the list (docs/foldables.md). For a **root-navigator** dialog
/// (`showDialog`'s default); a sheet on a nested navigator needs nothing,
/// because each half of the split is its own screen.
Offset? foldAnchorPoint(BuildContext context) {
  if (!context.mounted) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(box.size.center(Offset.zero));
}

/// Publishes whether the device is in **book posture** — a vertical fold that
/// splits the window: half-open, or a hinge with width even when flat (the
/// same features Material's dialogs avoid) — debounced by [FoldPostureHost].
class FoldPostureScope extends InheritedWidget {
  const FoldPostureScope({
    super.key,
    required this.bookPosture,
    required super.child,
  });

  final bool bookPosture;

  /// False with no host above (tests, routes outside the shell).
  static bool bookPostureOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FoldPostureScope>()
          ?.bookPosture ??
      false;

  @override
  bool updateShouldNotify(FoldPostureScope oldWidget) =>
      oldWidget.bookPosture != bookPosture;
}

/// The vertical fold the layout under [context] should split at, or null.
///
/// Null unless the debounced [FoldPostureScope] says book posture **and** the
/// local `MediaQuery` still has a vertical separating fold — so the rect is
/// always current (and in the local, re-based coordinates), while the on/off
/// decision is the debounced one.
FoldSplit? bookFoldOf(BuildContext context) {
  if (!FoldPostureScope.bookPostureOf(context)) return null;
  final split = separatingFold(foldMediaOf(context));
  return split?.axis == FoldAxis.vertical ? split : null;
}

/// Just the two things a fold is measured from — the window size and the
/// display features — read as `MediaQuery` aspects, so a caller is rebuilt
/// when either changes and not, say, on every frame of the keyboard sliding up
/// (which changes only `viewInsets`).
MediaQueryData foldMediaOf(BuildContext context) => MediaQueryData(
  size: MediaQuery.sizeOf(context),
  displayFeatures: MediaQuery.displayFeaturesOf(context),
);

/// Each display feature under [context] as `<type> <state> <w>×<h>` (e.g.
/// `fold postureHalfOpened 0×2208`), for the Debug Panel's App info tab — so
/// it can show what the device reports without reading the features itself.
/// Empty with no fold, hinge or cutout.
List<String> describeDisplayFeatures(BuildContext context) => [
  for (final f in MediaQuery.displayFeaturesOf(context))
    '${f.type.name} ${f.state.name} '
        '${f.bounds.width.round()}×${f.bounds.height.round()}',
];

/// Debounces book posture and publishes it through [FoldPostureScope].
///
/// Entering waits for [settle] of an unchanged half-open vertical fold: a
/// phone being opened passes through half-open on its way to flat, and a hand
/// adjusting the angle crosses the threshold more than once — without the wait
/// the split would flash on and off. Leaving is immediate, because there is no
/// fold left to lay out around.
///
/// [onChanged] fires (outside build) when the debounced value changes; the
/// shell uses it to collapse the rail.
class FoldPostureHost extends StatefulWidget {
  const FoldPostureHost({
    super.key,
    required this.child,
    this.onChanged,
    this.settle = const Duration(milliseconds: 300),
  });

  final Widget child;
  final ValueChanged<bool>? onChanged;
  final Duration settle;

  @override
  State<FoldPostureHost> createState() => _FoldPostureHostState();
}

class _FoldPostureHostState extends State<FoldPostureHost> {
  bool _book = false;
  Timer? _enter;
  FoldSplit? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final split = separatingFold(foldMediaOf(context));
    final raw = split?.axis == FoldAxis.vertical ? split : null;
    if (raw == null) {
      _enter?.cancel();
      _enter = null;
      _pending = null;
      if (_book) _set(false, inBuild: true);
      return;
    }
    if (_book) return;
    // A new or moved fold restarts the wait.
    if (_pending == raw && _enter != null) return;
    _pending = raw;
    _enter?.cancel();
    _enter = Timer(widget.settle, () {
      _enter = null;
      if (mounted && _pending != null) _set(true, inBuild: false);
    });
  }

  void _set(bool book, {required bool inBuild}) {
    if (inBuild) {
      // Called from didChangeDependencies, which runs inside the build that
      // will read [_book] — so assign, don't setState.
      _book = book;
      final onChanged = widget.onChanged;
      if (onChanged != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(book));
      }
      return;
    }
    setState(() => _book = book);
    widget.onChanged?.call(book);
  }

  @override
  void dispose() {
    _enter?.cancel();
    // The shell going away (a sign-out) mid-posture must not leave the rail
    // held collapsed for the next one. After the frame: listeners rebuild.
    final onChanged = widget.onChanged;
    if (_book && onChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(false));
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FoldPostureScope(bookPosture: _book, child: widget.child);
}

/// Debug-only: lays a vertical half-open fold down the middle of the window,
/// so the book-posture layout can be reviewed where no device reports one —
/// iOS (until Flutter reports the iPhone Duo's hinge), iPad, desktop, web.
/// Wired from Debug Panel → Simulate fold, through `MaterialApp.builder`.
class FoldSimulator extends StatelessWidget {
  const FoldSimulator({
    super.key,
    required this.enabled,
    required this.child,
    this.foldWidth = 40,
  });

  final bool enabled;
  final Widget child;

  /// The iPhone Duo's division is 40 pt.
  final double foldWidth;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    // Always a MediaQuery, so toggling it never remounts the app below.
    if (!enabled) return MediaQuery(data: data, child: child);
    final mid = data.size.width / 2;
    return MediaQuery(
      data: data.copyWith(
        displayFeatures: [
          ...data.displayFeatures,
          DisplayFeature(
            // rtl: physical — a fold is where it is on the device.
            bounds: Rect.fromLTWH(
              mid - foldWidth / 2,
              0,
              foldWidth,
              data.size.height,
            ),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      ),
      child: child,
    );
  }
}
