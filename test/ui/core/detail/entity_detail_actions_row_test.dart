import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/mdi_icons.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/detail/quick_action_kinds_scope.dart';

import '../../../_localization_helper.dart';

/// Mirrors the fixture in `entity_actions_hide_unsupported_test.dart`: a
/// primary Edit, a hidden action (Refund), and a transient-busy inert action
/// (Busy) that stays visible.
List<EntityActionItem<String>> _items() => [
  const EntityActionItem(
    kind: 'edit',
    icon: MdiIcons.circleEditOutline,
    label: 'Edit',
    enabled: true,
    isPrimary: true,
  ),
  const EntityActionItem(
    kind: 'refund',
    icon: Icons.money_off,
    label: 'Refund',
    enabled: false,
  ),
  const EntityActionItem(
    kind: 'busy',
    icon: Icons.hourglass_empty,
    label: 'Busy',
    enabled: false,
    disabledTooltipKey: null,
  ),
];

/// A primary Edit plus enough actions that they can't all fit inline at a
/// modest wide width — forcing the spread bar to collapse the tail into "More".
List<EntityActionItem<String>> _manyItems() => [
  const EntityActionItem(
    kind: 'edit',
    icon: MdiIcons.circleEditOutline,
    label: 'Edit',
    enabled: true,
    isPrimary: true,
  ),
  for (var i = 0; i < 8; i++)
    EntityActionItem(
      kind: 'a$i',
      icon: Icons.bolt_outlined,
      label: 'Action number $i',
      enabled: true,
    ),
];

/// A soft-deleted record drops the primary Edit and keeps only lifecycle ops.
const _noPrimary = <EntityActionItem<String>>[
  EntityActionItem(
    kind: 'archive',
    icon: Icons.archive_outlined,
    label: 'Archive',
    enabled: true,
    isLifecycle: true,
  ),
  EntityActionItem(
    kind: 'delete',
    icon: Icons.delete_outline,
    label: 'Delete',
    enabled: true,
    isLifecycle: true,
  ),
];

/// A record whose only action is Edit (e.g. a bank account with no lifecycle).
const _editOnly = <EntityActionItem<String>>[
  EntityActionItem(
    kind: 'edit',
    icon: MdiIcons.circleEditOutline,
    label: 'Edit',
    enabled: true,
    isPrimary: true,
  ),
];

