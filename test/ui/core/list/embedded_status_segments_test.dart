import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/list_status_tabs.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/ui/core/list/entity_list_status_tabs.dart';
import 'package:admin/ui/core/list/entity_list_top_row.dart';

import '../../../_localization_helper.dart';

/// The status segments a list embedded in a record's tab carries in its
/// toolbar, and the toolbar's rule for when they fit.
void main() {
  final tabs = listStatusTabsFor(
    EntityType.invoice,
    modes: kInvoiceBadgeModes,
    trackInventory: false,
  );

  Widget host(Widget child, {double width = 1000}) => MaterialApp(
    theme: buildInTheme(InTheme.light),
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: kTestSupportedLocales,
    home: Scaffold(
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('one segment per tab, All first, no counts; a tap goes out', (
    tester,
  ) async {
    ResolvedStatusTab? tapped;
    await tester.pumpWidget(
      host(
        EmbeddedStatusSegments(
          tabs: tabs,
          selectedIndex: 0,
          onTap: (t) => tapped = t,
        ),
      ),
    );
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    await tester.tap(find.text('Draft'));
    expect(tapped?.listModeId, 'draft');
  });

  testWidgets('the selected segment is announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(EmbeddedStatusSegments(tabs: tabs, selectedIndex: 1, onTap: (_) {})),
    );
    expect(
      tester.getSemantics(find.text('Draft')),
      isSemantics(label: 'Draft', isSelected: true, hasTapAction: true),
    );
    handle.dispose();
  });

  group('EmbeddedListTopRow', () {
    Widget row(BuildContext context) => EmbeddedListTopRow(
      searchField: const SizedBox(height: 40),
      newRoute: '/invoices/new',
      newLabelKey: 'new_invoice',
      wide: true,
      statusSegments: EmbeddedStatusSegments(
        tabs: tabs,
        selectedIndex: 0,
        onTap: (_) {},
      ),
      statusSegmentsWidth: EmbeddedStatusSegments.naturalWidth(context, tabs),
    );

    testWidgets('places the segments exactly where the search field keeps '
        'its room beside them and New, and falls back to the Status chip '
        'below that', (tester) async {
      // Measured, not a fixed width: the tab catalog grows (invoices gained
      // Paid) and the test font is not the app's. A window wide enough for
      // the host's own width to be the one that counts.
      tester.view.physicalSize = const Size(2400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(Builder(builder: row), width: 2000));
      final natural = EmbeddedStatusSegments.naturalWidth(
        tester.element(find.byType(EmbeddedListTopRow)),
        tabs,
      );
      final threshold = natural + kEmbeddedNewReserve + kEmbeddedSearchMinWidth;

      await tester.pumpWidget(
        host(Builder(builder: row), width: threshold + 1),
      );
      expect(find.byType(EmbeddedStatusSegments), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      // New is outlined: the record's quick-action strip has the accent.
      expect(find.widgetWithText(OutlinedButton, 'New'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      await tester.pumpWidget(
        host(Builder(builder: row), width: threshold - 1),
      );
      expect(find.byType(EmbeddedStatusSegments), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'New'), findsOneWidget);
    });

    testWidgets('a pane-width toolbar leaves them out', (tester) async {
      await tester.pumpWidget(host(Builder(builder: row), width: 520));
      expect(find.byType(EmbeddedStatusSegments), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'New'), findsOneWidget);
    });
  });
}
