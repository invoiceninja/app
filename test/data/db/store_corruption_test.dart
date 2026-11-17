import 'dart:io';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/db/database_opener_io.dart'
    show
        clearStoreCorruptMarkIn,
        listRetainedStoresIn,
        markStoreCorruptIn,
        storeMarkedCorruptIn;
import 'package:admin/data/db/db_open_exception.dart';
import 'package:admin/data/repositories/local_data_disposer.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '_corrupt_pages_interceptor.dart';

/// A store that opens cleanly and turns out corrupt later — the web demo's
/// failure: the open's probe and schema check never read a damaged table's
/// pages, so the first statement that did (a sign-out wipe's
/// `DELETE FROM "recurring_invoices"`) failed with SQLITE_CORRUPT on every
/// launch. Pins the watch that marks such a store, and the next open that
/// resets it through the reset a corrupt open already takes.
void main() {
  OutboxCompanion queued() => OutboxCompanion.insert(
    companyId: 'co',
    entityType: 'client',
    entityId: 'c_1',
    mutationKind: 'update',
    payload: '{}',
    idempotencyKey: 'k1',
    nextAttemptAt: 0,
    createdAt: 0,
  );

  group('after the open, the watch', () {
    late int marks;
    late OpenedDatabase opened;

    Future<void> openOver(CorruptPagesInterceptor pages) async {
      marks = 0;
      opened = await openAppDatabase(
        openExecutor: () async => NativeDatabase.memory().interceptWith(pages),
        destroyStore: () async => true,
        markCorrupt: () async {
          marks++;
          return true;
        },
      );
    }

    tearDown(() => opened.db.close());

    test('marks the store when a wipe hits a corrupt page', () async {
      await openOver(CorruptPagesInterceptor());

      await expectLater(
        LocalDataDisposer(opened.db).wipeAll(DisposalReason.sessionEnded),
        throwsA(isA<SqliteException>().having((e) => e.resultCode, 'code', 11)),
        reason: 'the watch only observes; the error still reaches the caller',
      );

      expect(marks, 1);
      expect(opened.corruption.detected.value, isA<SqliteException>());
      expect(await opened.corruption.marked, isTrue);
      expect(opened.wasReset, isFalse, reason: 'the open itself was clean');
    });

    test('marks once, however many statements fail', () async {
      await openOver(CorruptPagesInterceptor());
      for (var i = 0; i < 3; i++) {
        await expectLater(opened.db.wipe(), throwsA(isA<SqliteException>()));
      }
      expect(marks, 1);
    });

    test('ignores an error that is not corruption', () async {
      // A lock is not a damaged store: marking it would reset over a
      // condition a reload cures.
      await openOver(CorruptPagesInterceptor(code: 5));
      await expectLater(opened.db.wipe(), throwsA(isA<SqliteException>()));
      expect(marks, 0);
      expect(opened.corruption.detected.value, isNull);
      expect(await opened.corruption.marked, isFalse);
    });

    test('reads SQLITE_NOTADB as corruption too', () async {
      await openOver(CorruptPagesInterceptor(code: 26));
      await expectLater(opened.db.wipe(), throwsA(isA<SqliteException>()));
      expect(marks, 1);
    });

    test('says so when the mark could not be written', () async {
      opened = await openAppDatabase(
        openExecutor: () async =>
            NativeDatabase.memory().interceptWith(CorruptPagesInterceptor()),
        destroyStore: () async => true,
        markCorrupt: () async => throw const FileSystemException('read-only'),
      );
      await expectLater(opened.db.wipe(), throwsA(isA<SqliteException>()));
      expect(opened.corruption.detected.value, isNotNull);
      expect(await opened.corruption.marked, isFalse);
    });
  });

  group('the next open, with the store marked', () {
    late bool markStored;
    late int destroyed;
    late bool storeIsCorrupt;

    setUp(() {
      markStored = true;
      destroyed = 0;
      storeIsCorrupt = true;
    });

    Future<OpenedDatabase> open({
      QueryExecutor Function()? corruptStore,
      bool waitsForOutbox = false,
      bool destroyWorks = true,
    }) => openAppDatabase(
      openExecutor: () async => storeIsCorrupt
          ? (corruptStore?.call() ??
                NativeDatabase.memory().interceptWith(
                  CorruptPagesInterceptor(),
                ))
          : NativeDatabase.memory(),
      destroyStore: () async {
        destroyed++;
        if (destroyWorks) storeIsCorrupt = false;
        return destroyWorks;
      },
      markCorrupt: () async => markStored = true,
      readCorruptMark: () async => markStored,
      clearCorruptMark: () async => markStored = false,
      corruptResetWaitsForOutbox: waitsForOutbox,
    );

    test('resets a store quick_check fails, and takes the mark', () async {
      final opened = await open();
      expect(destroyed, 1);
      expect(opened.wasReset, isTrue);
      expect(opened.hadCorruptMark, isTrue);
      expect(markStored, isFalse);
      // The fresh store is the one the app runs on, and it is sound.
      await opened.db.wipe();
      expect(opened.corruption.detected.value, isNull);
      await opened.db.close();
    });

    test('resets a store whose quick_check itself fails as corrupt', () async {
      final opened = await open(
        corruptStore: () => NativeDatabase.memory().interceptWith(
          CorruptPagesInterceptor(quickCheckThrows: true),
        ),
      );
      expect(destroyed, 1);
      expect(opened.wasReset, isTrue);
      await opened.db.close();
    });

    test('keeps a store quick_check passes, and drops the mark', () async {
      final opened = await open(
        corruptStore: () => NativeDatabase.memory(), // sound after all
      );
      expect(destroyed, 0, reason: 'a mark is a suspicion, not a verdict');
      expect(opened.wasReset, isFalse);
      expect(opened.hadCorruptMark, isTrue);
      expect(markStored, isFalse);
      await opened.db.close();
    });

    test('a lock during quick_check leaves the store and the mark', () async {
      await expectLater(
        open(
          corruptStore: () => NativeDatabase.memory().interceptWith(
            CorruptPagesInterceptor(quickCheckThrows: true, code: 5),
          ),
        ),
        throwsA(
          isA<DatabaseUnavailableException>().having(
            (e) => e.kind,
            'kind',
            DbOpenFailureKind.transient,
          ),
        ),
      );
      expect(destroyed, 0);
      expect(markStored, isTrue);
    });

    test('an unmarked store is never checked', () async {
      markStored = false;
      final opened = await open();
      expect(destroyed, 0);
      expect(opened.hadCorruptMark, isFalse);
      await opened.db.close();
    });

    test('a reset that fails keeps the mark for the next open', () async {
      await expectLater(
        open(destroyWorks: false),
        throwsA(isA<DatabaseResetFailedException>()),
      );
      expect(markStored, isTrue);
    });

    group('where a reset carries nothing across (web)', () {
      late Directory dir;

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('corrupt_mark_');
      });

      tearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      /// A store on disk, so the outbox seeded before the open is the one the
      /// open finds.
      QueryExecutor corruptFile() => NativeDatabase(
        File('${dir.path}/store.sqlite'),
      ).interceptWith(CorruptPagesInterceptor());

      Future<void> seedOutbox() async {
        final db = AppDatabase(
          NativeDatabase(File('${dir.path}/store.sqlite')),
        );
        await db.outboxDao.enqueue(queued());
        await db.close();
      }

      test(
        'keeps a corrupt store, marked, while its outbox holds work',
        () async {
          await seedOutbox();
          final opened = await open(
            corruptStore: corruptFile,
            waitsForOutbox: true,
          );
          expect(
            destroyed,
            0,
            reason: 'a reset here loses the unsynced change',
          );
          expect(opened.wasReset, isFalse);
          expect(markStored, isTrue, reason: 'reset once the outbox drains');
          expect(await opened.db.outboxDao.hasAnyRows(), isTrue);
          await opened.db.close();
        },
      );

      test('resets it once the outbox is empty', () async {
        final opened = await open(
          corruptStore: corruptFile,
          waitsForOutbox: true,
        );
        expect(destroyed, 1);
        expect(opened.wasReset, isTrue);
        expect(markStored, isFalse);
        await opened.db.close();
      });
    });
  });

  group('the native mark', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('corrupt_mark_io_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('is written, read and cleared beside the store', () async {
      expect(await storeMarkedCorruptIn(dir), isFalse);
      expect(await markStoreCorruptIn(dir), isTrue);
      expect(await storeMarkedCorruptIn(dir), isTrue);
      await clearStoreCorruptMarkIn(dir);
      expect(await storeMarkedCorruptIn(dir), isFalse);
      // Clearing nothing is not an error.
      await clearStoreCorruptMarkIn(dir);
    });

    test(
      'is not a kept copy, so pruning and Device Settings ignore it',
      () async {
        await markStoreCorruptIn(dir);
        expect(await listRetainedStoresIn(dir), isEmpty);
      },
    );
  });
}
