import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/mobile_app_promo_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';
import 'package:admin/domain/desktop_app_promo.dart';
import 'package:admin/domain/mobile_app_promo.dart';
import 'package:admin/domain/web_app_banner.dart';
import 'package:admin/ui/core/widgets/copy_value_row.dart';
import 'package:admin/ui/features/mobile_promo/desktop_app_promo_dialog.dart';
import 'package:admin/ui/features/mobile_promo/mobile_app_promo_dialog.dart';

import '../../../_localization_helper.dart';

/// Every computer with a listing: the launch switch's state.
String? _allListed(NativeAppPlatform p) => switch (p) {
  NativeAppPlatform.mac => 'https://testflight.apple.com/join/mac',
  NativeAppPlatform.windows => 'https://example.com/windows',
  NativeAppPlatform.linux => 'https://flathub.org/apps/x',
  _ => null,
};

const _apple = [DesktopPromoTarget.mac];
const _android = DesktopPromoTarget.values;

/// What an Apple build must never show or speak (guideline 2.3.10), and —
/// since Windows and Linux are left off the Apple builds — their names and
/// stores too.
final _notOnApple = RegExp(
  'Android|Google|Windows|Linux|Microsoft|Flathub|Snap',
  caseSensitive: false,
);

/// The keys the Apple surface renders: anything the dialog draws with only
/// the Mac to offer, from its pitch to its footer.
const _appleSurfaceKeys = [
  'desktop_app_promo_title',
  'desktop_app_promo_subtitle',
  'desktop_app_promo_screen_title',
  'desktop_app_promo_screen_body',
  'desktop_app_promo_keyboard_title',
  'desktop_app_promo_keyboard_body',
  'desktop_app_promo_send_hint',
  'desktop_app_promo_share',
  'desktop_app_promo_copy',
  'desktop_app_promo_link_label',
  'desktop_app_promo_mac_testflight_step',
  'desktop_app_promo_mac_store_step',
  'desktop_app_promo_server_url',
  'desktop_app_promo_same_network',
  'desktop_app_promo_entry',
  'desktop_app_promo_section',
  'desktop_app_promo_settings_body',
];

/// Shared keys the Apple surface renders too: the close tooltip and the
/// footer, whose translations live in the locale bundles as well as the
/// app-local ones.
const _appleSharedKeys = [
  'close',
  'mobile_app_promo_remind_later',
  'mobile_app_promo_dont_show_again',
];

class _Harness {
  Future<MobilePromoResult?>? result;
  late MobileAppPromoController controller;

