// The Overview's catalog of overridden settings (`group_setting_overrides.dart`):
// which keys count as overridden, and that every one of them is named the way
// a settings page names it — never a raw key.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/api/company_settings_api_model.dart';
import 'package:admin/ui/features/group_settings/group_setting_overrides.dart';

Map<String, String> _english() {
  final en = (jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map)
      .cast<String, Object?>();
  final pending =
      (jsonDecode(File('assets/i18n/_app_pending.json').readAsStringSync())
              as Map)
          .cast<String, Object?>();
  return {
    for (final e in {...pending, ...en}.entries)
      if (e.value is String && (e.value as String).trim().isNotEmpty)
        e.key: e.value as String,
  };
}

void main() {
  final english = _english();

  group('overriddenSettingKeys', () {
    test('a group with no settings overrides nothing', () {
      expect(overriddenSettingKeys(null), isEmpty);
      expect(overriddenSettingKeys(const {}), isEmpty);
    });

    test('lists exactly the keys an override checkbox ticks', () {
      final keys = overriddenSettingKeys(const {
        'currency_id': '3',
        // An explicit "off" is an override; a null is "inherit".
        'military_time': false,
        'language_id': null,
        // No page binds a key the typed model does not know.
        'not_a_setting': 'x',
      });
      expect(keys.toSet(), {'currency_id', 'military_time'});
    });

    test('the typed model sets nothing on its own — an empty blob stays '
        'empty, or every group would list defaults it never set', () {
      final json = const CompanySettingsApi().toJson()
        ..removeWhere((_, v) => v == null);
      expect(json, isEmpty);
    });
  });

  test('every apiKey a settings page binds has a label and a section', () {
    final apiKey = RegExp(r"apiKey: '([a-z0-9_]+)'");
    final missing = <String>{};
    for (final f
        in Directory('lib/ui/features')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      for (final m in apiKey.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!;
        if (settingOverrideLabelKeys(key) == null) missing.add(key);
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Add these to kSettingOverrideSpecs with the label their page '
          'draws, so a group that ticks them lists them by name: $missing',
    );
  });

  test('every setting the typed model knows is named by a real string', () {
    final unnamed = <String>[];
    // The model's wire keys, read off its source: `toJson` drops nulls, so
    // an empty instance lists none of them.
    final keys = RegExp(r"JsonKey\(name: '([a-z0-9_]+)'")
        .allMatches(
          File(
            'lib/data/models/api/company_settings_api_model.dart',
          ).readAsStringSync(),
        )
        .map((m) => m.group(1)!)
        .toSet();
    expect(
      keys.length,
      greaterThan(200),
      reason: 'the key scan stopped matching',
    );
    for (final key in keys) {
      final labelKeys = settingOverrideLabelKeys(key);
      if (labelKeys != null) {
        for (final k in labelKeys) {
          if (!english.containsKey(k)) unnamed.add('$key → $k');
        }
        continue;
      }
      final stem = key.endsWith('_id') ? key.substring(0, key.length - 3) : key;
      if (!english.containsKey(key) && !english.containsKey(stem)) {
        unnamed.add(key);
      }
    }
    expect(unnamed, isEmpty, reason: 'No translation names: $unnamed');
  });

  group('composed labels', () {
    test('email templates are named as the Templates picker names them', () {
      expect(settingOverrideLabelKeys('email_subject_reminder1'), [
        'first_reminder',
        'subject',
      ]);
      expect(settingOverrideLabelKeys('email_template_payment_partial'), [
        'payment_partial',
        'body',
      ]);
      expect(settingOverrideLabelKeys('email_quote_template_reminder1'), [
        'quote_reminder1',
        'body',
      ]);
      expect(
        settingOverrideSection('email_template_invoice'),
        'templates_and_reminders',
      );
    });

    test('reminder rules name their reminder and the field', () {
      expect(settingOverrideLabelKeys('num_days_reminder2'), [
        'second_reminder',
        'days',
      ]);
      expect(settingOverrideLabelKeys('late_fee_endless_percent'), [
        'endless_reminder',
        'late_fee_percent',
      ]);
      expect(settingOverrideLabelKeys('quote_schedule_reminder1'), [
        'quote_reminder1',
        'schedule',
      ]);
      expect(settingOverrideKind('num_days_reminder1'), OverrideValueKind.days);
    });

    test('number patterns name their entity', () {
      expect(settingOverrideLabelKeys('recurring_invoice_number_pattern'), [
        'recurring_invoice',
        'number_pattern',
      ]);
      expect(
        settingOverrideSection('client_number_counter'),
        'generated_numbers',
      );
    });

    test('a lookup-valued key is never shown as stored', () {
      expect(settingOverrideKind('currency_id'), OverrideValueKind.currency);
      expect(
        settingOverrideKind('invoice_design_id'),
        OverrideValueKind.design,
      );
      expect(settingOverrideKind('payment_terms'), OverrideValueKind.days);
      expect(settingOverrideKind('mailgun_secret'), OverrideValueKind.secret);
    });
  });
}
