import 'dart:async';

import 'package:flutter/widgets.dart';

/// Where a dragged kanban card's pointer is, ticking while the drag lasts.
///
/// A drag cannot scroll a list by itself, so without this a card could only
/// reach what was already on screen — on a phone, its own column. The board
/// owns one, every card's drag reports to it, and each scrollable that should
/// follow the pointer (the board sideways, a column or the lanes up and down)
/// listens and calls [scroll] on every tick.
class KanbanDragScroller extends ChangeNotifier {
  /// The pointer's global position, or null when nothing is being dragged.
  Offset? get position => _position;
  Offset? _position;

  Timer? _ticker;

  void update(Offset global) {
    _position = global;
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => notifyListeners(),
    );
  }

  void end() {
    _position = null;
    _ticker?.cancel();
    _ticker = null;
  }

  /// Width of the band along an edge where the pointer scrolls, and the
  /// distance one tick covers at the very edge.
  static const double band = 56;
  static const double step = 14;

  /// −1…1: how hard the pointer at [at] along a viewport of [extent] is
  /// pushing towards its start (negative) or end. Zero outside both bands.
  static double edgeVelocity(double at, double extent) {
    if (at < band) return (-(band - at) / band).clamp(-1.0, 0.0);
    if (at > extent - band) {
      return ((at - (extent - band)) / band).clamp(0.0, 1.0);
    }
    return 0;
  }

  /// One tick of edge scrolling for the vertical list drawn by [box]. Does
  /// nothing unless the pointer is over [box].
  void scroll(ScrollController controller, RenderObject? box) {
    final at = _position;
    if (at == null || !controller.hasClients) return;
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final local = box.globalToLocal(at);
    if (local.dx < 0 || local.dx > box.size.width) return;
    if (local.dy < -band || local.dy > box.size.height + band) return;
    final v = edgeVelocity(local.dy, box.size.height);
    if (v == 0) return;
    final p = controller.position;
    final next = (p.pixels + v * step).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (next != p.pixels) controller.jumpTo(next);
  }

  @override
  void dispose() {
    end();
    super.dispose();
  }
}
