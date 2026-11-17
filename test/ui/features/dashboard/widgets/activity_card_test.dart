import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/core/widgets/initials_avatar.dart';
import 'package:admin/ui/features/dashboard/widgets/activity_card.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/utils/formatting.dart';

import '../../../../_localization_helper.dart';

/// The company's date format (`date_format_id` 5), so a day header proves it
/// goes through `Formatter.date` rather than printing ISO.
final _formatter = Formatter(
  settings: CompanyFormatSettings.fallback,
  currencies: const {},
  countries: const {},
  dateFormats: const {'5': DatetimeFormat(id: '5', format: 'MMM d, yyyy')},
);

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback? onViewAll,
  AsyncSection<List<DashboardActivity>> section =
      const AsyncSection<List<DashboardActivity>>.ready([]),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: ActivityCard(
              section: section,
              onViewAll: onViewAll,
              onRetry: () {},
              onActivityTap: (_) {},
              formatter: _formatter,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hides the "View all" link when there is no destination', (
    tester,
  ) async {
    await _pump(tester, onViewAll: null);
    expect(find.text('View All'), findsNothing);
  });

  testWidgets('shows and fires "View all" when a destination exists', (
    tester,
  ) async {
    var tapped = false;
    await _pump(tester, onViewAll: () => tapped = true);
    expect(find.text('View All'), findsOneWidget);
    await tester.tap(find.text('View All'));
    expect(tapped, isTrue);
  });

  testWidgets('renders real user + client names from the reactv2 labels', (
    tester,
  ) async {
    // A `?reactv2` row: nested `{label, hashed_id}` objects, no flat ids.
    final activity = DashboardActivity.fromJson(<String, dynamic>{
      'activity_type_id': 1, // ":user created client :client"
      'id': '1',
      'created_at': 1783310471,
      'user': {'label': 'Ada Lovelace', 'hashed_id': 'u1'},
      'client': {'label': 'Acme Corp', 'hashed_id': 'c1'},
    });

    await _pump(
      tester,
      onViewAll: null,
      section: AsyncSection<List<DashboardActivity>>.ready([activity]),
    );

    // Tokens resolve to the real labels…
    expect(
      find.textContaining('Ada Lovelace created client Acme Corp'),
      findsOneWidget,
    );
    // …and the sentence names the client, so the meta line does not repeat
    // it.
    expect(find.textContaining('Acme Corp ·'), findsNothing);
    // …not the old placeholder-noun output ("… created client Client").
    expect(find.textContaining('created client Client'), findsNothing);
  });

  group('the redesigned rows', () {
    // Seconds since the epoch, `hoursAgo` before now.
    int ago({int hours = 0, int days = 0}) =>
        DateTime.now()
            .subtract(Duration(hours: hours, days: days))
            .millisecondsSinceEpoch ~/
        1000;

    DashboardActivity invoiceCreated({
      required String id,
      required int createdAt,
      String user = 'Carey Feest Danyka Terry',
    }) => DashboardActivity.fromJson(<String, dynamic>{
      'activity_type_id': 4, // ":user created invoice :invoice"
      'id': id,
      'created_at': createdAt,
      'user': {'label': user, 'hashed_id': 'u1'},
      'invoice': {'label': '0026', 'hashed_id': 'i$id'},
      'client': {'label': 'Kohler LLC', 'hashed_id': 'c1'},
    });

    testWidgets('the actor is one strong run; the client is on the meta line', (
      tester,
    ) async {
      // On the demo server a user's first AND last name are each a full fake
      // name, so the actor really is "Carey Feest Danyka Terry".
      await _pump(
        tester,
        onViewAll: null,
        section: AsyncSection<List<DashboardActivity>>.ready([
          invoiceCreated(id: '1', createdAt: ago(hours: 1)),
        ]),
      );

      final sentence = tester.widget<Text>(
        find.textContaining('created invoice 0026'),
      );
      final runs = (sentence.textSpan! as TextSpan).children!
          .cast<TextSpan>()
          .toList();
      final actor = runs.firstWhere(
        (r) => r.text == 'Carey Feest Danyka Terry',
      );
      expect(actor.style?.fontWeight, FontWeight.w600);
      expect(
        runs.firstWhere((r) => r.text == '0026').style?.fontWeight,
        FontWeight.w600,
      );
      // The client the template does not name rides the muted meta line.
      expect(find.textContaining('Kohler LLC · '), findsOneWidget);
    });

    testWidgets('rows sit under Today / Yesterday headers', (tester) async {
      final now = DateTime.now();
      // Safely inside today and inside yesterday whatever the clock says.
      final todayNoon = DateTime(now.year, now.month, now.day, 0, 1);
      final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
      await _pump(
        tester,
        onViewAll: null,
        section: AsyncSection<List<DashboardActivity>>.ready([
          invoiceCreated(
            id: '1',
            createdAt: todayNoon.millisecondsSinceEpoch ~/ 1000,
          ),
          invoiceCreated(
            id: '2',
            createdAt: yesterday.millisecondsSinceEpoch ~/ 1000,
          ),
        ]),
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Yesterday')).dy,
        greaterThan(tester.getTopLeft(find.text('Today')).dy),
      );
    });

    testWidgets('an older day is headed with the company date, never ISO', (
      tester,
    ) async {
      final now = DateTime.now();
      final older = DateTime(now.year, now.month, now.day - 5, 12);
      await _pump(
        tester,
        onViewAll: null,
        section: AsyncSection<List<DashboardActivity>>.ready([
          invoiceCreated(
            id: '1',
            createdAt: older.millisecondsSinceEpoch ~/ 1000,
          ),
        ]),
      );

      final iso =
          '${older.year}-${older.month.toString().padLeft(2, '0')}-'
          '${older.day.toString().padLeft(2, '0')}';
      expect(find.text(iso), findsNothing);
      expect(
        find.text(_formatter.date(iso)),
        findsOneWidget,
        reason: 'the header is Formatter.date output ("MMM d, yyyy")',
      );
      expect(_formatter.date(iso), isNot(contains('-')));
    });

    testWidgets('the whole row is the one tap target', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: ActivityCard(
                section: AsyncSection<List<DashboardActivity>>.ready([
                  invoiceCreated(id: '1', createdAt: ago(hours: 2)),
                ]),
                onViewAll: null,
                onRetry: () {},
                onActivityTap: (a) => tapped.add(a.id),
                formatter: _formatter,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The meta line, not the record number, still opens it.
      await tester.tap(find.textContaining('Kohler LLC · '));
      expect(tapped, ['1']);
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('the actor leads as initials, the verb as a corner badge', (
      tester,
    ) async {
      await _pump(
        tester,
        onViewAll: null,
        section: AsyncSection<List<DashboardActivity>>.ready([
          invoiceCreated(id: '1', createdAt: ago(hours: 1), user: 'Ada Byron'),
          // A contact's view names no user: nobody to draw.
          DashboardActivity.fromJson(<String, dynamic>{
            'activity_type_id': 7, // ":contact viewed invoice :invoice"
            'id': '2',
            'created_at': ago(hours: 2),
            'contact': {'label': 'Grace Hopper', 'hashed_id': 'k1'},
            'invoice': {'label': '0027', 'hashed_id': 'i2'},
            'client': {'label': 'Kohler LLC', 'hashed_id': 'c1'},
          }),
        ]),
      );

      final avatar = find.byType(InitialsAvatar);
      expect(avatar, findsOneWidget);
      final widget = tester.widget<InitialsAvatar>(avatar);
      // Seeded on the user's id, never the name, so the tint matches every
      // other surface that draws this user.
      expect(widget.seed, 'u1');
      expect(widget.label, 'AB');
      // The tone icon rides the avatar's corner, inside the row's leading
      // slot's reach.
      final badge = find.descendant(
        of: find.ancestor(of: avatar, matching: find.byType(Stack)).first,
        matching: find.byType(Icon),
      );
      expect(badge, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
