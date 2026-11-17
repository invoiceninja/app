import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/db/store_corruption.dart';

final _log = Logger('main.boot');

/// What boot does about a store that turned out corrupt after it opened.
enum CorruptStoreBootStep {
  /// Nothing found, or nothing to do before the next launch: start the app.
  carryOn,

  /// Reload the page: the next open reads the mark and resets the store.
  reload,

  /// The reload was already spent, or could not work: show the boot screen
  /// for a corrupt store, whose Try again and Reset are the user's to press.
  showRepairScreen,
}

/// Bound on the outbox read and the mark write this waits on: it sits in
/// front of `runApp`, and boot must always paint.
const _kStepBudget = Duration(seconds: 5);

/// Decide, once boot's session phases are over (the restore, the demo
/// sign-in), what to do about corruption [corruption] met during them.
///
/// Only web reloads: nothing is in memory before `runApp`, and the reload's
/// open runs the reset `openAppDatabase` already has. Native has no in-place
/// reload; the mark repairs the store at the next launch, and the app starts
/// meanwhile so the outbox can still drain.
///
/// At most one automatic reload per launch: a launch whose open already
/// found a mark ([hadCorruptMark]) never reloads again — the reset did not
/// cure it — and neither does one whose mark did not reach storage, since the
/// next open could not see it. Either gets [CorruptStoreBootStep.showRepairScreen].
///
/// When the reset would lose unsynced work ([corruptStoreMayReset] with
/// [waitsForOutbox]), this carries on: the open keeps such a store until its
/// outbox drains, so a reload would change nothing.
Future<CorruptStoreBootStep> corruptStoreBootStep({
  required StoreCorruptionWatch corruption,
  required AppDatabase db,
  required bool hadCorruptMark,
  required bool waitsForOutbox,
  bool isWeb = kIsWeb,
}) async {
  if (corruption.detected.value == null) return CorruptStoreBootStep.carryOn;
  if (!isWeb) {
    _log.warning(
      'The local database is corrupt; it is repaired at the next launch',
    );
    return CorruptStoreBootStep.carryOn;
  }
  try {
    if (!await corruptStoreMayReset(
      db,
      waitsForOutbox: waitsForOutbox,
    ).timeout(_kStepBudget)) {
      return CorruptStoreBootStep.carryOn;
    }
  } catch (e, st) {
    _log.warning('Could not tell whether the outbox is empty', e, st);
    return CorruptStoreBootStep.carryOn;
  }
  if (hadCorruptMark) {
    _log.severe('The local database is still corrupt after its repair');
    return CorruptStoreBootStep.showRepairScreen;
  }
  final bool marked;
  try {
    marked = await corruption.marked.timeout(_kStepBudget);
  } catch (e, st) {
    _log.warning('Marking the local database for repair timed out', e, st);
    return CorruptStoreBootStep.showRepairScreen;
  }
  if (!marked) return CorruptStoreBootStep.showRepairScreen;
  _log.warning('The local database is corrupt; reloading to repair it');
  return CorruptStoreBootStep.reload;
}