/// Hosts [child] at a fixed [width] so the row's `LayoutBuilder` resolves to a
/// known branch: `< Breakpoints.wide` (600) ⇒ compact `⋮`, `≥ 600` ⇒ spread bar.
Widget _host(Widget child, {required double width}) => MaterialApp(
  theme: buildInTheme(InTheme.light),
  localizationsDelegates: kTestLocalizationsDelegates,
  supportedLocales: kTestSupportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('narrow (compact ⋮)', () {
    testWidgets('surfaces the primary Edit button + a ⋮ overflow with the rest', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(EntityDetailActionsRow<String>(items: _items()), width: 400),
      );
      await tester.pumpAndSettle();

      // Edit is surfaced as its own FilledButton; the rest live behind the ⋮.
      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // The overflow holds the transient-busy item — not Edit (it's the surfaced
      // button, removed from the menu), nor the unsupported Refund.
      expect(find.text('Busy'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'Edit'), findsNothing);
      expect(find.text('Refund'), findsNothing);
    });

    testWidgets('with no primary action, shows only the ⋮ overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(EntityDetailActionsRow<String>(items: _noPrimary), width: 400),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('with only the primary action, shows Edit and no ⋮', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(EntityDetailActionsRow<String>(items: _editOnly), width: 400),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });

  group('wide (spread bar + "More")', () {
    testWidgets('spreads actions inline next to Edit (no overflow menu) when '
        'they all fit', (tester) async {
      // Edit (primary, surfaced as leading) + Busy (the one visible "rest"
      // item) both fit at 800, so Busy renders inline rather than behind a menu.
      await tester.pumpWidget(
        _host(EntityDetailActionsRow<String>(items: _items()), width: 800),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Busy'), findsOneWidget);
      // Neither overflow trigger: the compact ⋮ is the narrow branch, and the
      // "More" menu only appears once something overflows. Both carry
      // `Icons.more_vert`, so one assertion covers the pair.
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('collapses the tail into a labeled "More" menu when actions '
        'overflow; Edit stays pinned', (tester) async {
      // 8 actions can't fit beside Edit at 650 — the tail collapses into "More".
      await tester.pumpWidget(
        _host(EntityDetailActionsRow<String>(items: _manyItems()), width: 650),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
      // The labeled "More" trigger, not the compact ⋮. Both carry
      // `Icons.more_vert` — the app uses one glyph on every overflow surface —
      // so the button type is what tells them apart.
      expect(
        find.widgetWithIcon(OutlinedButton, Icons.more_vert),
        findsOneWidget,
      );
      expect(find.widgetWithIcon(IconButton, Icons.more_vert), findsNothing);

      await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.more_vert));
      await tester.pumpAndSettle();
      // The last action overflowed into the menu.
      expect(find.text('Action number 7'), findsOneWidget);
    });

    testWidgets('with no primary, spreads lifecycle actions inline when wide', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(EntityDetailActionsRow<String>(items: _noPrimary), width: 800),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Archive'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });

  group('beside a quick-action strip', () {
    /// The bar under a record screen's scope, with [tiled] published as the
    /// strip's tiles and [onScreen] as already showing.
    Future<void> pumpBar(
      WidgetTester tester,
      List<EntityActionItem<String>> items, {
      required double width,
      Set<Object?> tiled = const {},
      Set<Object?> onScreen = const {},
    }) async {
      final kinds = QuickActionKinds();
      addTearDown(kinds.dispose);
      await tester.pumpWidget(
        _host(
          QuickActionKindsScope(
            notifier: kinds,
            child: EntityDetailActionsRow<String>(items: items),
          ),
          width: width,
        ),
      );
      kinds.publish(tiled, onScreen: onScreen);
      // Published after a frame, never during build.
      await tester.pump();
      await tester.pumpAndSettle();
    }

    const edit = EntityActionItem<String>(
      kind: 'edit',
      icon: MdiIcons.circleEditOutline,
      label: 'Edit',
      enabled: true,
      isPrimary: true,
    );

    for (final width in [400.0, 800.0]) {
      testWidgets('one accent per screen: Edit is outlined while the strip '
          'shows tiles (width $width)', (tester) async {
        await pumpBar(
          tester,
          [
            edit,
            const EntityActionItem(
              kind: 'statement',
              icon: Icons.picture_as_pdf,
              label: 'Statement',
              enabled: true,
            ),
          ],
          width: width,
          tiled: {'statement'},
        );
        expect(find.widgetWithText(FilledButton, 'Edit'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
      });
    }

    testWidgets('a kind that is only on screen does not turn Edit neutral', (
      tester,
    ) async {
      await pumpBar(tester, [edit], width: 800, onScreen: {'pdf'});
      expect(find.widgetWithText(FilledButton, 'Edit'), findsOneWidget);
    });

    testWidgets('a menu-only item never gets a bar button, but is in More', (
      tester,
    ) async {
      await pumpBar(tester, [
        edit,
        const EntityActionItem(
          kind: 'settings',
          icon: Icons.settings_outlined,
          label: 'Settings',
          enabled: true,
          menuOnly: true,
        ),
        const EntityActionItem(
          kind: 'comment',
          icon: Icons.add_comment_outlined,
          label: 'Add Comment',
          enabled: true,
        ),
      ], width: 800);
      expect(
        find.widgetWithText(OutlinedButton, 'Add Comment'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Settings'), findsNothing);
      await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Settings'), findsOneWidget);
    });

    testWidgets('a group whose child is a tile goes under More whole — Clone '
        'was drawn twice', (tester) async {
      await pumpBar(
        tester,
        [
          edit,
          const EntityActionItem(
            kind: 'cloneGroup',
            icon: Icons.copy_outlined,
            label: 'Clone',
            enabled: true,
            children: [
              EntityActionItem(
                kind: 'clone',
                icon: Icons.copy_outlined,
                label: 'Clone',
                enabled: true,
              ),
              EntityActionItem(
                kind: 'cloneToQuote',
                icon: Icons.copy_outlined,
                label: 'Clone to Quote',
                enabled: true,
              ),
            ],
          ),
          const EntityActionItem(
            kind: 'pdf',
            icon: Icons.picture_as_pdf,
            label: 'View PDF',
            enabled: true,
          ),
        ],
        width: 800,
        tiled: {'clone'},
        onScreen: {'pdf'},
      );
      expect(find.widgetWithText(OutlinedButton, 'Clone'), findsNothing);
      // The PDF is on screen beside the record: no button for it either.
      expect(find.widgetWithText(OutlinedButton, 'View PDF'), findsNothing);
      await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SubmenuButton, 'Clone'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'View PDF'), findsOneWidget);
    });
  });
}
