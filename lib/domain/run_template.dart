import 'package:admin/data/models/domain/design.dart';
import 'package:admin/domain/entity_type.dart';

/// The record types Run Template is offered on, each carrying the two names
/// the server knows it by (`docs/running-a-template.md`) and the local
/// [EntityType] its outbox rows are filed under.
///
/// Every controller that dispatches `TemplateAction`. Recurring invoices have
/// no `template` bulk action (`BulkRecurringInvoiceRequest`), so they are not
/// here.
enum RunTemplateEntity {
  invoice('invoice', 'invoices', EntityType.invoice),
  quote('quote', 'quotes', EntityType.quote),
  credit('credit', 'credits', EntityType.credit),
  purchaseOrder('purchase_order', 'purchase_orders', EntityType.purchaseOrder),
  project('project', 'projects', EntityType.project),
  expense('expense', 'expenses', EntityType.expense),
  client('client', 'clients', EntityType.client),
  payment('payment', 'payments', EntityType.payment),
  task('task', 'tasks', EntityType.task);

  const RunTemplateEntity(this.designEntity, this.path, this.entityType);

  /// The record type, whose `name` is the outbox's `entity_type`.
  final EntityType entityType;

  /// The value a template design lists in its `entities` (the Design editor's
  /// checkboxes; `StoreDesignRequest::$valid_entities`).
  final String designEntity;

  /// The plural route segment whose `/bulk` takes `action: template`.
  final String path;
}

/// The designs Run Template can offer for [entity]: templates the user ticked
/// that record type on, that still exist, and that the server knows about.
///
/// A design's `entities` is the server's own filter (`DesignFilters::entities`
/// is `FIND_IN_SET` on it), and React and v1 both ask for exactly this list —
/// offering every template on every record is invoiceninja/app#197.
List<Design> templatesFor(Iterable<Design> designs, RunTemplateEntity entity) {
  final list = [
    for (final d in designs)
      if (d.isTemplate &&
          !d.isDeleted &&
          d.archivedAt == null &&
          !d.id.startsWith('tmp_') &&
          d.entities.any((e) => e.trim() == entity.designEntity))
        d,
  ];
  list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Why the rendered PDF can't be opened in the app — only emailed.
enum RunTemplatePdfBlock {
  /// `ReportPreviewRequest` admits only an admin or a `view_reports` holder.
  permission,

  /// …and refuses a free hosted account (`isFreeHostedClient`).
  plan,
}

/// Whether this user may read a finished template back, or why not.
///
/// The PDF is served by `templates/preview/<hash>`, which the server guards
/// with `ReportPreviewRequest` — a stricter gate than the bulk `template`
/// action's `can('view')`. Without this, a user allowed to start a job is
/// shown a 403 for a PDF they could only ever have had emailed. The plan test
/// is the server's `isFreeHostedClient()`: a free / empty plan slug or a plan
/// expired, with no trial exemption.
RunTemplatePdfBlock? runTemplatePdfBlock({
  required bool canViewReports,
  required bool isHosted,
  required bool isPaidPlanSlug,
  required bool isPlanExpired,
}) {
  if (isHosted && (!isPaidPlanSlug || isPlanExpired)) {
    return RunTemplatePdfBlock.plan;
  }
  if (!canViewReports) return RunTemplatePdfBlock.permission;
  return null;
}
