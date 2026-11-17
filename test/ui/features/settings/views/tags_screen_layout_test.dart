import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/ui/core/widgets/empty_state.dart';
import 'package:admin/ui/core/widgets/searchable_dropdown_field.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/advanced/tags_screen.dart';
import 'package:admin/ui/features/settings/widgets/settings_page_intro.dart';

import '../../shell/_shell_test_helpers.dart';

/// Settings → Tags read oddly when empty: the Type picker floated on its own
/// above the 720 px column (a scaffold `banner`, outside the cap), over a
/// wide card holding a start-aligned icon, title, hint and button. The
/// picker is now the page's control on the intro row, and the empty state is
/// the shared `EmptyStateBody`, centred in the card.
void main() {
  Future<ShellFixture> pumpTags(
    WidgetTester tester, {
    List<String> names = const [],
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await buildFixture(
      companies: [const FakeCompany(id: 'co1', name: 'Co')],
      closeStreamsSynchronously: true,
      // The screen's `refreshAll` pages `/tags` on open; answer with an
      // empty page so the rows under test are the ones seeded below.
      httpClient: MockClient(
        (_) async => http.Response(
          '{"data":[],"meta":{"pagination":{"total":0,"count":0,'
          '"per_page":50,"current_page":1,"total_pages":1}}}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(fixture.dispose);
    for (final (i, name) in names.indexed) {
      await fixture.db
          .into(fixture.db.tags)
          .insert(
            TagsCompanion.insert(
              id: 't$i',
              companyId: 'co1',
              entityType: const Value('task'),
              name: Value(name),
              updatedAt: 1,
              payload: '{}',
            ),
          );
    }
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsLevelController>(
        create: (_) => SettingsLevelController(),
        child: wrapWithShell(fixture.services, const TagsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  }

  testWidgets('the Type picker sits on the intro row, inside the column', (
    tester,
  ) async {
    await pumpTags(tester);
    final picker = find.byType(SearchableDropdownField<String>);
    expect(picker, findsOneWidget);
    expect(
      find.ancestor(of: picker, matching: find.byType(SettingsPageIntro)),
      findsOneWidget,
    );
    // Inside the column: its end edge level with the card's, not floating
    // out past the 720 / 1000 px cap. The empty state's `Center` spans the
    // card's content box, inset by the card's padding.
    final content = find
        .ancestor(
          of: find.byType(EmptyStateBody),
          matching: find.byType(Center),
        )
        .first;
    final cardEnd = tester.getTopRight(content).dx;
    expect(
      tester.getTopRight(picker).dx,
      inInclusiveRange(cardEnd, cardEnd + 17),
    );
    expect(
      tester.getBottomLeft(picker).dy,
      lessThan(tester.getTopLeft(content).dy),
    );
  });

  testWidgets('empty: the shared empty state, centred, one New Tag', (
    tester,
  ) async {
    await pumpTags(tester);
    final body = find.byType(EmptyStateBody);
    expect(body, findsOneWidget);
    expect(find.text('No Tags'), findsOneWidget);
    expect(find.text('New Tag'), findsOneWidget);
    // Centred in the card, as on the entity lists — not start-aligned.
    final content = find
        .ancestor(of: body, matching: find.byType(Center))
        .first;
    expect(
      tester.getCenter(find.text('No Tags')).dx,
      closeTo(tester.getCenter(content).dx, 1),
    );
    expect(
      tester.getTopLeft(find.text('No Tags')).dx,
      greaterThan(tester.getTopLeft(content).dx + 100),
    );
  });

  testWidgets('with tags: the rows, and New Tag once at the end', (
    tester,
  ) async {
    await pumpTags(tester, names: ['Urgent', 'Billable']);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Billable'), findsOneWidget);
    expect(find.byType(EmptyStateBody), findsNothing);
    expect(find.text('New Tag'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New Tag')).dy,
      greaterThan(tester.getTopLeft(find.text('Urgent')).dy),
    );
  });

  testWidgets('a 390 px phone lays out without overflow', (tester) async {
    await pumpTags(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchableDropdownField<String>), findsOneWidget);
    expect(find.text('No Tags'), findsOneWidget);
  });
}
