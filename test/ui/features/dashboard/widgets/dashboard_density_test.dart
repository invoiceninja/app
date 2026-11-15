import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/list_density_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/features/activity/widgets/activity_feed_row.dart';
import 'package:admin/ui/features/dashboard/helpers/activity_formatter.dart';
import 'package:admin/ui/features/dashboard/view_models/async_section.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_density.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_figures.dart';
import 'package:admin/ui/features/dashboard/widgets/dashboard_record_row.dart';
import 'package:admin/ui/features/dashboard/widgets/list_card.dart';

import '../../../../_localization_helper.dart';

/// Compact on the dashboard (`docs/list-density.md` § The dashboard),
/// measured on the real widgets: a pointer row reaches its 32 px floor, a
/// touch row never drops under the 44 px target, a figure card's floor stays
/// a floor at a large text size, and the card shell tightens only on the
/// dashboard — the edit forms that share it keep their size.
///
/// `flutter_test` defaults to Android (touch), so the pointer cases run as
/// macOS.
void main() {
  final pointer = TargetPlatformVariant.only(TargetPlatform.macOS);

  late AppDatabase db;
  late ListDensityController density;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final prefs = DevicePrefsStore(db);
    await prefs.load();
    density = ListDensityController(prefs: prefs);
  });
  tearDown(() async {
    density.dispose();
    await db.close();
  });

  /// [onDashboard] false leaves out the [DashboardScope] marker — what an edit
  /// form that reuses [DashboardCardShell] looks like.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required bool compact,
    bool onDashboard = true,
    double textScale = 1,
  }) async {
    await density.setCompact(compact);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: ListDensityScope(controller: density, child: inner!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: onDashboard ? DashboardScope(child: child) : child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const rowKey = Key('row');
  Widget row({bool stacked = false}) => DashboardRecordRow(
    key: rowKey,
    number: '0042',
    client: 'Acme',
    lead: 'Due today',
    amount: r'$1,200.00',
    onTap: () {},
    compact: false,
    stacked: stacked,
    actions: [
      RecordRowAction(
        icon: Icons.send_outlined,
        tooltipKey: 'send',
        onRun: () async {},
      ),
    ],
  );
  double rowHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(rowKey)).height;

  group('DashboardRecordRow', () {
    testWidgets('Normal is unchanged: 44 with a pointer', (tester) async {
      await pump(tester, row(), compact: false);
      expect(rowHeight(tester), 44);
    }, variant: pointer);

    testWidgets('Compact is 32 with a pointer', (tester) async {
      await pump(tester, row(), compact: true);
      expect(rowHeight(tester), 32);
    }, variant: pointer);

    testWidgets('Compact on touch never drops under the target', (
      tester,
    ) async {
      await pump(tester, row(), compact: true);
      expect(rowHeight(tester), InSizes.touchTarget);
    });

    testWidgets('a stacked row is 52 under Compact with a pointer', (
      tester,
    ) async {
      await pump(tester, row(stacked: true), compact: true);
      expect(rowHeight(tester), 52);
    }, variant: pointer);

    testWidgets('a stacked row is 64 under Compact on touch', (tester) async {
      await pump(tester, row(stacked: true), compact: true);
      expect(rowHeight(tester), 64);
    });

    test('the floor helpers agree with the rendered rows', () {
      expect(dashboardRecordRowExtent(compact: true, dense: true), 52);
      expect(dashboardRecordRowExtent(compact: true), 60);
    });
  });

  group('OutstandingFigureCard', () {
    const cardKey = Key('figure');
    Widget card() => const OutstandingFigureCard(
      key: cardKey,
      state: ValueSectionState.ready,
      value: r'$57,905.00',
      caption: '17 unpaid',
      valueFontSize: 22,
    );

    testWidgets('Compact puts the caption on the value line', (tester) async {
      await pump(tester, card(), compact: true);
      final value = tester.getRect(find.text(r'$57,905.00'));
      final caption = tester.getRect(find.text('17 unpaid'));
      expect(caption.left, greaterThan(value.right));
      expect(caption.center.dy, closeTo(value.center.dy, 4));
      expect(tester.getSize(find.byKey(cardKey)).height, lessThan(72));
    }, variant: pointer);

    testWidgets('its floor is a floor: 2x text grows the card', (tester) async {
      await pump(tester, card(), compact: true);
      final atOne = tester.getSize(find.byKey(cardKey)).height;
      await pump(tester, card(), compact: true, textScale: 2);
      expect(tester.getSize(find.byKey(cardKey)).height, greaterThan(atOne));
    }, variant: pointer);

    testWidgets('Normal keeps the caption under the value', (tester) async {
      await pump(tester, card(), compact: false);
      final value = tester.getRect(find.text(r'$57,905.00'));
      final caption = tester.getRect(find.text('17 unpaid'));
      expect(caption.top, greaterThanOrEqualTo(value.bottom));
      expect(
        tester.getSize(find.byKey(cardKey)).height,
        greaterThanOrEqualTo(kFigureCardMinHeight),
      );
    }, variant: pointer);
  });

  group('DashboardCardShell', () {
    const shellKey = Key('shell');
    Widget shell() => const DashboardCardShell(
      key: shellKey,
      title: 'Panel',
      child: SizedBox(height: 20),
    );
    BoxDecoration decoration(WidgetTester tester) =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(shellKey),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    testWidgets('on the dashboard: no shadow, and Compact is tighter', (
      tester,
    ) async {
      await pump(tester, shell(), compact: false);
      final normal = tester.getSize(find.byKey(shellKey)).height;
      expect(decoration(tester).boxShadow, isNull);

      await pump(tester, shell(), compact: true);
      expect(tester.getSize(find.byKey(shellKey)).height, lessThan(normal));
      expect(decoration(tester).boxShadow, isNull);
      expect(
        decoration(tester).borderRadius,
        BorderRadius.circular(InRadii.r2),
      );
    }, variant: pointer);

    testWidgets('off the dashboard (an edit form) Compact changes nothing', (
      tester,
    ) async {
      await pump(tester, shell(), compact: false, onDashboard: false);
      final normal = tester.getSize(find.byKey(shellKey)).height;

      await pump(tester, shell(), compact: true, onDashboard: false);
      expect(tester.getSize(find.byKey(shellKey)).height, normal);
      expect(
        decoration(tester).borderRadius,
        BorderRadius.circular(InRadii.r3),
      );
      expect(decoration(tester).boxShadow, isNotEmpty);
    }, variant: pointer);
  });

  group('ActivityFeedRow.cardDense', () {
    const activityKey = Key('activity');
    Widget activity() => ActivityFeedRow(
      key: activityKey,
      render: const ActivityRender(
        title: 'Ada created invoice 0025',
        meta: '3 h ago',
        tone: ActivityTone.sent,
        icon: Icons.edit_outlined,
      ),
      meta: '3 h ago',
      density: ActivityRowDensity.cardDense,
      onTap: () {},
    );

    testWidgets('is shorter than the card row with a pointer', (tester) async {
      await pump(tester, activity(), compact: true);
      expect(
        tester.getSize(find.byKey(activityKey)).height,
        lessThan(InSizes.touchTarget),
      );
    }, variant: pointer);

    testWidgets('keeps the 44 px target on touch', (tester) async {
      await pump(tester, activity(), compact: true);
      expect(
        tester.getSize(find.byKey(activityKey)).height,
        greaterThanOrEqualTo(InSizes.touchTarget),
      );
    });
  });

  group('DashboardListCard', () {
    Widget card({int? preview}) => DashboardListCard<int>(
      title: 'Upcoming',
      section: AsyncSection<List<int>>.ready(List.generate(12, (i) => i)),
      emptyTitle: 'None',
      preview: preview,
      bodyBuilder: (context, rows) =>
          Column(children: [for (final r in rows) Text('row $r')]),
    );

    testWidgets('shows 5 rows under Normal', (tester) async {
      await pump(tester, card(), compact: false);
      expect(find.textContaining('row '), findsNWidgets(5));
    });

    testWidgets('shows $kDensePanelRows rows under Compact', (tester) async {
      await pump(tester, card(), compact: true);
      expect(find.textContaining('row '), findsNWidgets(kDensePanelRows));
    });

    testWidgets('an explicit count (the phone) wins', (tester) async {
      await pump(tester, card(preview: 3), compact: true);
      expect(find.textContaining('row '), findsNWidgets(3));
    });
  });
}
