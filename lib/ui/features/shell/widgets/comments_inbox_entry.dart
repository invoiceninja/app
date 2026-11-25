import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/comments_inbox_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/features/comments_inbox/comments_inbox_sheet.dart';
import 'package:admin/ui/features/shell/widgets/sidebar_nav_item.dart';

/// The sidebar's comments inbox row: teammates' new comments, counted, and
/// the inbox one tap away (docs/comments-and-activity.md § A teammate's
/// comment is new until you have seen it).
///
/// Pinned chrome like Outbox, and like Outbox it renders **nothing** while
/// there is nothing to count — a zero is no badge and no row. That keeps the
/// pinned block's height where it was for everyone without news, and it means
/// non-admins (whose feed never holds a teammate's comment) never see it.
class CommentsInboxSidebarRow extends StatelessWidget {
  const CommentsInboxSidebarRow({
    super.key,
    required this.compact,
    required this.touch,
    this.onBeforeModal,
  });

  final bool compact;
  final bool touch;

  /// Pops the mobile drawer before the inbox opens over it.
  final VoidCallback? onBeforeModal;

  @override
  Widget build(BuildContext context) {
    final inbox = context.read<CommentsInboxController?>();
    if (inbox == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final count = inbox.unreadCount;
        if (count == 0) return const SizedBox.shrink();
        return SidebarNavItem(
          label: context.tr('comments'),
          icon: Icons.mark_chat_unread_outlined,
          active: false,
          selection: SidebarNavSelection.neutral,
          compact: compact,
          touch: touch,
          count: count,
          countLabel: context.tr('new'),
          onTap: () {
            // The root navigator's context outlives the drawer this row may
            // sit in, which `onBeforeModal` pops.
            final root = Navigator.of(context, rootNavigator: true).context;
            onBeforeModal?.call();
            showCommentsInbox(root);
          },
        );
      },
    );
  }
}

/// The phone's way to hear about it: a dot on the menu button while the
/// drawer holds a [CommentsInboxSidebarRow] with a count — the dot
/// `FilterIconButton` wears for an active filter, in the accent ink.
class CommentsInboxDot extends StatelessWidget {
  const CommentsInboxDot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inbox = context.read<CommentsInboxController?>();
    if (inbox == null) return child;
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          child!,
          if (inbox.unreadCount > 0)
            PositionedDirectional(
              end: -1,
              top: -1,
              // Labelled, so the menu button reads "Menu, 2 new" rather than
              // hiding the news from a screen reader.
              child: Semantics(
                label: context.tr('comments_new_count', {
                  'count': '${inbox.unreadCount}',
                }),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    // Accent ink, not the accent: the accent may be white.
                    color: context.inTheme.accentInk,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}
