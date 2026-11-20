import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/db/dao/outbox_dao.dart';
import 'package:admin/data/models/domain/design.dart';
import 'package:admin/data/models/domain/document.dart';
import 'package:admin/data/services/api_exception.dart';
import 'package:admin/data/services/run_template_api.dart';
import 'package:admin/domain/run_template.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/list/entity_list_screen_scaffold.dart';
import 'package:admin/ui/core/widgets/document_viewer.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';

/// Run Template on [ids] — one record from its actions menu, or a list
/// selection (the server merges them into one PDF).
///
/// Asks for the template and whether to email it, then either opens the
/// rendered PDF in the document viewer (with Download) or asks the server to
/// email it to the user. Online-only and outside the outbox: nothing here
/// writes a record, and the PDF comes back only to the caller that started
/// the job (`RunTemplateApi`, `docs/running-a-template.md`).
///
/// [hasUnsyncedEdits] stops a record whose own save is still queued: the
/// server would render its older copy. (The outbox row this replaced waited
/// behind that save; a direct call does not.) The local `is_dirty` flag and
/// the outbox can disagree, and the bulk bar sees only the flag, so every id
/// is also checked against the outbox ([runTemplateHasQueuedChanges]), on the
/// single and the bulk path alike.
///
/// Returns false when the user backed out — the list bulk bar keeps its
/// selection then ([SelectionActionOutcome.cancelled], via
/// [runTemplateOnSelection]).
Future<bool> runTemplate(
  BuildContext context, {
  required RunTemplateEntity entity,
  required List<String> ids,
  bool hasUnsyncedEdits = false,
}) async {
  if (ids.isEmpty) return false;
  final services = context.read<Services>();
  final session = services.auth.session.value;
  if (hasUnsyncedEdits ||
      (session != null &&
          await runTemplateHasQueuedChanges(
            services.db.outboxDao,
            companyId: session.currentCompanyId,
            entity: entity,
            ids: ids,
          ))) {
    if (context.mounted) {
      Notify.error(context, context.tr('sync_first_generic'));
    }
    return false;
  }
  if (!context.mounted) return false;
  final pdfBlock = session == null
      ? null
      : runTemplatePdfBlock(
          canViewReports: session.currentCompany?.can('view_reports') ?? false,
          isHosted: session.isHosted,
          isPaidPlanSlug: session.isPaidPlanSlug,
          isPlanExpired: session.isPlanExpired,
        );
  final choice = await showRunTemplateDialog(
    context,
    entity: entity,
    count: ids.length,
    pdfBlock: pdfBlock,
  );
  if (choice == null || !context.mounted) return false;
  final api = services.runTemplate;

  if (choice.sendEmail) {
    try {
      await api.start(
        entityPath: entity.path,
        ids: ids,
        templateId: choice.template.id,
        sendEmail: true,
      );
      if (!context.mounted) return true;
      Notify.success(context, context.tr('run_template_emailed'));
    } catch (e) {
      if (!context.mounted) return true;
      Notify.error(context, context.tr('run_template'), error: e);
    }
    return true;
  }

  // The viewer shows the spinner, the error with Retry, and the PDF with
  // Download. Closing it stops the polling; a Retry starts a fresh job,
  // because the server deletes a finished PDF once it has been read.
  var closed = false;
  final timedOut = context.tr('run_template_timed_out');
  final refused = context.tr('run_template_pdf_refused');
  await showDocumentViewer(
    context,
    doc: Document(name: choice.template.name, type: 'pdf'),
    fetch: () async {
      try {
        final hash = await api.start(
          entityPath: entity.path,
          ids: ids,
          templateId: choice.template.id,
          sendEmail: false,
        );
        return await api.fetchPdf(hash!, isCancelled: () => closed);
      } on RunTemplateTimeout {
        throw _RunTemplateMessage(timedOut);
      } on PlanRequiredException {
        throw DocumentFetchRefused(refused);
      } on ServerException catch (e) {
        // `ReportPreviewRequest` refused this user the file. Asking again
        // would only queue another job nobody can read.
        if (e.statusCode == 403) throw DocumentFetchRefused(refused);
        rethrow;
      }
    },
  );
  closed = true;
  return true;
}

/// Whether any of [ids] still has a change of its fields in the outbox —
/// `pending`, `in_flight` or `unconfirmed` (`OutboxDao.hasActiveRowsForEntity`,
/// which leaves out a document upload or a comment). The server would render
/// the copy it has, not the one on screen.
Future<bool> runTemplateHasQueuedChanges(
  OutboxDao outbox, {
  required String companyId,
  required RunTemplateEntity entity,
  required List<String> ids,
}) async {
  for (final id in ids) {
    if (await outbox.hasActiveRowsForEntity(
      companyId: companyId,
      entityType: entity.entityType.name,
      entityId: id,
    )) {
      return true;
    }
  }
  return false;
}

