import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/comments_inbox_controller.dart';
import 'package:admin/data/models/domain/dashboard/dashboard_activity.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/data/repositories/auth/auth_session.dart';

AuthSession _session({
  String userId = 'me',
  String companyId = 'co',
  bool isAdmin = true,
}) => AuthSession(
  baseUrl: 'https://example.com',
  isHosted: true,
  accountId: 'acc',
  userId: userId,
  currentCompanyId: companyId,
  companies: [
    AuthCompany(
      id: companyId,
      name: 'Co',
      displayName: 'Co',
      permissions: '',
      isAdmin: isAdmin,
      isOwner: false,
    ),
  ],
);

DashboardActivity _row({
  required String id,
  required String author,
  required int at,
  int typeId = 141,
  String invoice = 'inv1',
}) => DashboardActivity.fromJson({
  'id': id.hashCode,
  'hashed_id': id,
  'activity_type_id': typeId,
  'created_at': at,
  'notes': 'note $id',
  'user': {'label': author == 'me' ? 'Me' : 'Pat', 'hashed_id': author},
  'invoice': {'label': '0012', 'hashed_id': invoice},
  'client': {'label': 'Acme', 'hashed_id': 'c1'},
});

class _Harness {
  _Harness({
    AuthSession? session,
    DevicePrefsStore? prefs,
    int nowSeconds = 900,
  }) : session = ValueNotifier<AuthSession?>(session ?? _session()),
       prefs = prefs ?? DevicePrefsStore(null),
       now = DateTime.fromMillisecondsSinceEpoch(nowSeconds * 1000) {
    controller = CommentsInboxController(
      prefs: this.prefs,
      session: this.session,
      watchFeed: (companyId) {
        watched.add(companyId);
        return feed.stream;
      },
      watchFeedFetchedAt: (_) => fetchedAt.stream,
      refreshFeed: (companyId) async => refreshed.add(companyId),
      refreshCycles: cycles,
      now: () => now,
      debounce: Duration.zero,
    );
  }

  final ValueNotifier<AuthSession?> session;
  final DevicePrefsStore prefs;
  DateTime now;
  final feed = StreamController<List<DashboardActivity>?>.broadcast();
  final fetchedAt = StreamController<DateTime?>.broadcast();
  final cycles = ValueNotifier<int>(0);
  final watched = <String>[];
  final refreshed = <String>[];
  late final CommentsInboxController controller;

  Future<void> emit(List<DashboardActivity>? rows) async {
    feed.add(rows);
    await pumpEventQueue();
  }

  void dispose() {
    controller.dispose();
    unawaited(feed.close());
    unawaited(fetchedAt.close());
  }
}

