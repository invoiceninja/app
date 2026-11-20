import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/after_saving_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

import '../_support/device_prefs_test_support.dart';

/// "After Saving" (docs/after-saving.md, invoiceninja/app#202):
///   * null means automatic — the editor stays open except on a phone
///   * an explicit choice wins on either device, and survives a relaunch
///   * set() stores nothing when the choice is the device's automatic answer
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String?> storedRow() async =>
      (await db.devicePrefsDao.readAll())[DevicePrefKeys.afterSaving.name];

  test(
    'starts on automatic: stay on a tablet or desktop, leave on a phone',
    () {
      final controller = AfterSavingController(prefs: DevicePrefsStore(db));
      expect(controller.value, isNull);
      expect(controller.staysFor(isPhone: false), isTrue);
      expect(controller.staysFor(isPhone: true), isFalse);
    },
  );

  test('an explicit choice wins on either device', () {
    final view = AfterSavingController(
      prefs: prefsWith({DevicePrefKeys.afterSaving: false}),
    );
    expect(view.staysFor(isPhone: false), isFalse);
    final edit = AfterSavingController(
      prefs: prefsWith({DevicePrefKeys.afterSaving: true}),
    );
    expect(edit.staysFor(isPhone: true), isTrue);
  });

  test('a choice that differs from the device default persists and survives '
      'a relaunch', () async {
    await AfterSavingController(
      prefs: DevicePrefsStore(db),
    ).set(false, isPhone: false);
    expect(await storedRow(), '0');

    final prefs = DevicePrefsStore(db);
    final fresh = AfterSavingController(prefs: prefs);
    expect(fresh.value, isNull, reason: 'before the boot load');
    await prefs.load();
    expect(fresh.value, isFalse);
    expect(fresh.staysFor(isPhone: false), isFalse);
  });

  test('choosing what the device would pick anyway stores nothing, so it '
      'keeps adapting', () async {
    final controller = AfterSavingController(prefs: DevicePrefsStore(db));
    await controller.set(true, isPhone: true);
    expect(await storedRow(), '1');

    await controller.set(false, isPhone: true);
    expect(controller.value, isNull);
    expect(await storedRow(), isNull);
    // The same untouched setting now reads "stay" on a tablet.
    expect(controller.staysFor(isPhone: false), isTrue);
  });
}
