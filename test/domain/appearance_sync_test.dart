import 'package:flutter_test/flutter_test.dart';

import 'package:admin/domain/appearance_sync.dart';

/// `reconcileAppearance` — the decision behind the appearance following the
/// user across devices (invoiceninja/app#199,
/// `docs/user-settings-storage.md`).
void main() {
  const dark = AppearanceRecord(
    themeMode: 'dark',
    lightVariant: 'mist',
    darkVariant: 'midnight',
    custom: {
      'light': {'background': '#FFEEDD'},
      'dark': <String, Object?>{},
    },
  );
  const light = AppearanceRecord(
    themeMode: 'light',
    lightVariant: 'paper',
    darkVariant: 'carbon',
  );
  const nowMs = 5000;

  AppearanceDecision decide({
    required AppearanceRecord local,
    Map<String, AppearanceRecord?> companies = const {'a': null},
    String active = 'a',
    bool seeded = true,
  }) => reconcileAppearance(
    local: local,
    companies: companies,
    activeCompanyId: active,
    seeded: seeded,
    nowMs: nowMs,
  );

  group('adopting', () {
    test('a newer copy in the active company is adopted', () {
      final d = decide(
        local: light.withUpdatedAt(100),
        companies: {'a': dark.withUpdatedAt(200)},
      );
      expect(d.adopt?.themeMode, 'dark');
      expect(d.adopt?.updatedAt, 200);
      expect(d.push, isNull, reason: 'the active company already has it');
    });

    test('the newest copy in ANY company is adopted, and the active company '
        'is sent it', () {
      // The change was made under company b on the other computer; this one
      // signed in on company a.
      final d = decide(
        local: light.withUpdatedAt(100),
        companies: {
          'a': light.withUpdatedAt(100),
          'b': dark.withUpdatedAt(300),
          'c': light.withUpdatedAt(250),
        },
      );
      expect(d.adopt?.updatedAt, 300);
      expect(d.adopt?.sameLook(dark), isTrue);
      expect(d.push?.updatedAt, 300);
      expect(d.push?.sameLook(dark), isTrue);
    });

    test(
      'no stamp here: any copy on the server wins — the new-device case',
      () {
        final d = decide(
          local: light,
          companies: {'a': null, 'b': dark.withUpdatedAt(1)},
        );
        expect(d.adopt?.sameLook(dark), isTrue);
        expect(d.push?.updatedAt, 1, reason: 'a lacks it, so it is sent');
      },
    );

    test('a tie with a different look goes to the server', () {
      final d = decide(
        local: light.withUpdatedAt(200),
        companies: {'a': dark.withUpdatedAt(200)},
      );
      expect(d.adopt?.sameLook(dark), isTrue);
      expect(d.push, isNull);
    });

    test('an equal copy is a no-op', () {
      final d = decide(
        local: dark.withUpdatedAt(200),
        companies: {'a': dark.withUpdatedAt(200)},
      );
      expect(d.isNoop, isTrue);
    });
  });

  group('pushing', () {
    test('a newer local change is pushed to the active company', () {
      final d = decide(
        local: dark.withUpdatedAt(400),
        companies: {'a': light.withUpdatedAt(200)},
      );
      expect(d.adopt, isNull);
      expect(d.push?.sameLook(dark), isTrue);
      expect(d.push?.updatedAt, 400);
    });

    test('a stale copy written back by another client is put right', () {
      // React's whole-object profile save brought an older copy back.
      final d = decide(
        local: dark.withUpdatedAt(400),
        companies: {'a': light.withUpdatedAt(100)},
      );
      expect(d.push?.updatedAt, 400);
    });

    test('a company that lacks the key is sent it (the old app dropped it, '
        'or a switch made it active)', () {
      final d = decide(
        local: dark.withUpdatedAt(400),
        companies: {'a': null, 'b': dark.withUpdatedAt(400)},
      );
      expect(d.adopt, isNull);
      expect(d.push?.updatedAt, 400);
    });

    test('only the active company is ever pushed to', () {
      final d = decide(
        local: dark.withUpdatedAt(400),
        companies: {'a': dark.withUpdatedAt(400), 'b': null},
      );
      expect(d.isNoop, isTrue);
    });

    test('nothing is pushed before the active company is stored', () {
      final d = decide(
        local: dark.withUpdatedAt(400),
        companies: {'b': light.withUpdatedAt(100)},
      );
      expect(d.push, isNull);
      expect(d.markSeeded, isFalse);
    });
  });

  group('seeding once', () {
    test('an unstamped non-default look is uploaded once when nothing '
        'anywhere has a copy', () {
      final d = decide(local: dark, seeded: false);
      expect(d.push?.sameLook(dark), isTrue);
      expect(d.push?.updatedAt, nowMs);
      expect(d.adopt?.updatedAt, nowMs, reason: 'the device takes the stamp');
      expect(d.markSeeded, isTrue);
    });

    test('a default look is never uploaded, but the device is marked', () {
      final d = decide(local: AppearanceRecord.defaults, seeded: false);
      expect(d.push, isNull);
      expect(d.adopt, isNull);
      expect(d.markSeeded, isTrue);
    });

    test('a seeded device never uploads an unstamped look again — the next '
        'user of a shared device does not get the last one\'s', () {
      final d = decide(local: dark, seeded: true);
      expect(d.isNoop, isTrue);
    });

    test('a copy on the server beats seeding', () {
      final d = decide(
        local: dark,
        seeded: false,
        companies: {'a': light.withUpdatedAt(10)},
      );
      expect(d.adopt?.sameLook(light), isTrue);
      expect(d.push, isNull);
      expect(d.markSeeded, isTrue);
    });
  });

  group('the record', () {
    test('reads back from settings and writes one path per field', () {
      final patch = dark.withUpdatedAt(42).toSettingsPatch();
      expect(patch.keys, everyElement(startsWith('flutter_appearance.')));
      final settings = <String, dynamic>{
        'flutter_appearance': {
          for (final e in patch.entries) e.key.split('.').last: e.value,
          'from_a_newer_build': true,
        },
      };
      final back = AppearanceRecord.fromSettings(settings)!;
      expect(back.sameLook(dark), isTrue);
      expect(back.updatedAt, 42);
    });

    test('a copy without a stamp, or not a map, reads as missing', () {
      expect(AppearanceRecord.fromSettings(null), isNull);
      expect(
        AppearanceRecord.fromSettings({'flutter_appearance': 'x'}),
        isNull,
      );
      expect(
        AppearanceRecord.fromSettings({
          'flutter_appearance': {'theme_mode': 'dark'},
        }),
        isNull,
      );
    });

    test('an empty custom side equals a missing one', () {
      expect(
        light.sameLook(
          const AppearanceRecord(
            themeMode: 'light',
            lightVariant: 'paper',
            darkVariant: 'carbon',
            custom: {'light': <String, Object?>{}, 'dark': <String, Object?>{}},
          ),
        ),
        isTrue,
      );
      expect(AppearanceRecord.defaults.isDefaultLook, isTrue);
      expect(dark.isDefaultLook, isFalse);
    });

    test('a stamp sent as a string or a double still orders', () {
      final r = AppearanceRecord.fromSettings({
        'flutter_appearance': {'theme_mode': 'dark', 'updated_at': '77'},
      });
      expect(r?.updatedAt, 77);
      final d = AppearanceRecord.fromSettings({
        'flutter_appearance': {'theme_mode': 'dark', 'updated_at': 78.0},
      });
      expect(d?.updatedAt, 78);
    });
  });
}