void main() {
  test('counts teammates comments newer than where tracking started', () async {
    final h = _Harness(nowSeconds: 900);
    addTearDown(h.dispose);
    await h.emit([
      _row(id: 'old', author: 'them', at: 800),
      _row(id: 'mine', author: 'me', at: 1100),
      _row(id: 'theirs', author: 'them', at: 1000),
      _row(id: 'system', author: 'them', at: 1200, typeId: 4),
    ]);

    expect(h.controller.comments.map((c) => c.id), ['theirs', 'old']);
    expect(h.controller.unreadCount, 1);
  });

  test('a first look at the feed calls nothing new', () async {
    final h = _Harness(nowSeconds: 5000);
    addTearDown(h.dispose);
    await h.emit([_row(id: 'theirs', author: 'them', at: 1000)]);
    expect(h.controller.comments, hasLength(1));
    expect(h.controller.unreadCount, 0);
  });

  test('opening the inbox reads every comment in it', () async {
    final h = _Harness(nowSeconds: 900);
    addTearDown(h.dispose);
    await h.emit([
      _row(id: 'a', author: 'them', at: 1000),
      _row(id: 'b', author: 'them', at: 1001),
    ]);
    expect(h.controller.unreadCount, 2);

    h.controller.markFeedSeen();
    expect(h.controller.unreadCount, 0);

    await h.emit([
      _row(id: 'c', author: 'them', at: 1002),
      _row(id: 'a', author: 'them', at: 1000),
      _row(id: 'b', author: 'them', at: 1001),
    ]);
    expect(h.controller.unreadCount, 1, reason: 'a later comment is new again');
  });

  test("seeing a record's card clears its comments from the count", () async {
    final h = _Harness(nowSeconds: 900);
    addTearDown(h.dispose);
    await h.emit([
      _row(id: 'a', author: 'them', at: 1000, invoice: 'inv1'),
      _row(id: 'b', author: 'them', at: 1000, invoice: 'inv2'),
    ]);
    expect(h.controller.unreadCount, 2);

    h.controller.markRecordSeen(
      companyId: 'co',
      wireName: 'invoice',
      id: 'inv1',
      upTo: 1000,
    );
    expect(h.controller.unreadCount, 1);
    expect(
      h.controller.recordThreshold(
        companyId: 'co',
        wireName: 'invoice',
        id: 'inv1',
      ),
      1000,
    );
  });

  test('read state is per user', () async {
    final prefs = DevicePrefsStore(null);
    final h = _Harness(prefs: prefs, nowSeconds: 900);
    addTearDown(h.dispose);
    h.controller.markRecordSeen(
      companyId: 'co',
      wireName: 'invoice',
      id: 'inv1',
      upTo: 1000,
    );
    expect(prefs.read(DevicePrefKeys.commentReads), contains('"user":"me"'));

    // Someone else on this device, with the first user's blob still stored.
    h.now = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
    h.session.value = _session(userId: 'other');
    expect(
      h.controller.recordThreshold(
        companyId: 'co',
        wireName: 'invoice',
        id: 'inv1',
      ),
      2000,
      reason: "the first user's stamp is not theirs; tracking starts now",
    );
  });

  test('a wipe forgets it, and the controller follows the store', () async {
    final prefs = DevicePrefsStore(null);
    final h = _Harness(prefs: prefs, nowSeconds: 900);
    addTearDown(h.dispose);
    h.controller.markRecordSeen(
      companyId: 'co',
      wireName: 'invoice',
      id: 'inv1',
      upTo: 1000,
    );
    prefs.forgetWiped();
    h.now = DateTime.fromMillisecondsSinceEpoch(1500 * 1000);
    expect(
      h.controller.recordThreshold(
        companyId: 'co',
        wireName: 'invoice',
        id: 'inv1',
      ),
      1500,
    );
  });

  test(
    'a non-admin gets no inbox: their feed holds only their own rows',
    () async {
      final h = _Harness(session: _session(isAdmin: false));
      addTearDown(h.dispose);
      await pumpEventQueue();
      expect(h.controller.enabled, isFalse);
      expect(h.watched, isEmpty);
      expect(h.refreshed, isEmpty);
      expect(h.controller.unreadCount, 0);
      // The record card still tracks for them.
      expect(
        h.controller.recordThreshold(
          companyId: 'co',
          wireName: 'invoice',
          id: 'inv1',
        ),
        isNotNull,
      );
    },
  );

  test('signed out: nothing counted, nothing tracked', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.session.value = null;
    await pumpEventQueue();
    expect(h.controller.enabled, isFalse);
    expect(
      h.controller.recordThreshold(
        companyId: 'co',
        wireName: 'invoice',
        id: 'inv1',
      ),
      isNull,
    );
  });

  group('refetching the feed', () {
    test('on activation, and after each completed delta refresh', () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await pumpEventQueue();
      expect(h.refreshed, ['co']);

      h.cycles.value++;
      await pumpEventQueue();
      expect(h.refreshed, ['co', 'co']);
    });

    test('not when anyone wrote the feed within the gap', () async {
      final h = _Harness(nowSeconds: 10000);
      addTearDown(h.dispose);
      await pumpEventQueue();
      h.refreshed.clear();

      h.fetchedAt.add(h.now.subtract(const Duration(seconds: 30)));
      await pumpEventQueue();
      h.cycles.value++;
      await pumpEventQueue();
      expect(h.refreshed, isEmpty);

      h.now = h.now.add(kCommentsInboxMinGap);
      h.cycles.value++;
      await pumpEventQueue();
      expect(h.refreshed, ['co']);
    });

    test('a failed refetch is swallowed', () async {
      final session = ValueNotifier<AuthSession?>(_session());
      final controller = CommentsInboxController(
        prefs: DevicePrefsStore(null),
        session: session,
        watchFeed: (_) => const Stream.empty(),
        watchFeedFetchedAt: (_) => const Stream.empty(),
        refreshFeed: (_) => Future.error(Exception('offline')),
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(controller.enabled, isTrue);
    });
  });
}
