import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/domain/tasks/kanban_prefs.dart';
import 'package:admin/ui/features/tasks/views/kanban_screen.dart';

import '../shell/_shell_test_helpers.dart';

/// The board's Display menu, on the real screen over real `Services`: a pick
/// is saved as it is made (`DevicePrefKeys.kanban`), and the menu stays open
/// for the next one.
void main() {
  testWidgets('Display picks are saved as they are made', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
      closeStreamsSynchronously: true,
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      wrapWithShell(fixture.services, const KanbanScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = fixture.services.kanbanPrefs;
    expect(prefs.value, const KanbanPrefs());

    await tester.tap(find.byTooltip('Display'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Group by'), findsOneWidget);
    expect(find.text('Card fields'), findsOneWidget);

    // By type: the filter bar above the board has a `Project` of its own.
    await tester.tap(
      find.widgetWithText(RadioMenuButton<KanbanGroupBy>, 'Project'),
    );
    await tester.pump();
    expect(prefs.value.groupBy, KanbanGroupBy.project);

    // Still open: the next pick needs no second trip to the AppBar.
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Task Number'));
    await tester.pump();
    expect(prefs.value.shows(KanbanCardField.number), isTrue);
    expect(
      KanbanPrefs.decode(prefs.value.encode()).groupBy,
      KanbanGroupBy.project,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
