// Every create / edit screen's fields sit in the shared card chrome — the
// white rounded panel the phone invoice editor's Details tab draws
// (`DashboardCardShell`, or `FormSection` on the settings-hosted screens) —
// never bare on the page's canvas, never in a hand-drawn twin of it, never a
// card inside a card, and on a phone never edge to edge.
//
// Walks every wired entity module's create builder plus the screens the
// settings tree hosts directly, through each top-level tab, on a phone and a
// desktop window, over every field on screen (each draws an
// `InputDecorator`: text fields, dropdowns, pickers, date fields). Each
// field's label also goes through `LabeledField`, so it sits above the box at
// Comfortable and inside it at Compact. `docs/form-fields.md` § An edit screen's fields sit in the
// shared card.

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/entity_modules.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/features/billing_shared/contacts/billing_doc_contacts_section.dart';
import 'package:admin/ui/features/billing_shared/line_item_editor/line_item_table_desktop.dart';
import 'package:admin/ui/features/billing_shared/markdown_notes_section.dart';
import 'package:admin/ui/features/billing_shared/view_models/billing_doc_edit_view_model.dart';
import 'package:admin/ui/features/bank_accounts/views/bank_account_edit_screen.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/advanced/group_settings_edit_screen.dart';
import 'package:admin/ui/features/settings/views/advanced/payment_terms_edit_screen.dart';
import 'package:admin/ui/features/settings/views/advanced/schedules_edit_screen.dart';
import 'package:admin/ui/features/settings/views/advanced/tags_edit_screen.dart';
import 'package:admin/ui/features/settings/views/advanced/task_statuses_edit_screen.dart';
import 'package:admin/ui/features/settings/views/advanced/tax_rates_edit_screen.dart';
import 'package:admin/ui/features/settings/views/advanced/user_management/views/user_edit_screen.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/tokens/views/token_edit_screen.dart';
import 'package:admin/ui/features/transaction_rules/views/transaction_rule_edit_screen.dart';
import 'package:admin/ui/features/webhooks/views/webhook_edit_screen.dart';

import '../../features/billing_shared/detail/_billing_doc_fixtures.dart';
import '../../features/billing_shared/edit/_billing_edit_harness.dart';
import '../../features/shell/_shell_test_helpers.dart';

bool _isSharedCard(Widget w) => w is DashboardCardShell || w is FormSection;

/// A grid, not a form: the wide line-item table's cells are inputs, and the
/// table draws its own flat card (hairline border, no shadow — React's).
bool _isGrid(Widget w) => w is LineItemTableDesktop;

