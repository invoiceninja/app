import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/data/models/domain/task.dart';
import 'package:admin/ui/features/tasks/widgets/kanban/kanban_drag_scroller.dart';
import 'package:material_ui/material_ui.dart';

/// Space under every card, and the gap a drop indicator is drawn in.
const double kKanbanCardGap = 8;

/// One card's place on the board: the card, its drag, and the drop target
/// that means "above this card". Shared by a column's list and a lane's cell.
///
/// A card drags whole — at once with a mouse (a mouse drag scrolls nothing),
/// on a long press under a finger (where a plain drag is the scroll).
class KanbanCardSlot extends StatelessWidget {
  const KanbanCardSlot({
    super.key,
    required this.task,
    required this.card,
    required this.ghost,
    this.width,
    this.canDrag = true,
    this.onDropAbove,
    this.accepts,
    this.scroller,
  });

  final Task task;
  final Widget card;

  /// The card as it rides under the pointer: no timer button, no menu.
  final Widget ghost;

  /// The resting card's width, for the ghost (which is laid out in the
  /// Overlay). Null measures it — which a caller under an intrinsic-height
  /// pass must not rely on.
  final double? width;

  final bool canDrag;

  /// Called with the card dropped on this one. Null makes this no target.
  final ValueChanged<Task>? onDropAbove;

  /// Narrows which dragged cards may land here (a lane takes only its own).
  final bool Function(Task dragged)? accepts;

  final KanbanDragScroller? scroller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    Widget child = card;
    if (canDrag) {
      child = width != null
          ? _draggable(width!)
          : LayoutBuilder(builder: (context, c) => _draggable(c.maxWidth));
    }
    if (onDropAbove != null) {
      final draggable = child;
      child = DragTarget<Task>(
        onWillAcceptWithDetails: (d) =>
            d.data.id != task.id && (accepts?.call(d.data) ?? true),
        onAcceptWithDetails: (d) => onDropAbove!(d.data),
        builder: (context, candidate, rejected) {
          if (candidate.isEmpty) return draggable;
          // "Lands above this card": an accent bar in the gap over it.
          return Stack(
            clipBehavior: Clip.none,
            children: [
              draggable,
              Positioned(
                left: 0,
                right: 0,
                top: -(kKanbanCardGap + 3) / 2,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: kKanbanCardGap),
      child: child,
    );
  }

  Widget _draggable(double ghostWidth) {
    final feedback = Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.9,
        child: SizedBox(width: ghostWidth, child: ghost),
      ),
    );
    final resting = Opacity(opacity: 0.35, child: card);
    void update(DragUpdateDetails d) => scroller?.update(d.globalPosition);
    void end(DraggableDetails _) => scroller?.end();
    void cancel(Velocity _, Offset _) => scroller?.end();
    if (Env.isTouchPrimary) {
      return LongPressDraggable<Task>(
        data: task,
        feedback: feedback,
        childWhenDragging: resting,
        onDragUpdate: update,
        onDragEnd: end,
        onDraggableCanceled: cancel,
        child: card,
      );
    }
    return Draggable<Task>(
      data: task,
      feedback: feedback,
      childWhenDragging: resting,
      onDragUpdate: update,
      onDragEnd: end,
      onDraggableCanceled: cancel,
      child: card,
    );
  }
}
