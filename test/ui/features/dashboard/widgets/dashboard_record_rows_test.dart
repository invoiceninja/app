import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_panel_grid.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_record_row.dart';

/// A list panel that spans a two-column grid row flows its rows into two
/// columns, rather than stretching each row across the whole dashboard — the
/// gap between a client's name and the amount that split Invoices & Quotes in
/// two.
void main() {
  Future<void> pump(WidgetTester tester, {required bool spans}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        home: Scaffold(
          body: DashboardPanelCell(
            stretched: false,
            spans: spans,
            child: DashboardRecordRows(
              rows: [
                for (var i = 1; i <= 5; i++)
                  SizedBox(height: 40, child: Text('row $i')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double x(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dx;
  double y(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  testWidgets('spanning: the earlier half on the start side, side by side', (
    tester,
  ) async {
    await pump(tester, spans: true);
    for (final label in ['row 1', 'row 2', 'row 3']) {
      expect(x(tester, label), x(tester, 'row 1'), reason: label);
    }
    for (final label in ['row 4', 'row 5']) {
      expect(x(tester, label), greaterThan(500), reason: label);
    }
    expect(y(tester, 'row 4'), y(tester, 'row 1'));
    expect(y(tester, 'row 5'), y(tester, 'row 2'));
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('in a half-width cell the rows stay one column', (tester) async {
    await pump(tester, spans: false);
    for (var i = 2; i <= 5; i++) {
      expect(x(tester, 'row $i'), x(tester, 'row 1'));
      expect(y(tester, 'row $i'), greaterThan(y(tester, 'row ${i - 1}')));
    }
    expect(find.byType(VerticalDivider), findsNothing);
  });
}
