import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/comments_inbox_controller.dart';
import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/ui/features/comments_inbox/comments_inbox_sheet.dart';
import 'package:admin/ui/features/shell/widgets/comments_inbox_entry.dart';
import 'package:admin/ui/features/shell/widgets/sidebar_nav_item.dart';

import '../../../_localization_helper.dart';

/// The shell's comments inbox (docs/comments-and-activity.md § A teammate's
/// comment is new until you have seen it).
DashboardActivity _row(
  String id, {
  required String author,
  required int at,
  Map<String, Object> refs = const {},
}) => DashboardActivity.fromJson({
  'id': id.hashCode,
  'hashed_id': id,
  'activity_type_id': 141,
  'created_at': at,
  'notes': 'Note $id',
  'user': {'label': author == 'me' ? 'Me' : 'Pat Lee', 'hashed_id': author},
  ...refs,
});

const _onInvoice = {
  'invoice': {'label': '0012', 'hashed_id': 'inv1'},
  'client': {'label': 'Acme', 'hashed_id': 'c1'},
};

class _Harness {
  _Harness() {
    controller = CommentsInboxController(
      prefs: DevicePrefsStore(null),
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
              isAdmin: true,
              isOwner: false,
            ),
          ],
        ),
      ),
      watchFeed: (_) => feed.stream,
      watchFeedFetchedAt: (_) => const Stream<DateTime?>.empty(),
      refreshFeed: (_) async {},
      now: () => DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      debounce: Duration.zero,
    );
  }

  final feed = StreamController<List<DashboardActivity>?>.broadcast();
  late final CommentsInboxController controller;

  void dispose() {
    controller.dispose();
    unawaited(feed.close());
  }
}

Widget _app(CommentsInboxController controller, Widget child) =>
    ChangeNotifierProvider<CommentsInboxController>.value(
      value: controller,
      child: MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('the sidebar row is absent at zero and counts new comments', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      _app(
        h.controller,
        const SizedBox(
          width: 232,
          child: CommentsInboxSidebarRow(compact: false, touch: false),
        ),
      ),
    );
    await tester.pump();
    // Tracking starts at the first feed: what is already there is not new.
    h.feed.add([_row('old', author: 'them', at: 900, refs: _onInvoice)]);
    await tester.pump();
    expect(find.byType(SidebarNavItem), findsNothing);

    h.feed.add([
      _row('mine', author: 'me', at: 1300, refs: _onInvoice),
      _row('a', author: 'them', at: 1200, refs: _onInvoice),
      _row('b', author: 'them', at: 1100, refs: _onInvoice),
      _row('old', author: 'them', at: 900, refs: _onInvoice),
    ]);
    await tester.pump();
    final item = tester.widget<SidebarNavItem>(find.byType(SidebarNavItem));
    expect(item.count, 2);
    expect(item.label, 'Comments');
  });

  testWidgets('opening the inbox lists teammates, marks them read, and a row '
      'opens the record it was written on', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    final opened = <(EntityType, String)>[];
    await tester.pumpWidget(
      _app(
        h.controller,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommentsInbox(
              context,
              openRecord: (type, id) => opened.add((type, id)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    h.feed.add(const []);
    await tester.pump();
    h.feed.add([
      _row('a', author: 'them', at: 1200, refs: _onInvoice),
      _row(
        'c',
        author: 'them',
        at: 950,
        refs: {
          'client': {'label': 'Acme', 'hashed_id': 'c1'},
        },
      ),
    ]);
    await tester.pump();
    expect(h.controller.unreadCount, 1);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Note a'), findsOneWidget);
    expect(find.text('Note c'), findsOneWidget);
    // Who, and the record it is on — the invoice, not the client it was
    // copied to.
    expect(
      find.textContaining('Pat Lee · Invoice 0012', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pat Lee · Acme', findRichText: true),
      findsOneWidget,
    );
    // Only the comment newer than the baseline is marked.
    expect(find.textContaining('New · ', findRichText: true), findsOneWidget);
    expect(h.controller.unreadCount, 0, reason: 'opening it reads it');

    await tester.tap(find.text('Note a'));
    await tester.pumpAndSettle();
    expect(opened, [(EntityType.invoice, 'inv1')]);
    expect(find.text('Note a'), findsNothing, reason: 'the inbox closed');
  });

  testWidgets('an empty inbox says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: CommentsInboxList(
            comments: const [],
            freshIds: const {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('No recent comments from your team'), findsOneWidget);
  });

  testWidgets('the menu button wears a dot only while something is new', (
    tester,
  ) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      _app(h.controller, const CommentsInboxDot(child: Icon(Icons.menu))),
    );
    h.feed.add(const []);
    await tester.pump();
    Finder dot() => find.descendant(
      of: find.byType(CommentsInboxDot),
      matching: find.byType(PositionedDirectional),
    );
    expect(dot(), findsNothing);

    h.feed.add([_row('a', author: 'them', at: 1200, refs: _onInvoice)]);
    await tester.pump();
    // The event lands in a microtask after that frame; build the next.
    await tester.pump();
    expect(dot(), findsOneWidget);
  });
}