  Future<void> open(
    WidgetTester tester, {
    List<DesktopPromoTarget> targets = _apple,
    MobilePromoAccount account = const MobilePromoAccount(),
    bool isManual = false,
    int closes = 0,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller = MobileAppPromoController(prefs: DevicePrefsStore(null));
    addTearDown(controller.dispose);
    for (var i = 0; i < closes; i++) {
      await controller.snooze(DateTime.utc(2026, 10, 14, 12));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => result = showDialog<MobilePromoResult>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DesktopAppPromoDialog(
                    targets: targets,
                    account: account,
                    controller: controller,
                    isManual: isManual,
                    urlOf: _allListed,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

List<String> _everything(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final t in tester.widgetList<RichText>(find.byType(RichText)))
    t.text.toPlainText(),
  for (final t in tester.widgetList<Tooltip>(find.byType(Tooltip)))
    t.message ?? '',
  for (final s in tester.widgetList<Semantics>(find.byType(Semantics)))
    s.properties.label ?? '',
];

/// Records what reaches the clipboard. The share sheet has no plugin under
/// test, so Share falls back to the clipboard too.
List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  // The layout checks measure real text: the test font draws every glyph a
  // full em wide, which wraps everything and says nothing about a phone.
  setUpAll(() async {
    await (FontLoader('Inter Tight')..addFont(
          File(
            'assets/fonts/InterTight.ttf',
          ).readAsBytes().then((b) => ByteData.view(b.buffer)),
        ))
        .load();
  });

  group('Apple builds (App Review 2.3.10)', () {
    testWidgets('offer the Mac only, and name no other platform or store '
        'anywhere — text, tooltip, semantics or copied link', (tester) async {
      final copied = _captureClipboard(tester);
      final h = _Harness();
      await h.open(
        tester,
        account: const MobilePromoAccount(
          serverUrl: 'http://192.168.1.20',
          privateNetwork: true,
        ),
      );

      expect(find.byType(SegmentedButton<DesktopPromoTarget>), findsNothing);
      expect(
        find.textContaining('On your Mac, the link opens TestFlight'),
        findsOneWidget,
      );
      for (final s in _everything(tester)) {
        expect(s, isNot(matches(_notOnApple)), reason: s);
      }

      await tester.tap(find.text('Copy link'));
      await tester.pump();
      await tester.tap(find.text('Share link'));
      // No share plugin under test: the sheet throws on the real event loop,
      // and the clipboard takes the link instead.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(copied, hasLength(2));
      for (final link in copied) {
        expect(link, _allListed(NativeAppPlatform.mac));
      }
      for (final s in _everything(tester)) {
        expect(s, isNot(matches(_notOnApple)), reason: s);
      }
      await tester.pump(const Duration(seconds: 5));
    });

    test('no locale\'s Apple-surface string names another platform or '
        'store', () {
      // Every bundle, not only the app-local ones: a shared key's
      // translation comes from the locale's own file.
      final files = Directory(
        'assets/i18n',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      for (final file in files) {
        final json = (jsonDecode(file.readAsStringSync()) as Map)
            .cast<String, Object?>();
        for (final key in [..._appleSurfaceKeys, ..._appleSharedKeys]) {
          final value = json[key];
          if (value is! String) continue;
          expect(
            value,
            isNot(matches(_notOnApple)),
            reason: '${file.path}: $key',
          );
        }
      }
    });

    test('the English has every Apple-surface key', () {
      final en =
          (jsonDecode(File('assets/i18n/_app_pending.json').readAsStringSync())
                  as Map)
              .cast<String, Object?>();
      for (final key in _appleSurfaceKeys) {
        expect(en[key], isA<String>(), reason: key);
      }
    });
  });

  group('Android', () {
    testWidgets('offers every listed computer, and each one\'s link', (
      tester,
    ) async {
      final copied = _captureClipboard(tester);
      final h = _Harness();
      await h.open(tester, targets: _android);

      expect(find.byType(SegmentedButton<DesktopPromoTarget>), findsOneWidget);
      expect(find.text('Windows'), findsOneWidget);
      expect(find.text('Mac'), findsOneWidget);
      expect(find.text('Linux'), findsOneWidget);
      expect(
        find.text('On your PC, the link opens the Microsoft Store.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Linux'));
      await tester.pump();
      expect(find.textContaining('The link opens Flathub'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(copied.last, _allListed(NativeAppPlatform.linux));

      await tester.tap(find.text('Mac'));
      await tester.pump();
      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(copied.last, _allListed(NativeAppPlatform.mac));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the schedule', () {
    testWidgets('an automatic open snoozes on Remind me later', (tester) async {
      final h = _Harness();
      await h.open(tester);
      expect(find.text("Don't show again"), findsOneWidget);
      await tester.tap(find.text('Remind me later'));
      await tester.pumpAndSettle();
      expect(await h.result, MobilePromoResult.snoozed);
    });

    testWidgets('sharing the link takes the app: the automatic opens end', (
      tester,
    ) async {
      _captureClipboard(tester);
      final h = _Harness();
      await h.open(tester);
      await tester.tap(find.text('Share link'));
      await tester.pump();
      expect(h.controller.state.engaged, isTrue);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text("Don't show again"), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(await h.result, MobilePromoResult.engaged);
    });

    testWidgets("Don't show again ends it for good", (tester) async {
      final h = _Harness();
      await h.open(tester);
      await tester.tap(find.text("Don't show again"));
      await tester.pumpAndSettle();
      expect(await h.result, MobilePromoResult.dismissed);
      expect(h.controller.state.done, isTrue);
    });

    testWidgets('the last reminder offers Close only', (tester) async {
      final h = _Harness();
      await h.open(tester, closes: MobileAppPromoController.maxAutoOpens - 1);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Remind me later'), findsNothing);
      expect(find.text("Don't show again"), findsNothing);
    });

    testWidgets('a requested open never offers to snooze', (tester) async {
      final h = _Harness();
      await h.open(tester, isManual: true);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Remind me later'), findsNothing);
    });

    testWidgets('a tap in the first half-second does nothing', (tester) async {
      final h = _Harness();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      h.controller = MobileAppPromoController(prefs: DevicePrefsStore(null));
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => h.result = showDialog<MobilePromoResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => DesktopAppPromoDialog(
                  targets: _apple,
                  account: const MobilePromoAccount(),
                  controller: h.controller,
                  urlOf: _allListed,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Remind me later'));
      await tester.pump();
      expect(find.text('Invoice Ninja on your computer'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('the server', () {
    testWidgets('a self-hosted address is offered to copy, with the network '
        'note for a private one', (tester) async {
      final h = _Harness();
      await h.open(
        tester,
        account: const MobilePromoAccount(
          serverUrl: 'http://192.168.1.20',
          privateNetwork: true,
        ),
      );
      expect(find.text('Then sign in to this server:'), findsOneWidget);
      expect(
        find.widgetWithText(CopyValueRow, 'http://192.168.1.20'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your computer needs to be on the same network as the server.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hosted says nothing about a server', (tester) async {
      final h = _Harness();
      await h.open(tester);
      expect(find.text('Then sign in to this server:'), findsNothing);
    });
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('a small phone at 200% text', const Size(320, 568), 2.0),
      ('a phone', const Size(390, 844), 1.0),
      ('a tablet', const Size(1024, 1366), 1.0),
      ('a tablet in landscape', const Size(1366, 1024), 1.0),
    ]) {
      testWidgets('fits $name, with every way out on screen', (tester) async {
        final h = _Harness();
        await h.open(
          tester,
          targets: _android,
          size: size,
          textScale: scale,
          account: const MobilePromoAccount(
            serverUrl: 'https://in.example.com',
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.byType(DesktopAppPromoDialog), findsOneWidget);
      });
    }

    testWidgets('an iPhone SE shows the whole pitch above the footer, with '
        'nothing to scroll', (tester) async {
      final h = _Harness();
      await h.open(tester, size: const Size(375, 647));
      final footerTop = tester.getTopLeft(find.byType(Divider).last).dy;
      expect(
        tester.getBottomLeft(find.text('Keyboard shortcuts')).dy,
        lessThan(footerTop),
      );
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(DesktopAppPromoDialog),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, 0);
      expect(
        find.byIcon(Icons.laptop_outlined),
        findsNothing,
        reason: 'the glyph gives way on a short phone',
      );
    });

    testWidgets('a 4-inch phone keeps the features to their titles', (
      tester,
    ) async {
      final h = _Harness();
      await h.open(tester, size: const Size(320, 548));
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(
        find.text('Search, create and move between screens from the keyboard.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large text size stacks the footer, the way out on top, '
        'rather than cutting both labels short', (tester) async {
      final h = _Harness();
      await h.open(tester, size: const Size(320, 548), textScale: 2);
      expect(tester.takeException(), isNull);
      final remind = find.text('Remind me later');
      final dontShow = find.text("Don't show again");
      expect(
        tester.getTopLeft(remind).dy,
        lessThan(tester.getTopLeft(dontShow).dy),
      );
      for (final label in [remind, dontShow]) {
        expect(
          tester.widget<Text>(label).overflow,
          isNot(TextOverflow.ellipsis),
        );
      }
    });

    testWidgets('a platform name never breaks across lines', (tester) async {
      final h = _Harness();
      await h.open(
        tester,
        targets: _android,
        size: const Size(320, 548),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      for (final name in ['Windows', 'Mac', 'Linux']) {
        expect(tester.widget<Text>(find.text(name)).maxLines, 1, reason: name);
      }
    });

    testWidgets('on a foldable held half-open it lays out for its half, not '
        'the window (the tablet layout overflowed a ~420 half)', (
      tester,
    ) async {
      tester.view.displayFeatures = const [
        DisplayFeature(
          bounds: Rect.fromLTWH(420, 0, 0, 701),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ];
      final h = _Harness();
      await h.open(tester, targets: _android, size: const Size(841, 701));
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(Dialog));
      expect(card.width, lessThanOrEqualTo(420));
      // The phone layout: the link comes before the pitch.
      expect(
        tester.getTopLeft(find.text('Share link')).dy,
        lessThan(tester.getTopLeft(find.text('Room to work')).dy),
      );
    });
  });

  test('a phone build runs the desktop promo and never the phone one', () {
    // `flutter test` runs as Android.
    expect(currentDesktopPromoTargets(), isNotEmpty);
    expect(currentMobilePromoTargets(), isEmpty);
  });
}
