import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/data/db/db_open_exception.dart';
import 'package:admin/data/db/open_failure.dart';

final _log = Logger('AppDatabase');

/// Notices a store that turns out corrupt **after** it opened, and marks it
/// so the next open repairs it.
///
/// `openAppDatabase` only sees what its probe and schema check touch:
/// `SELECT 1` and `PRAGMA table_info` read the schema page, not a damaged
/// table's own pages. A store whose `recurring_invoices` pages were malformed
/// opened cleanly, and the first statement to touch them — a sign-out wipe's
/// `DELETE FROM "recurring_invoices"` — failed with SQLITE_CORRUPT on every
/// launch, so no sign-in could finish (the web demo sat on /login).
///
/// Every statement goes through this interceptor once the open has settled
/// ([arm]); the first error [classifyDbOpenFailure] calls `corrupt` (SQLITE_
/// CORRUPT 11, SQLITE_NOTADB 26 — the same reading the open path uses) is
/// recorded through the platform's mark (`markStoreCorrupt`) and published on
/// [detected]. Nothing is repaired here: the next `openAppDatabase` reads the
/// mark and sends the store through the reset it already runs for a corrupt
/// open. Every error is rethrown untouched — this only watches.
class StoreCorruptionWatch extends QueryInterceptor {
  StoreCorruptionWatch({required Future<bool> Function() mark}) : _mark = mark;

  final Future<bool> Function() _mark;

  bool _armed = false;
  Future<bool>? _marking;
  final _detected = ValueNotifier<Object?>(null);

  /// The first corruption error seen since the open settled, or null.
  ValueListenable<Object?> get detected => _detected;

  /// Whether the mark for [detected] reached storage — false while nothing
  /// was detected, and false when the write failed. A boot that reloads to
  /// repair waits on this: reloading without a mark the next open can read
  /// would only find the same store again.
  Future<bool> get marked => _marking ?? Future<bool>.value(false);

  /// Start watching. Called once the open has settled on the store the app
  /// will use: an error during the open itself is the open path's to handle,
  /// and a mark written then could land after the reset that answered it.
  void arm() => _armed = true;

  void _observe(Object error) {
    if (!_armed || _marking != null) return;
    if (classifyDbOpenFailure(error) != DbOpenFailureKind.corrupt) return;
    _log.severe(
      'The local database is corrupt (found after it opened); marking it to '
      'be repaired at the next open',
      error,
    );
    _marking = _record();
    _detected.value = error;
  }

  Future<bool> _record() async {
    try {
      return await _mark();
    } catch (e, st) {
      _log.warning('Could not mark the local database for repair', e, st);
      return false;
    }
  }

  Future<T> _watch<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      _observe(e);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _watch(() => executor.runSelect(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _watch(() => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _watch(() => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _watch(() => executor.runDelete(statement, args));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _watch(() => executor.runCustom(statement, args));

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _watch(() => executor.runBatched(statements));

  @override
  Future<void> commitTransaction(TransactionExecutor inner) =>
      _watch(inner.send);
}
