// Device Settings, the redesigned content area: every tab at the widths a
// settings pane really gets, at 2x text, right to left and dark; the touch
// floors; the font-size glyphs; the palette dots; the counters card.
//
// `docs/settings-screens.md` § The setting row and § The segmented picker.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/text_scale_controller.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/enabled_modules.dart';
import 'package:admin/data/services/device_contacts_service.dart';
import 'package:admin/domain/entity_type.dart';
import 'package:admin/domain/sidebar_badge_modes.dart';
import 'package:admin/domain/sidebar_menu.dart';
import 'package:admin/ui/core/widgets/in_segmented.dart';
import 'package:admin/ui/features/settings/state/settings_level_controller.dart';
import 'package:admin/ui/features/settings/views/basic/device_settings_screen.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';
import 'package:admin/ui/features/settings/widgets/sidebar_counters_section.dart';

import '../../../../../_localization_helper.dart';
import '../../../../../_support/fake_biometric_service.dart';
import '../../../shell/_shell_test_helpers.dart';

/// No address book: the Contacts card hides itself, as on desktop.
class _NoContacts implements DeviceContactsService {
  @override
  bool get canSync => false;

  @override
  Future<DeviceContactsPermission> checkPermission() async =>
      DeviceContactsPermission.denied;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _kTabs = <String>['', 'security', 'phone', 'forms', 'data'];

Future<ShellFixture> _fixture() async {
  final fixture = await buildFixture(
    companies: const [FakeCompany(id: 'co1', name: 'Acme')],
    closeStreamsSynchronously: true,
    biometricService: FakeBiometricService(),
    deviceContactsService: _NoContacts(),
  );
  addTearDown(fixture.dispose);
  return fixture;
}

/// Pumps Device Settings on [tab] in a pane [width] wide — the window *is*
/// the pane here, so the shell's 24 px padding is all that is taken off.
Future<void> _pump(
  WidgetTester tester,
  ShellFixture fixture, {
  required double width,
  String tab = '',
  double height = 2400,
  double textScale = 1,
  bool rtl = false,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: tab.isEmpty
        ? '/settings/device_settings'
        : '/settings/device_settings/$tab',
    routes: [
      GoRoute(
        path: '/settings/device_settings',
        builder: (_, _) => const DeviceSettingsScreen(),
        routes: [
          GoRoute(
            path: ':tab',
            builder: (_, state) =>
                DeviceSettingsScreen(initialTab: state.pathParameters['tab']),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<Services>.value(value: fixture.services),
        ChangeNotifierProvider<SettingsLevelController>(
          create: (_) => SettingsLevelController(),
        ),
      ],
      child: MaterialApp.router(
        theme: buildInTheme(dark ? InTheme.darkEspresso : InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
}

/// Not `pumpAndSettle`: the counter previews hold live Drift watches.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Drop the tree inside the test body so the watches close before the
/// binding's pending-timer check.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

Finder _visible(Finder f) => find.descendant(
  of: find.byWidgetPredicate((w) => w is TickerMode && w.enabled),
  matching: f,
);

void main() {
  group('every tab lays out', () {
    for (final width in const <double>[320, 390, 720, 1000, 1440]) {
      testWidgets('at $width px', (tester) async {
        final fixture = await _fixture();
        for (final tab in _kTabs) {
          await _pump(tester, fixture, width: width, tab: tab);
          expect(find.byType(DeviceSettingsScreen), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$tab at $width');
        }
        await _dispose(tester);
      }, variant: _desktop);
    }

    for (final (label, scale, rtl, dark) in const [
      ('2x text', 2.0, false, false),
      ('right to left', 1.0, true, false),
      ('dark', 1.0, false, true),
    ]) {
      testWidgets('$label at 390 and 1440 px', (tester) async {
        final fixture = await _fixture();
        for (final width in const <double>[390, 1440]) {
          for (final tab in _kTabs) {
            await _pump(
              tester,
              fixture,
              width: width,
              tab: tab,
              textScale: scale,
              rtl: rtl,
              dark: dark,
            );
            expect(tester.takeException(), isNull, reason: '$tab at $width');
          }
        }
        await _dispose(tester);
      }, variant: _desktop);
    }
  });

  testWidgets('the page subtitle says where these settings live', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pump(tester, fixture, width: 1440);
    expect(
      find.text(
        kIsWeb
            ? 'Stored in this browser only, never synced to other browsers or '
                  'devices.'
            : 'Stored on this device only, never synced to your other '
                  'devices.',
      ),
      findsOneWidget,
    );
    await _dispose(tester);
  }, variant: _desktop);

  group('sections', () {
    testWidgets('side by side past 960 px of content, like Localization', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pump(tester, fixture, width: 1440);
      final description = find.text(
        'How the app looks and how much fits on screen.',
      );
      final theme = find.text('Theme');
      // The description in the title column, beside the card's first row.
      expect(
        tester.getTopRight(description).dx,
        lessThan(tester.getTopLeft(theme).dx),
      );
      expect(find.text('Lists & dashboard'), findsOneWidget);
      expect(find.text('Main menu'), findsOneWidget);
      await _dispose(tester);
    }, variant: _desktop);

    testWidgets('stacked below it: the description above the first row', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pump(tester, fixture, width: 1000);
      final description = find.text(
        'How the app looks and how much fits on screen.',
      );
      expect(
        tester.getBottomLeft(description).dy,
        lessThan(tester.getTopLeft(find.text('Theme')).dy),
      );
      await _dispose(tester);
    }, variant: _desktop);

    testWidgets('a narrow row stacks its picker under its text, filling it', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pump(tester, fixture, width: 390);
      final title = find.text('Theme');
      final picker = find.byType(InSegmented<ThemeMode>);
      expect(
        tester.getTopLeft(picker).dy,
        greaterThan(tester.getBottomLeft(title).dy),
      );
      // Starts at the text's edge and runs to the row's end.
      expect(
        tester.getTopLeft(picker).dx,
        moreOrLessEquals(tester.getTopLeft(title).dx, epsilon: 0.5),
      );
      final row = find.ancestor(of: title, matching: find.byType(SettingRow));
      expect(
        tester.getTopRight(picker).dx,
        moreOrLessEquals(tester.getTopRight(row).dx - 12, epsilon: 0.5),
      );
      await _dispose(tester);
    }, variant: _desktop);

    testWidgets('a wide row keeps its picker beside its text, segments equal', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pump(tester, fixture, width: 1440);
      final title = find.text('Theme');
      final picker = find.byType(InSegmented<ThemeMode>);
      expect(
        tester.getCenter(picker).dy,
        moreOrLessEquals(
          tester
              .getCenter(
                find.ancestor(of: title, matching: find.byType(SettingRow)),
              )
              .dy,
          epsilon: 1,
        ),
      );
      final faces = [
        for (final label in const ['Auto', 'Light', 'Dark'])
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.descendant(
                        of: picker,
                        matching: find.text(label),
                      ),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .width,
      ];
      expect(faces.toSet(), hasLength(1), reason: 'equal segments: $faces');
      await _dispose(tester);
    }, variant: _desktop);
  });

  group('touch', () {
    testWidgets('every control and row is at least 44 px tall', (tester) async {
      // flutter_test's default platform is android: touch-primary.
      final fixture = await _fixture();
      for (final tab in const ['', 'security', 'forms']) {
        await _pump(tester, fixture, width: 390, tab: tab);
        for (final e in _visible(
          find.byWidgetPredicate((w) => w is InSegmented),
        ).evaluate()) {
          expect(
            (e.renderObject! as RenderBox).size.height,
            greaterThanOrEqualTo(44),
          );
        }
        for (final e in _visible(find.byType(SettingRow)).evaluate()) {
          final row = e.widget as SettingRow;
          final h = (e.renderObject! as RenderBox).size.height;
          expect(h, greaterThanOrEqualTo(44), reason: row.title);
        }
        for (final e in _visible(find.byType(Switch)).evaluate()) {
          final row = e.findAncestorWidgetOfExactType<SettingRow>();
          final box = find
              .ancestor(
                of: find.byWidget(e.widget),
                matching: find.byType(SettingRow),
              )
              .evaluate()
              .first
              .renderObject;
          expect(
            (box! as RenderBox).size.height,
            greaterThanOrEqualTo(48),
            reason: '${row?.title}',
          );
        }
      }
      // The counter rows, and the Customize button.
      await _pump(tester, fixture, width: 390);
      for (final e
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'menu_counter_',
                    ),
              )
              .evaluate()) {
        expect(
          (e.renderObject! as RenderBox).size.height,
          greaterThanOrEqualTo(44),
        );
      }
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Customize')).height,
        greaterThanOrEqualTo(44),
      );
      await _dispose(tester);
    });
  });

