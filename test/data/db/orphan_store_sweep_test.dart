import 'dart:async';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/db/orphan_store_sweep.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The web opener's `localStorage` and IndexedDB, in memory.
class _FakeBrowser {
  _FakeBrowser({required this.orphans});

  List<String> orphans;
  String live = 'invoiceninja_g3';
  final deleteCalls = <String>[];

  /// A delete that has not answered yet, per store name.
  final pending = <String, Completer<bool>>{};

  /// Stores the browser refuses to delete (the delete answers `false`).
  final held = <String>{};

  /// When true every delete waits on [pending] until the test answers it —
  /// the browser that holds a store until sqlite3's 1 s bound fires.
  bool slow = false;

  OrphanStoreSweep sweep() => OrphanStoreSweep(
    readOrphans: () => [...orphans],
    writeOrphans: (names) => orphans = [...names],
    liveName: () => live,
    deleteStore: (name) {
      deleteCalls.add(name);
      if (slow) return (pending[name] = Completer<bool>()).future;
      return Future.value(!held.contains(name));
    },
  );

  /// The web opener's `_abandonCurrentStore`.
  void abandonLive(String next) {
    orphans = [...orphans, live];
    live = next;
  }
}

void main() {
  group('OrphanStoreSweep', () {
    test('the database opens without waiting for a slow delete, and the sweep '
        'finishes afterwards', () async {
      final browser = _FakeBrowser(
        orphans: ['invoiceninja_g1', 'invoiceninja_g2'],
      )..slow = true;
      final sweep = browser.sweep();

      // The web opener's shape: the open takes the snapshot and opens; the
      // sweep is started apart from it (main.dart, after the first frame).
      // Here it starts alongside the open, the worst case.
      final opening = openAppDatabase(
        openExecutor: () async {
          sweep.snapshot();
          return NativeDatabase.memory();
        },
        destroyStore: () async => true,
      );
      var sweepDone = false;
      unawaited(sweep.run().then((_) => sweepDone = true));

      final opened = await opening;
      addTearDown(opened.db.close);
      await pumpEventQueue();

      expect(opened.wasReset, isFalse);
      expect(browser.deleteCalls, ['invoiceninja_g1']);
      expect(sweepDone, isFalse, reason: 'the delete has not answered');

      browser.pending['invoiceninja_g1']!.complete(true);
      await pumpEventQueue();
      browser.pending['invoiceninja_g2']!.complete(false);
      final outcome = await sweep.run();

      expect(sweepDone, isTrue);
      expect(outcome, (attempted: 2, swept: 1, remaining: 1));
      expect(browser.orphans, ['invoiceninja_g2'], reason: 'retried later');
    });

    test('never deletes the live store, and drops it from the list', () async {
      final browser = _FakeBrowser(
        orphans: ['invoiceninja_g1', 'invoiceninja_g3'],
      );
      final outcome = await browser.sweep().run();

      expect(browser.deleteCalls, ['invoiceninja_g1']);
      expect(browser.orphans, isEmpty);
      expect(outcome.swept, 1);
    });

    test(
      'a store abandoned while the sweep runs is kept for the next load',
      () async {
        final browser = _FakeBrowser(orphans: ['invoiceninja_g1'])..slow = true;
        final sweep = browser.sweep()..snapshot();
        final run = sweep.run();
        await pumpEventQueue();

        // A reset mid-sweep: the live store is abandoned, a new one opened.
        browser.abandonLive('invoiceninja_g4');
        browser.pending['invoiceninja_g1']!.complete(true);
        await run;

        expect(browser.orphans, ['invoiceninja_g3']);
        expect(browser.deleteCalls, isNot(contains('invoiceninja_g3')));
      },
    );

    test('the candidates are fixed by the first open of the load', () async {
      final browser = _FakeBrowser(orphans: ['invoiceninja_g1']);
      final sweep = browser.sweep()..snapshot();
      // This load's own reset abandons the store the page holds; deleting it
      // in this page would only time out.
      browser.abandonLive('invoiceninja_g4');
      sweep.snapshot();

      await sweep.run();

      expect(browser.deleteCalls, ['invoiceninja_g1']);
      expect(browser.orphans, ['invoiceninja_g3']);
    });

    test('runs once per load and never throws', () async {
      final browser = _FakeBrowser(orphans: ['invoiceninja_g1']);
      var calls = 0;
      final sweep = OrphanStoreSweep(
        readOrphans: () => [...browser.orphans],
        writeOrphans: (names) => browser.orphans = names,
        liveName: () => browser.live,
        deleteStore: (name) async {
          calls++;
          throw StateError('VfsException(1)');
        },
      );

      final first = await sweep.run();
      final second = await sweep.run();

      expect(calls, 1);
      expect(identical(first, second), isTrue);
      expect(first, (attempted: 1, swept: 0, remaining: 1));
      expect(browser.orphans, ['invoiceninja_g1']);
    });

    test('an ordinary load does nothing', () async {
      final browser = _FakeBrowser(orphans: []);
      expect(await browser.sweep().run(), kNoOrphanSweep);
      expect(browser.deleteCalls, isEmpty);
    });
  });
}
