import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/comments_inbox_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/db/dao/outbox_dao.dart';
import 'package:admin/data/models/api/activity_api_model.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/data/services/activities_api.dart';
import 'package:admin/domain/sync/mutation.dart';
import 'package:admin/ui/features/billing_shared/activity/entity_activity_view_model.dart';
import 'package:admin/ui/features/billing_shared/activity/entity_comments_card.dart';

import '../../../_localization_helper.dart';

/// The Comments card's "N new" tag — teammates' comments the user has not
/// seen on this record (docs/comments-and-activity.md § A teammate's comment
/// is new until you have seen it).
class _FakeApi implements ActivitiesApi {
  _FakeApi(this.rows);

  final List<ActivityApi> rows;

  @override
  List<ActivityApi>? peekForEntity({
    required String entity,
    required String entityId,
    Set<int>? activityTypeIds,
  }) => null;

  @override
  Future<List<ActivityApi>> fetchForEntity({
    required String entity,
    required String entityId,
    int rows = kEntityActivityRows,
    Set<int>? activityTypeIds,
  }) async => this.rows;

  @override
  bool isEntityUnsupported(String entity) => false;

  @override
  bool get ignoresActivityTypeFilter => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeOutbox implements OutboxDao {
  const _FakeOutbox();

  @override
  Stream<List<OutboxRow>> watchPendingForEntity({
    required String companyId,
    required String entityType,
    required String entityId,
    MutationKind? kind,
  }) => Stream<List<OutboxRow>>.multi((c) {
    c.add(const []);
    c.close();
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ActivityApi _comment(String id, {required String author, required int at}) =>
    ActivityApi(
      id: id,
      activityTypeId: kCommentActivityTypeId,
      notes: 'Comment $id',
      createdAt: at,
      user: ActivityLabelApi(
        label: author == 'me' ? 'Me' : 'Pat Lee',
        hashedId: author,
      ),
    );

CommentsInboxController _inbox(DevicePrefsStore prefs, {int now = 1000}) =>
    CommentsInboxController(
      prefs: prefs,
      session: ValueNotifier<AuthSession?>(
        const AuthSession(
          baseUrl: 'https://example.com',
          isHosted: true,
          accountId: 'acc',
          userId: 'me',
          currentCompanyId: 'co',
          companies: [
            AuthCompany(
              id: 'co',
              name: 'Co',
              displayName: 'Co',
              permissions: '',
              // Not an admin: the card's tracking doesn't depend on the
              // inbox, and no feed refresh timer is armed in the test.
              isAdmin: false,
              isOwner: false,
            ),
          ],
        ),
      ),
      watchFeed: (_) => const Stream<List<DashboardActivity>?>.empty(),
      watchFeedFetchedAt: (_) => const Stream<DateTime?>.empty(),
      refreshFeed: (_) async {},
      now: () => DateTime.fromMillisecondsSinceEpoch(now * 1000),
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<ActivityApi> rows,
  required CommentsInboxController? inbox,
}) async {
  final vm = EntityActivityViewModel(
    api: _FakeApi(rows),
    outbox: const _FakeOutbox(),
    companyId: 'co',
    entityWireName: 'invoice',
    entityId: 'inv1',
    kickDebounce: Duration.zero,
  );
  addTearDown(vm.dispose);
  vm.kick();
  Widget card = EntityCommentsCard(
    // A fresh element per pump, so each pump is a new visit.
    key: UniqueKey(),
    vm: vm,
    onViewAll: () {},
    hostWireName: 'invoice',
  );
  if (inbox != null) {
    card = ChangeNotifierProvider<CommentsInboxController>.value(
      value: inbox,
      child: card,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("tags teammates' comments newer than the last visit", (
    tester,
  ) async {
    final inbox = _inbox(DevicePrefsStore(null));
    addTearDown(inbox.dispose);
    await _pump(
      tester,
      inbox: inbox,
      rows: [
        _comment('a', author: 'them', at: 1200),
        _comment('b', author: 'them', at: 1100),
        _comment('old', author: 'them', at: 900),
      ],
    );
    expect(find.byType(NewCommentsTag), findsOneWidget);
    expect(find.text('2 new'), findsOneWidget);
    // Both rows on the card wear the "New".
    expect(find.textContaining('New · ', findRichText: true), findsNWidgets(2));
  });

  testWidgets('my own comments are never new, and zero draws no tag', (
    tester,
  ) async {
    final inbox = _inbox(DevicePrefsStore(null));
    addTearDown(inbox.dispose);
    await _pump(
      tester,
      inbox: inbox,
      rows: [_comment('mine', author: 'me', at: 1200)],
    );
    expect(find.text('Comment mine'), findsOneWidget);
    expect(find.byType(NewCommentsTag), findsNothing);
    expect(find.textContaining('New · ', findRichText: true), findsNothing);
  });

  testWidgets('seeing the card clears the tag for the next visit', (
    tester,
  ) async {
    final inbox = _inbox(DevicePrefsStore(null));
    addTearDown(inbox.dispose);
    final rows = [_comment('a', author: 'them', at: 1200)];

    await _pump(tester, inbox: inbox, rows: rows);
    expect(find.text('1 new'), findsOneWidget);
    expect(
      inbox.recordThreshold(companyId: 'co', wireName: 'invoice', id: 'inv1'),
      1200,
      reason: 'showing the card marked its newest comment seen',
    );

    await _pump(tester, inbox: inbox, rows: rows);
    expect(find.byType(NewCommentsTag), findsNothing);

    // A later comment from a teammate is new again.
    await _pump(
      tester,
      inbox: inbox,
      rows: [
        _comment('b', author: 'them', at: 1300),
        ...rows,
      ],
    );
    expect(find.text('1 new'), findsOneWidget);
  });

  testWidgets('a card offstage marks nothing', (tester) async {
    final inbox = _inbox(DevicePrefsStore(null));
    addTearDown(inbox.dispose);
    final vm = EntityActivityViewModel(
      api: _FakeApi([_comment('a', author: 'them', at: 1200)]),
      outbox: const _FakeOutbox(),
      companyId: 'co',
      entityWireName: 'invoice',
      entityId: 'inv1',
      kickDebounce: Duration.zero,
    );
    addTearDown(vm.dispose);
    vm.kick();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: TickerMode(
            enabled: false,
            child: ChangeNotifierProvider<CommentsInboxController>.value(
              value: inbox,
              child: EntityCommentsCard(vm: vm),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(
      inbox.recordThreshold(companyId: 'co', wireName: 'invoice', id: 'inv1'),
      1000,
    );
  });

  testWidgets('with no inbox above it, the card is unchanged', (tester) async {
    await _pump(
      tester,
      inbox: null,
      rows: [_comment('a', author: 'them', at: 1200)],
    );
    expect(find.text('Comment a'), findsOneWidget);
    expect(find.byType(NewCommentsTag), findsNothing);
  });
}
