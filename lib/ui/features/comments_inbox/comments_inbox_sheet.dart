import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/comments_inbox_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/router.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/activity.dart';
import 'package:admin/domain/activity/comment_reads.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/phone/call_note.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';
import 'package:admin/utils/formatting.dart';

/// Opens the comments inbox: teammates' recent comments, newest first, each
/// naming the record it was written on and opening it on a tap
/// (docs/comments-and-activity.md § A teammate's comment is new until you
/// have seen it).
///
/// Opening it is reading it: the comments new at this moment keep their "New"
/// for as long as it stays open, and the shell's count clears at once.
///
/// [context] should outlive a drawer — pass the root navigator's context when
/// opening from one, since the drawer is popped first. [openRecord] replaces
/// `goEntityRecord` in a test that has no router.
Future<void> showCommentsInbox(
  BuildContext context, {
  void Function(EntityType type, String id)? openRecord,
}) async {
  final inbox = context.read<CommentsInboxController?>();
  if (inbox == null) return;
  final formatter = context.read<Services?>()?.formatterIfReady(
    inbox.companyId,
  );
  final comments = inbox.comments;
  final fresh = {
    for (final c in comments)
      if (inbox.isUnread(c)) c.id,
  };
  inbox.markFeedSeen();

  void open(BuildContext sheetContext, Activity a) {
    final source = commentSourceRecord(a);
    final type = source?.ref.type;
    if (source == null || type == null) return;
    Navigator.of(sheetContext).pop();
    if (!context.mounted) return;
    if (openRecord != null) return openRecord(type, source.ref.id);
    goEntityRecord(context, type, source.ref.id);
  }

  Widget body(BuildContext ctx) => CommentsInboxList(
    comments: comments,
    freshIds: fresh,
    formatter: formatter,
    onOpen: (a) => open(ctx, a),
  );

  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<void>(
      context: context,
      anchorPoint: foldAnchorPoint(context),
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: math.min(640, MediaQuery.sizeOf(ctx).height * 0.9),
          ),
          child: body(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
      ),
      child: body(ctx),
    ),
  );
}

/// The inbox's content: a heading and the comments, or an empty state.
class CommentsInboxList extends StatelessWidget {
  const CommentsInboxList({
    super.key,
    required this.comments,
    required this.freshIds,
    required this.onOpen,
    this.formatter,
  });

  /// Newest first (`CommentsInboxController.comments`).
  final List<Activity> comments;

  /// The [Activity.id]s that were new when the inbox opened.
  final Set<String> freshIds;

  /// Opens the record a comment was written on.
  final ValueChanged<Activity> onOpen;

  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = InSpacing.lg(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(inset, inset, inset, 8),
          child: Semantics(
            header: true,
            headingLevel: 1,
            child: Text(
              context.tr('comments'),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: EmptyStateBody(
              icon: Icons.forum_outlined,
              title: context.tr('no_team_comments'),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              addAutomaticKeepAlives: false,
              padding: EdgeInsets.only(bottom: InSpacing.md(context)),
              itemCount: comments.length,
              itemBuilder: (context, i) {
                final c = comments[i];
                final source = commentSourceRecord(c);
                return CommentsInboxRow(
                  comment: c,
                  isNew: freshIds.contains(c.id),
                  formatter: formatter,
                  isLast: i == comments.length - 1,
                  onTap: source?.ref.type == null ? null : () => onOpen(c),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// One teammate's comment: who, on which record, what, and when.
class CommentsInboxRow extends StatelessWidget {
  const CommentsInboxRow({
    super.key,
    required this.comment,
    required this.isNew,
    required this.onTap,
    this.formatter,
    this.isLast = false,
  });

  final Activity comment;
  final bool isNew;

  /// Null for a comment whose record can't be opened — the row is then
  /// inert, with no chevron.
  final VoidCallback? onTap;
  final Formatter? formatter;
  final bool isLast;

  /// "Invoice 0012" for a document, the name alone for a client or vendor —
  /// the record the comment was written on, never the client it was copied
  /// to (§ A client's comment feed is mixed).
  static String sourceLabel(BuildContext context, Activity a) {
    final source = commentSourceRecord(a);
    if (source == null) return '';
    final label = source.ref.label.trim();
    if (source.token == 'client' || source.token == 'vendor') return label;
    return label.isEmpty
        ? context.tr(source.token)
        : '${context.tr(source.token)} $label';
  }

  String _when(BuildContext context) {
    final elapsed = DateTime.now().difference(comment.createdAt);
    if (elapsed.inHours < 24) return formatRelativeTime(context, elapsed);
    return formatter?.date(
          comment.createdAt.toLocal().toIso8601String().split('T').first,
        ) ??
        formatRelativeTime(context, elapsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final inset = InSpacing.lg(context);
    final (bg, fg) = activityToneColors(
      tokens,
      activityToneFor(comment.activityTypeId),
    );
    final author = (comment.userLabel ?? '').trim();
    final source = sourceLabel(context, comment);
    final text =
        (comment.isCallNote
                ? stripCallNoteMarker(comment.notes)
                : comment.notes)
            .trim();

    final headline = Text.rich(
      TextSpan(
        children: [
          if (isNew)
            TextSpan(
              text: '${context.tr('new')} · ',
              style: TextStyle(
                color: tokens.accentInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (author.isNotEmpty)
            TextSpan(
              text: author,
              style: TextStyle(color: tokens.ink, fontWeight: FontWeight.w600),
            ),
          if (source.isNotEmpty)
            TextSpan(
              text: author.isEmpty ? source : ' · $source',
              style: TextStyle(color: tokens.ink2),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );

    Widget content = Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: tokens.border)),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(inset, 12, inset, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(InRadii.r2),
            ),
            child: Icon(
              comment.isCallNote
                  ? Icons.phone_in_talk_outlined
                  : Icons.comment_outlined,
              size: 16,
              color: fg,
            ),
          ),
          SizedBox(width: InSpacing.md(context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headline,
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  _when(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.ink3,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(Icons.chevron_right, size: 16, color: tokens.ink3),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    // Transparency on a local Material, so the ink paints over the sheet's
    // surface rather than under it (the `Ink` ban's mechanism).
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
