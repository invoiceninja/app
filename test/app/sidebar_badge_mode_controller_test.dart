import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/sidebar_badge_mode_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A relaunch: a new store, loaded from the same database.
  Future<SidebarBadgeModeController> relaunch() async {
    final prefs = DevicePrefsStore(db);
    await prefs.load();
    return SidebarBadgeModeController(prefs: prefs);
  }

  group('defaults', () {
    // A number on every row read as the size of the archive. Out of the box
    // only the three counts that are work waiting are badged.
    test('the actionable rows count work waiting; every other row is off', () {
      final controller = SidebarBadgeModeController();
      expect(controller.modeFor(EntityType.invoice), 'overdue');
      expect(controller.modeFor(EntityType.quote), 'expired');
      expect(controller.modeFor(EntityType.payment), 'unapplied');
      for (final type in [
        EntityType.client,
        EntityType.product,
        EntityType.credit,
        EntityType.task,
        EntityType.expense,
        EntityType.vendor,
      ]) {
        expect(controller.modeFor(type), kBadgeModeNone, reason: type.name);
      }
      expect(controller.hasOverrides, isFalse);
    });

    test('every actionable default is a mode its entity offers', () {
      for (final (type, modes) in [
        (EntityType.invoice, kInvoiceBadgeModes),
        (EntityType.quote, kQuoteBadgeModes),
        (EntityType.payment, kPaymentBadgeModes),
      ]) {
        final id = defaultBadgeModeFor(type);
        expect(id, isNot(kBadgeModeNone), reason: type.name);
        expect(modes.map((m) => m.id), contains(id), reason: type.name);
      }
      // And none, the default everywhere else, is on every list.
      for (final list in kAllSidebarBadgeModeLists) {
        expect(list.map((m) => m.id), contains(kBadgeModeNone));
      }
    });
  });

  group('persistence', () {
    test('a chosen mode survives a relaunch', () async {
      final controller = SidebarBadgeModeController(
        prefs: DevicePrefsStore(db),
      );
      await controller.set(EntityType.invoice, 'unpaid');
      await controller.set(EntityType.client, kBadgeModeTotal);

      final reloaded = await relaunch();
      expect(reloaded.modeFor(EntityType.invoice), 'unpaid');
      // Total is no longer the default, so choosing it is stored like any
      // other choice.
      expect(reloaded.modeFor(EntityType.client), kBadgeModeTotal);
    });

    test("choosing a row's default clears the stored entry rather than "
        'persisting it — defaults stay implicit so a mode added later needs no '
        'backfill', () async {
      final controller = SidebarBadgeModeController(
        prefs: DevicePrefsStore(db),
      );
      await controller.set(EntityType.invoice, kBadgeModeTotal);
      await controller.set(EntityType.invoice, 'overdue');
      await controller.set(EntityType.client, kBadgeModeTotal);
      await controller.set(EntityType.client, kBadgeModeNone);
      expect(controller.modesToJson(), isEmpty);
      expect(controller.hasOverrides, isFalse);
    });

    test('a stored value equal to the default is not an override', () {
      final controller = SidebarBadgeModeController()
        ..restoreFromJson('{"invoice": "overdue", "client": "none"}');
      expect(controller.modesToJson(), isEmpty);
      expect(controller.hasOverrides, isFalse);
      expect(controller.modeFor(EntityType.invoice), 'overdue');
    });

    test('resetAll puts every row back on its default', () async {
      final controller = SidebarBadgeModeController(
        prefs: DevicePrefsStore(db),
      );
      await controller.set(EntityType.invoice, kBadgeModeTotal);
      await controller.set(EntityType.quote, 'draft');
      await controller.set(EntityType.client, 'overdue');
      await controller.resetAll();

      final reloaded = await relaunch();
      expect(reloaded.modeFor(EntityType.invoice), 'overdue');
      expect(reloaded.modeFor(EntityType.quote), 'expired');
      expect(reloaded.modeFor(EntityType.client), kBadgeModeNone);
    });
  });

  group('notification', () {
    test('re-selecting the current mode does not notify', () async {
      final controller = SidebarBadgeModeController(
        prefs: DevicePrefsStore(db),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.set(EntityType.invoice, 'unpaid');
      expect(notifications, 1);
      await controller.set(EntityType.invoice, 'unpaid');
      expect(notifications, 1);
      // Re-selecting what the row already shows by default is no change.
      await controller.set(EntityType.quote, 'expired');
      expect(notifications, 1);
    });

    test('resetAll with nothing to reset does not notify', () async {
      final controller = SidebarBadgeModeController(
        prefs: DevicePrefsStore(db),
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.resetAll();
      expect(notifications, 0);
    });
  });

  group('defensive decoding', () {
    // A stored blob is user data from a previous release: it must never be
    // able to break boot, only to be ignored.
    test('garbage falls back to defaults', () {
      final controller = SidebarBadgeModeController();
      for (final blob in ['', 'not json', '[]', '{"invoice": 7}']) {
        controller.restoreFromJson(blob);
        expect(
          controller.modeFor(EntityType.invoice),
          'overdue',
          reason: 'blob: $blob',
        );
      }
    });

    test('an unknown mode id is dropped, not persisted forward', () {
      final controller = SidebarBadgeModeController()
        ..restoreFromJson('{"invoice": "mode_from_a_future_release"}');
      expect(controller.modeFor(EntityType.invoice), 'overdue');
      expect(controller.modesToJson(), isEmpty);
    });

    test('an unknown entity name is dropped', () {
      final controller = SidebarBadgeModeController()
        ..restoreFromJson('{"a_module_that_went_away": "overdue"}');
      expect(controller.modesToJson(), isEmpty);
    });
  });

  group('availability', () {
    test("a stored mode the company no longer offers falls back to the row's "
        'default — a stock counter has to stop being selected when inventory is '
        'switched off', () {
      final controller = SidebarBadgeModeController()
        ..restoreFromJson('{"product": "low_stock"}');
      expect(controller.modeFor(EntityType.product), 'low_stock');
      expect(
        controller.modeFor(
          EntityType.product,
          available: availableBadgeModes(
            kProductBadgeModes,
            trackInventory: false,
          ),
        ),
        kBadgeModeNone,
      );
      expect(
        controller.modeFor(
          EntityType.product,
          available: availableBadgeModes(
            kProductBadgeModes,
            trackInventory: true,
          ),
        ),
        'low_stock',
      );
    });
  });
}
