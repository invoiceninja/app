import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/document.dart';
import 'package:admin/data/repositories/base_entity_repository.dart';
import 'package:admin/data/repositories/document_bearing_repository.dart';
import 'package:admin/data/repositories/document_repository.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/detail_tab_indices.dart';
import 'package:admin/ui/core/detail/entity_detail_tabs.dart';
import 'package:admin/ui/core/detail/entity_documents_tab.dart';
import 'package:admin/utils/formatting.dart';

/// Builds the standard Documents tab used on every document-bearing entity's
/// detail screen (Client / Product / Project / Vendor / Expense /
/// RecurringExpense / Invoice). Wraps [EntityDocumentsTab] with the
/// `documents` label and its count badge, the description icon, and the
/// three callback closures that route through [repo]'s uniform
/// `uploadDocument` / `deleteDocument` / `setDocumentVisibility` methods.
///
/// Each detail screen used to inline ~35 LOC of boilerplate for this tab;
/// after the [DocumentBearingRepository] interface unified the per-entity
/// signatures, the call site collapses to one line.
EntityDetailTab buildStandardDocumentsTab({
  required BuildContext context,
  required String companyId,
  required String entityId,
  required List<Document> documents,
  required DocumentBearingRepository repo,
  Formatter? formatter,
  bool readOnly = false,
}) {
  return EntityDetailTab(
    id: DetailTabIds.documents,
    label: context.tr('documents'),
    // The badge every counted tab wears, in place of a "(2)" in the label.
    // Exact — the documents ride on the record — and left off at none: an
    // empty Documents tab is the usual case, not news.
    count: documents.isEmpty ? null : documents.length,
    icon: Icons.description_outlined,
    bodyBuilder: (_) => entityDocumentsTabFor(
      context: context,
      companyId: companyId,
      entityId: entityId,
      documents: documents,
      repo: repo,
      formatter: formatter,
      // A soft-deleted record cannot take a new document or lose one, but the
      // ones it has stay readable.
      readOnly: readOnly,
    ),
  );
}

/// An [EntityDocumentsTab] wired to [repo] — upload, delete and visibility
/// through the record's own outbox rows, rename through the Documents table
/// (`DocumentRepository.renameAttached`, which patches the record's copy).
/// The record screen's tab and a record's edit form (invoiceninja/app#205)
/// both build it here, so the two can't drift apart.
EntityDocumentsTab entityDocumentsTabFor({
  required BuildContext context,
  required String companyId,
  required String entityId,
  required List<Document> documents,
  required DocumentBearingRepository repo,
  Formatter? formatter,
  bool readOnly = false,
  bool padded = true,
}) {
  final owner = repo;
  final parentType = owner is BaseEntityRepository
      ? (owner as BaseEntityRepository).entityType
      : null;
  DocumentRepository? documentsRepo;
  try {
    documentsRepo = context.read<Services>().documents;
  } catch (_) {
    // No Services above, or a test fake without the Documents table: no
    // rename, everything else as before.
  }
  final renames = documentsRepo;
  return EntityDocumentsTab(
    entityId: entityId,
    documents: documents,
    formatter: formatter,
    readOnly: readOnly,
    padded: padded,
    onUpload: (sources) async {
      for (final s in sources) {
        await repo.uploadDocument(
          companyId: companyId,
          entityId: entityId,
          source: s,
        );
      }
    },
    onDelete: (doc) => repo.deleteDocument(
      companyId: companyId,
      entityId: entityId,
      documentId: doc.id,
    ),
    onToggleVisibility: (doc) => repo.setDocumentVisibility(
      companyId: companyId,
      entityId: entityId,
      documentId: doc.id,
      isPublic: !doc.isPublic,
    ),
    onRename: renames == null || parentType == null
        ? null
        : (doc, name) => renames.renameAttached(
            companyId: companyId,
            document: doc,
            parentType: parentType,
            parentId: entityId,
            name: name,
          ),
  );
}
