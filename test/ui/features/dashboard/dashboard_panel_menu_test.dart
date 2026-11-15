import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_panel_menu.dart';

import '../../../_localization_helper.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: buildInTheme(InTheme.light),
    localizationsDelegates: kTestLocalizationsDelegates,
    home: Scaffold(body: child),
  );

  const shell = DashboardCardShell(title: 'Recent Payments', child: Text('x'));

  testWidgets('a dashboard panel header carries Hide and Customize', (
    tester,
  ) async {
    var hidden = 0;
    var customized = 0;
    await tester.pumpWidget(
      host(
        DashboardPanelMenuScope(
          onHide: () => hidden++,
          onCustomize: () => customized++,
          child: shell,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(hidden, 1);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
    expect(customized, 1);
  });

  testWidgets('a shell outside a dashboard panel has no menu', (tester) async {
    // The same shell frames record and edit screens app-wide.
    await tester.pumpWidget(host(shell));
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
