import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/sidebar_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

import '_device_pref_controller_contract.dart';

/// Defaults to expanded.
void main() {
  devicePrefControllerContract(
    build: (prefs) => SidebarController(prefs: prefs),
    key: DevicePrefKeys.sidebarCollapsed,
    fallback: false,
    other: true,
  );

  test('toggle() flips and persists the collapsed flag', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await SidebarController(prefs: DevicePrefsStore(db)).toggle();

    final prefs = DevicePrefsStore(db);
    await prefs.load();
    expect(SidebarController(prefs: prefs).value, isTrue);
  });

  // Book posture on a foldable collapses the rail without touching the stored
  // preference, and the collapse button flips what the user sees
  // (docs/foldables.md).
  group('book posture', () {
    late AppDatabase db;
    late SidebarController sidebar;
    late List<bool> seen;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      sidebar = SidebarController(prefs: DevicePrefsStore(db));
      seen = [];
      sidebar.effective.addListener(() => seen.add(sidebar.effective.value));
    });

    tearDown(() async {
      sidebar.dispose();
      await db.close();
    });

    test('collapses the rail and leaves the preference alone', () {
      sidebar.setFoldCollapsed(true);
      expect(sidebar.effectiveValue, isTrue);
      expect(sidebar.value, isFalse);
      sidebar.setFoldCollapsed(false);
      expect(sidebar.effectiveValue, isFalse);
      expect(seen, [true, false]);
    });

    test('expanding in book posture is transient', () async {
      sidebar.setFoldCollapsed(true);
      await sidebar.toggle();
      expect(sidebar.effectiveValue, isFalse);
      expect(sidebar.value, isFalse, reason: 'nothing to persist');
      await sidebar.toggle();
      expect(sidebar.effectiveValue, isTrue);
      expect(sidebar.value, isFalse, reason: 'the fold collapsed it, not you');
    });

    test('an expand ends with the posture', () async {
      sidebar.setFoldCollapsed(true);
      await sidebar.toggle();
      sidebar.setFoldCollapsed(false);
      sidebar.setFoldCollapsed(true);
      expect(sidebar.effectiveValue, isTrue);
    });

    test('expanding over a stored "collapsed" clears it', () async {
      await sidebar.set(true);
      sidebar.setFoldCollapsed(true);
      await sidebar.toggle();
      expect(sidebar.effectiveValue, isFalse);
      expect(sidebar.value, isFalse);
    });

    test('collapsing again in posture restores a stored "collapsed"', () async {
      await sidebar.set(true);
      sidebar.setFoldCollapsed(true);
      await sidebar.toggle(); // expand — clears the stored collapse
      await sidebar.toggle(); // collapse again — the user's last word
      sidebar.setFoldCollapsed(false);
      expect(sidebar.value, isTrue);
      expect(sidebar.effectiveValue, isTrue);
    });

    test('no notification when the effective value does not change', () async {
      await sidebar.set(true);
      seen.clear();
      sidebar.setFoldCollapsed(true);
      sidebar.setFoldCollapsed(false);
      expect(seen, isEmpty);
    });
  });
}