  group('font size', () {
    testWidgets('four "A" glyphs, each named, each step reachable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final fixture = await _fixture();
      await _pump(tester, fixture, width: 1440);
      final picker = find.byType(InSegmented<double>);
      expect(
        find.descendant(of: picker, matching: find.text('A')),
        findsNWidgets(4),
      );
      for (final (label, value) in const [
        ('Small', kTextScaleSmall),
        ('Normal', kTextScaleNormal),
        ('Large', kTextScaleLarge),
        ('Extra Large', kTextScaleExtraLarge),
      ]) {
        final segment = find.descendant(
          of: picker,
          matching: find.bySemanticsLabel(label),
        );
        expect(segment, findsOneWidget, reason: label);
        await tester.tap(segment);
        await _frames(tester);
        expect(fixture.services.textScale.value, value, reason: label);
        // The step in effect is the row's subtitle.
        final row = find.ancestor(
          of: find.text('Font Size'),
          matching: find.byType(SettingRow),
        );
        expect(
          find.descendant(of: row, matching: find.text(label)),
          findsOneWidget,
        );
      }
      // Back to Normal, so the 1.4 scale doesn't outlive the test.
      await fixture.services.textScale.set(kTextScaleNormal);
      await _dispose(tester);
      handle.dispose();
    }, variant: _desktop);
  });

  group('palette', () {
    List<Color?> swatches<T>(WidgetTester tester) => [
      for (final s
          in tester
              .widget<InSegmented<T>>(find.byType(InSegmented<T>))
              .segments)
        s.swatch,
    ];

    testWidgets('light shows the light presets, by their own backgrounds', (
      tester,
    ) async {
      final fixture = await _fixture();
      await fixture.services.theme.setThemeMode(ThemeMode.light);
      await _pump(tester, fixture, width: 1440);
      expect(swatches<LightVariant>(tester), [
        for (final v in LightVariant.values) v.tokens.bg,
      ]);
      expect(find.byType(InSegmented<DarkVariant>), findsNothing);
      expect(find.text('Background tint'), findsOneWidget);
      await _dispose(tester);
    }, variant: _desktop);

    testWidgets('dark shows the dark presets, by their own backgrounds', (
      tester,
    ) async {
      final fixture = await _fixture();
      await fixture.services.theme.setThemeMode(ThemeMode.dark);
      await _pump(tester, fixture, width: 1440, dark: true);
      expect(swatches<DarkVariant>(tester), [
        for (final v in DarkVariant.values) v.tokens.bg,
      ]);
      expect(find.byType(InSegmented<LightVariant>), findsNothing);
      // The same words in either brightness — never "for light mode".
      expect(find.text('Background tint'), findsOneWidget);
      await fixture.services.theme.setThemeMode(ThemeMode.system);
      await _dispose(tester);
    }, variant: _desktop);
  });

  group('menu counters', () {
    int expectedOn(ShellFixture fixture) {
      final services = fixture.services;
      final modules =
          services.auth.session.value?.currentCompany?.enabledModules ?? 0;
      var on = 0;
      for (final h in services.entityRegistry.sidebarTop) {
        if (h.disabled || h.badgeStream == null) continue;
        if (!isEntityModuleEnabledForCompany(h.type, modules)) continue;
        final modes = availableBadgeModes(h.badgeModes, trackInventory: false);
        if (services.sidebarBadgeModes.modeFor(h.type, available: modes) !=
            kBadgeModeNone) {
          on++;
        }
      }
      return on;
    }

    testWidgets('"N on" counts the rows that are not None', (tester) async {
      final fixture = await _fixture();
      await _pump(tester, fixture, width: 1440);
      final before = expectedOn(fixture);
      expect(before, greaterThan(0));
      expect(find.text('$before on'), findsOneWidget);

      await fixture.services.sidebarBadgeModes.set(
        EntityType.client,
        kBadgeModeTotal,
      );
      await _frames(tester);
      expect(find.text('${before + 1} on'), findsOneWidget);

      await fixture.services.sidebarBadgeModes.set(
        EntityType.invoice,
        kBadgeModeNone,
      );
      await _frames(tester);
      expect(find.text('$before on'), findsOneWidget);
      expect(expectedOn(fixture), before);
      await _dispose(tester);
    }, variant: _desktop);

    test('two columns only when each measures 360 px, never on a phone', () {
      expect(menuCountersTwoColumns(743, phone: false), isFalse);
      expect(menuCountersTwoColumns(744, phone: false), isTrue);
      expect(menuCountersTwoColumns(1200, phone: true), isFalse);
    });

    Future<void> pumpCard(WidgetTester tester, ShellFixture f, double w) async {
      tester.view.physicalSize = Size(w, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrapWithShell(
          f.services,
          const SingleChildScrollView(child: SidebarCountersSection()),
        ),
      );
      await _frames(tester);
    }

    Offset rowAt(WidgetTester tester, EntityType type) =>
        tester.getTopLeft(find.byKey(ValueKey('menu_counter_${type.name}')));

    testWidgets('the columns follow the measured width', (tester) async {
      final fixture = await _fixture();
      // A card standing alone (no shell), so its width is the window's.
      await pumpCard(tester, fixture, 1200);
      final xs = <double>{
        for (final e
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'menu_counter_',
                      ),
                )
                .evaluate())
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
      };
      expect(xs, hasLength(2), reason: 'two columns at 1200 px');

      await pumpCard(tester, fixture, 700);
      final narrow = <double>{
        for (final e
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'menu_counter_',
                      ),
                )
                .evaluate())
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
      };
      expect(narrow, hasLength(1), reason: 'one column at 700 px');
      await _dispose(tester);
    }, variant: _desktop);

    testWidgets('rows follow the menu order, top to bottom then across', (
      tester,
    ) async {
      final fixture = await _fixture();
      // The menu's last counted row first, its first row last: the user's
      // own arrangement.
      final counted = [
        for (final h in fixture.services.entityRegistry.sidebarTop)
          if (!h.disabled && h.badgeStream != null) h.type,
      ];
      final head = counted.last;
      final tail = counted.first;
      final ids = [
        for (final h in fixture.services.entityRegistry.sidebarTop) h.type.name,
      ];
      final reordered = [
        head.name,
        ...ids.where((id) => id != head.name && id != tail.name),
        tail.name,
      ];
      await fixture.services.sidebarMenu.setEntries([
        for (final id in reordered) SidebarMenuEntryPref(id: id),
      ]);

      await pumpCard(tester, fixture, 700);
      final first = rowAt(tester, head);
      final last = rowAt(tester, tail);
      expect(first.dy, lessThan(rowAt(tester, EntityType.invoice).dy));
      expect(last.dy, greaterThan(rowAt(tester, EntityType.invoice).dy));

      // Two columns: the first half down the start column, then the rest.
      await pumpCard(tester, fixture, 1200);
      final a = rowAt(tester, head);
      final z = rowAt(tester, tail);
      expect(z.dx, greaterThan(a.dx), reason: 'last row in the end column');
      expect(a.dy, lessThanOrEqualTo(z.dy));
      await _dispose(tester);
    }, variant: _desktop);
  });
}