/// [runTemplate] as a list bulk bar's `onSelection`: [records] are the
/// eligible selection, and backing out keeps it selected.
Future<Object?> runTemplateOnSelection<T>(
  BuildContext context,
  List<Object?> records, {
  required RunTemplateEntity entity,
  required String Function(T record) idOf,
}) async {
  final ran = await runTemplate(
    context,
    entity: entity,
    ids: [for (final r in records.cast<T>()) idOf(r)],
  );
  return ran ? null : SelectionActionOutcome.cancelled;
}

/// What the picker returns.
typedef RunTemplateChoice = ({Design template, bool sendEmail});

/// The picker on its own: the templates whose `entities` include [entity]
/// (`templatesFor`), and a Send Email switch — locked on when [pdfBlock] says
/// the PDF can't be opened here. Null when cancelled.
Future<RunTemplateChoice?> showRunTemplateDialog(
  BuildContext context, {
  required RunTemplateEntity entity,
  int count = 1,
  RunTemplatePdfBlock? pdfBlock,
}) async {
  final services = context.read<Services>();
  final companyId = services.auth.session.value!.currentCompanyId;
  final allDesigns = await services.designs
      .watchAll(companyId: companyId)
      .first;
  if (!context.mounted) return null;
  return showDialog<RunTemplateChoice>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    builder: (_) => RunTemplateDialog(
      designs: templatesFor(allDesigns, entity),
      count: count,
      pdfBlock: pdfBlock,
    ),
  );
}

/// Public so a test can pump it without `Services`.
class RunTemplateDialog extends StatefulWidget {
  const RunTemplateDialog({
    super.key,
    required this.designs,
    this.count = 1,
    this.pdfBlock,
  });

  /// Already filtered to the record type — see [templatesFor].
  final List<Design> designs;

  /// How many records the template runs on; shown when more than one.
  final int count;

  /// Set when the server won't hand this user the PDF ([runTemplatePdfBlock]):
  /// Send Email is then on, locked, and says why.
  final RunTemplatePdfBlock? pdfBlock;

  @override
  State<RunTemplateDialog> createState() => _RunTemplateDialogState();
}

class _RunTemplateDialogState extends State<RunTemplateDialog> {
  Design? _selected;
  late bool _sendEmail = widget.pdfBlock != null;

  @override
  void initState() {
    super.initState();
    // One template is the whole choice — don't make the user pick it.
    if (widget.designs.length == 1) _selected = widget.designs.single;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final emailOnly = widget.pdfBlock != null;
    return AlertDialog(
      title: Text(context.tr('run_template')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.count > 1) ...[
              Text(
                context.tr('count_records_selected', {
                  'count': '${widget.count}',
                }),
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: InSpacing.md(context)),
            ],
            if (widget.designs.isEmpty)
              Text(
                context.tr('run_template_none_available'),
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              SearchableDropdownField<Design>(
                label: context.tr('template'),
                items: widget.designs,
                initialValue: _selected,
                displayString: (d) => d.name,
                idOf: (d) => d.id,
                onChanged: (d) => setState(() => _selected = d),
              ),
              const SizedBox(height: InSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _sendEmail,
                title: Text(context.tr('send_email')),
                subtitle: Text(
                  context.tr(switch (widget.pdfBlock) {
                    null => 'run_template_send_email_help',
                    RunTemplatePdfBlock.permission =>
                      'run_template_email_only_permission',
                    RunTemplatePdfBlock.plan => 'run_template_email_only_plan',
                  }),
                ),
                onChanged: emailOnly
                    ? null
                    : (v) => setState(() => _sendEmail = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                context.tr(widget.designs.isEmpty ? 'close' : 'cancel'),
              ),
            ),
            if (widget.designs.isNotEmpty) ...[
              SizedBox(width: InSpacing.md(context)),
              PrimaryDialogAction(
                label: context.tr('run'),
                onPressed: () => Navigator.of(context).pop<RunTemplateChoice>((
                  template: selected!,
                  sendEmail: _sendEmail,
                )),
                enabled: selected != null,
                // The dropdown eats Enter, and Run starts disabled unless
                // there is a single template — so no Enter hint.
                autofocus: false,
                showEnterHint: false,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A failure whose text is already the user-facing sentence — the viewer
/// prints `toString()` behind its "failed to load" lead.
class _RunTemplateMessage implements Exception {
  const _RunTemplateMessage(this.message);
  final String message;

  @override
  String toString() => message;
}