/// Jump the first tab strip on screen to [index], whether it carries its own
/// controller or reads a `DefaultTabController`.
Future<void> _showTab(WidgetTester tester, int index) async {
  final bar = find.byType(TabBar).first;
  final controller =
      tester.widget<TabBar>(bar).controller ??
      DefaultTabController.of(tester.element(bar));
  controller.index = index;
  // The page animates even on a controller jump; wait out the transition.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A surface-filled, bordered, rounded box that is not the shared card's own
/// fill — a hand-drawn twin of the card.
bool _isCardLike(Widget w) {
  final surface = InTheme.light.surface;
  if (w is DecoratedBox) {
    final d = w.decoration;
    return d is BoxDecoration &&
        d.color == surface &&
        d.border != null &&
        d.borderRadius != null;
  }
  if (w is Material) {
    final shape = w.shape;
    return w.color == surface &&
        shape is RoundedRectangleBorder &&
        shape.side != BorderSide.none;
  }
  return false;
}

/// What is wrong with one field's chrome, or an empty list.
List<String> _problems(Element field, double width) {
  final path = <Element>[];
  field.visitAncestorElements((a) {
    path.add(a);
    return true;
  });
  final problems = <String>[];
  final cards = [
    for (final a in path)
      if (_isSharedCard(a.widget)) a,
  ];
  if (cards.isEmpty) problems.add('bare on the canvas');
  if (cards.length > 1) problems.add('a card inside a card');
  for (var i = 0; i < path.length; i++) {
    if (!_isCardLike(path[i].widget)) continue;
    // The shared card's own fill sits a few elements under it.
    final owned = path.skip(i + 1).take(12).any((a) => _isSharedCard(a.widget));
    if (!owned) problems.add('a hand-drawn card');
  }
  if (cards.isNotEmpty && width < 600) {
    final box = cards.last.renderObject! as RenderBox;
    final start = box.localToGlobal(Offset.zero).dx;
    final end = width - start - box.size.width;
    if (start < InSpacing.sm || end < InSpacing.sm) {
      problems.add('edge to edge (gutters $start / $end)');
    }
  }
  return problems;
}

/// The field's own label, to name it in a failure.
String _nameOf(Element field) {
  final d = (field.widget as InputDecorator).decoration;
  return d.labelText ?? d.hintText ?? '(no label)';
}

/// A field that sets `labelText` outside a `LabeledField` keeps its label
/// inside the box at Comfortable too; one inside a `LabeledField` with no
/// `labelText` loses its label at Compact (`docs/form-fields.md` § Labels sit
/// above the field).
String? _labelProblem(Element field) {
  final labelText = (field.widget as InputDecorator).decoration.labelText;
  var labeled = false;
  field.visitAncestorElements((a) {
    final w = a.widget;
    if (w is LabeledField && (w.label ?? '').isNotEmpty) labeled = true;
    return !labeled;
  });
  final hasLabel = labelText != null && labelText.isNotEmpty;
  if (hasLabel && !labeled) {
    return 'its label is not a LabeledField (inside the box at Comfortable)';
  }
  if (labeled && !hasLabel) {
    return 'its LabeledField has no labelText (no label at Compact)';
  }
  return null;
}

void main() {
  final screens = <String, GoRouterWidgetBuilder>{
    for (final m in kWiredEntityModules)
      if (m.createBuilder != null) m.type.name: m.createBuilder!,
    'token': (_, _) => const TokenEditScreen(),
    'webhook': (_, _) => const WebhookEditScreen(),
    'bankAccount': (_, _) => const BankAccountEditScreen(),
    'transactionRule': (_, _) => const TransactionRuleEditScreen(),
    'group': (_, _) => const GroupSettingsEditScreen(),
    'taskStatus': (_, _) => const TaskStatusesEditScreen(),
    'tag': (_, _) => const TagsEditScreen(),
    'paymentTerm': (_, _) => const PaymentTermsEditScreen(),
    'taxRate': (_, _) => const TaxRatesEditScreen(),
    'schedule': (_, _) => const SchedulesEditScreen(),
    'user': (_, _) => const UserEditScreen(),
  };

  for (final width in const [390.0, 1280.0]) {
    for (final MapEntry(key: name, value: builder) in screens.entries) {
      testWidgets('$name @ ${width.toInt()} px: every field is in a card', (
        tester,
      ) async {
        setWindow(tester, width, height: 2400);
        final fixture = await buildFixture(
          closeStreamsSynchronously: true,
          companies: [const FakeCompany(id: kHarnessCompanyId, name: 'Co')],
        );
        addTearDown(fixture.dispose);
        final router = GoRouter(
          initialLocation: '/edit/new',
          routes: [GoRoute(path: '/edit/new', builder: builder)],
        );
        // The settings-hosted screens read the scope controller their shell
        // provides.
        await tester.pumpWidget(
          wrapWithShell(
            fixture.services,
            ChangeNotifierProvider<SettingsLevelController>(
              create: (_) => SettingsLevelController(),
              child: Router.withConfig(config: router),
            ),
          ),
        );
        await settle(tester);

        final bars = find.byType(TabBar);
        final tabs = bars.evaluate().isEmpty
            ? 1
            : tester.widget<TabBar>(bars.first).tabs.length;
        final failures = <String>[];
        for (var tab = 0; tab < tabs; tab++) {
          if (tab > 0) await _showTab(tester, tab);
          for (final e in find.byType(InputDecorator).evaluate()) {
            var inGrid = false;
            e.visitAncestorElements((a) {
              inGrid = _isGrid(a.widget);
              return !inGrid;
            });
            if (inGrid) continue;
            final problems = [..._problems(e, width), ?_labelProblem(e)];
            if (problems.isEmpty) continue;
            failures.add('tab $tab, "${_nameOf(e)}": ${problems.join('; ')}');
          }
        }
        expect(failures, isEmpty);
        await unmount(tester, fixture);
      });
    }
  }

  // The phone billing editor's tabs whose bodies are not `InputDecorator`s —
  // the Contacts tab's checkbox rows, the Notes tab's markdown editors — and
  // the E-Invoice tab, which only a company that files e-invoices shows: each
  // in the shared card like the Details tab, inside the gutter. The Items
  // tab's line-item tiles are rows of their own and are not walked.
  for (final doc in BillingDoc.values) {
    testWidgets('${doc.name} @ 390 px: every tab body is in the card', (
      tester,
    ) async {
      setWindow(tester, 390, height: 2400);
      final fixture = await buildFixture(
        closeStreamsSynchronously: true,
        companies: [
          const FakeCompany(
            id: kHarnessCompanyId,
            name: 'Co',
            settings: {'enable_e_invoice': true},
          ),
        ],
      );
      addTearDown(fixture.dispose);
      final vendor = doc == BillingDoc.purchaseOrder;
      await (vendor ? seedVendor : seedClient)(fixture.services);
      final mounted = buildLayout(doc, fixture.services, showPdfTab: false);
      addTearDown(mounted.vm.dispose);
      final vm = mounted.vm as BillingDocEditViewModel;
      vendor ? vm.setVendorId('v1') : vm.setClientId('c1');
      await tester.pumpWidget(wrapWithShell(fixture.services, mounted.layout));
      await settle(tester);

      final labels = tabBarLabels(tester).first;
      final failures = <String>[];
      final seen = <String, int>{};
      for (var tab = 0; tab < labels.length; tab++) {
        if (labels[tab] == 'Items') continue;
        if (tab > 0) await _showTab(tester, tab);
        void check(Finder finder, String Function(Element) name) {
          for (final e in finder.evaluate()) {
            seen[labels[tab]] = (seen[labels[tab]] ?? 0) + 1;
            final problems = [
              ..._problems(e, 390),
              if (e.widget is InputDecorator) ?_labelProblem(e),
            ];
            if (problems.isEmpty) continue;
            failures.add('${labels[tab]}, ${name(e)}: ${problems.join('; ')}');
          }
        }

        check(find.byType(InputDecorator), _nameOf);
        check(
          find.byType(MarkdownNotesField),
          (e) => (e.widget as MarkdownNotesField).label,
        );
        check(find.byType(BillingDocContactsSection), (_) => 'contacts');
      }
      expect(failures, isEmpty);
      // The walk reached what it is here for.
      expect(seen['Contacts'], greaterThan(0), reason: 'contacts rendered');
      expect(seen['Notes'], greaterThanOrEqualTo(4), reason: 'notes editors');
      if (doc != BillingDoc.quote && doc != BillingDoc.purchaseOrder) {
        expect(labels, contains('E-Invoice'));
        expect(seen['E-Invoice'], greaterThan(0), reason: 'e-invoice fields');
      }
      await unmount(tester, fixture);
    });
  }
}
