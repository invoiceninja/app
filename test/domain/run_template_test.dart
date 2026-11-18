import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/design.dart';
import 'package:admin/domain/run_template.dart';

Design _design(
  String id, {
  String? name,
  bool isTemplate = true,
  List<String> entities = const ['invoice'],
  bool isDeleted = false,
  DateTime? archivedAt,
}) => Design(
  id: id,
  name: name ?? id,
  isCustom: true,
  isActive: true,
  isTemplate: isTemplate,
  isFree: false,
  entities: entities,
  template: const DesignTemplate(),
  updatedAt: DateTime.utc(2026, 1, 1, 12),
  createdAt: DateTime.utc(2026, 1, 1, 12),
  archivedAt: archivedAt,
  isDeleted: isDeleted,
);

void main() {
  group('templatesFor', () {
    test('offers only templates ticked for the record type '
        '(invoiceninja/app#197)', () {
      final designs = [
        _design('inv', entities: const ['invoice']),
        _design('both', entities: const ['invoice', 'quote']),
        _design('quote', entities: const ['quote']),
        _design('none', entities: const []),
      ];

      expect(
        templatesFor(designs, RunTemplateEntity.invoice).map((d) => d.id),
        ['both', 'inv'],
      );
      expect(templatesFor(designs, RunTemplateEntity.quote).map((d) => d.id), [
        'both',
        'quote',
      ]);
      expect(templatesFor(designs, RunTemplateEntity.credit), isEmpty);
    });

    test('leaves out plain designs, deleted, archived and unsynced ones', () {
      final designs = [
        _design('plain', isTemplate: false),
        _design('deleted', isDeleted: true),
        _design('archived', archivedAt: DateTime.utc(2026, 1, 2, 12)),
        _design('tmp_new'),
        _design('ok'),
      ];

      expect(
        templatesFor(designs, RunTemplateEntity.invoice).map((d) => d.id),
        ['ok'],
      );
    });

    test('matches the wire name, not the enum name', () {
      final designs = [
        _design('po', entities: const ['purchase_order']),
        _design('camel', entities: const ['purchaseOrder']),
      ];

      expect(
        templatesFor(designs, RunTemplateEntity.purchaseOrder).map((d) => d.id),
        ['po'],
      );
    });

    test('sorts by name, ignoring case', () {
      final designs = [
        _design('1', name: 'beta'),
        _design('2', name: 'Alpha'),
        _design('3', name: 'gamma'),
      ];

      expect(
        templatesFor(designs, RunTemplateEntity.invoice).map((d) => d.name),
        ['Alpha', 'beta', 'gamma'],
      );
    });
  });

  test('every entity routes to the plural bulk path the server serves', () {
    expect(
      {for (final e in RunTemplateEntity.values) e.designEntity: e.path},
      {
        'invoice': 'invoices',
        'quote': 'quotes',
        'credit': 'credits',
        'purchase_order': 'purchase_orders',
        'project': 'projects',
        'expense': 'expenses',
        'client': 'clients',
        'payment': 'payments',
        'task': 'tasks',
      },
    );
  });

  group('runTemplatePdfBlock mirrors ReportPreviewRequest', () {
    RunTemplatePdfBlock? block({
      bool canViewReports = true,
      bool isHosted = true,
      bool isPaidPlanSlug = true,
      bool isPlanExpired = false,
    }) => runTemplatePdfBlock(
      canViewReports: canViewReports,
      isHosted: isHosted,
      isPaidPlanSlug: isPaidPlanSlug,
      isPlanExpired: isPlanExpired,
    );

    test('a paid admin or view_reports holder reads the PDF', () {
      expect(block(), isNull);
    });

    test('without view_reports it can only be emailed', () {
      expect(block(canViewReports: false), RunTemplatePdfBlock.permission);
    });

    test('a free or expired hosted plan can only email it', () {
      expect(block(isPaidPlanSlug: false), RunTemplatePdfBlock.plan);
      expect(block(isPlanExpired: true), RunTemplatePdfBlock.plan);
    });

    test('self-hosted has no plan gate', () {
      expect(block(isHosted: false, isPaidPlanSlug: false), isNull);
    });
  });
}
