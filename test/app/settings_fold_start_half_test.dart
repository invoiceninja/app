// `settingsFoldStartHalf` (lib/app/router.dart) measures the settings menu's
// half before a book-posture fold. The router's redirect asks it, and so does
// a settings-hosted list deciding its back arrow — from inside the shell, where
// the fold was re-based past the rail, or inside half of a split, where it was
// removed. Every caller must get the window's answer, the one `SettingsShell`
// splits on, or the arrow points at a `/settings` that redirects away
// (docs/foldables.md).

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:admin/app/router.dart' show settingsFoldStartHalf;
import 'package:admin/app/sidebar_controller.dart';
import 'package:admin/data/db/app_database.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// An open iPhone Duo: 951 wide, its 40 pt division at 455–495.
const _window = MediaQueryData(
  size: Size(951, 669),
  displayFeatures: [
    DisplayFeature(
      bounds: Rect.fromLTWH(455, 0, 40, 669),
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.postureHalfOpened,
    ),
  ],
);

void main() {
  late AppDatabase db;
  late SidebarController sidebar;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sidebar = SidebarController(prefs: DevicePrefsStore(db))
      ..setFoldCollapsed(true);
  });

  tearDown(() async {
    sidebar.dispose();
    await db.close();
  });

  /// Measures from a context inside the shell, where [inner] has rewritten
  /// the MediaQuery the way the app does — the content re-base, or half of a
  /// split with the fold removed — under a root navigator that sees the window.
  Future<double?> measure(
    WidgetTester tester, {
    required TextDirection direction,
    MediaQueryData Function(MediaQueryData window)? inner,
  }) async {
    double? half;
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: _window,
          // A fresh Navigator each time: its route closure captures `half`.
          child: Navigator(
            key: UniqueKey(),
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (context, _, _) => MediaQuery(
                data: inner == null ? _window : inner(_window),
                child: Builder(
                  builder: (context) {
                    half = settingsFoldStartHalf(context, sidebar);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return half;
  }

  MediaQueryData rebased(MediaQueryData w) => rebaseDisplayFeatures(w, -64);

  // Half of a master-detail or settings split: the fold is gone.
  MediaQueryData listHalf(MediaQueryData w) =>
      foldHalfMediaQuery(w, const Rect.fromLTWH(0, 0, 391, 669), 887);

  testWidgets('left-to-right: the same number from anywhere', (tester) async {
    // 455 − 64 (the collapsed rail) = 391.
    for (final inner in [null, rebased, listHalf]) {
      expect(
        await measure(tester, direction: TextDirection.ltr, inner: inner),
        391,
      );
    }
  });

  testWidgets('right-to-left: the menu takes the right-hand half', (
    tester,
  ) async {
    // (951 − 64) − 495 = 392.
    for (final inner in [null, listHalf]) {
      expect(
        await measure(tester, direction: TextDirection.rtl, inner: inner),
        392,
      );
    }
  });

  testWidgets('no book posture, no half', (tester) async {
    sidebar.setFoldCollapsed(false);
    expect(await measure(tester, direction: TextDirection.ltr), isNull);
  });
}
