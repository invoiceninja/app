import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/data/models/value/language.dart';
import 'package:admin/utils/formatting.dart';

/// The server's languages table, as `database/seeders/LanguageSeeder.php`
/// seeds it (id → locale). The app reads it from the statics bundle; this
/// copy only pins the ids the bug was about and gives every locale a run
/// through `DateFormat`.
const _serverLocales = {
  '1': 'en', '2': 'it', '3': 'de', '4': 'fr', '5': 'pt_BR', '6': 'nl', //
  '7': 'es', '8': 'nb_NO', '9': 'da', '10': 'ja', '11': 'sv', '12': 'es_ES',
  '13': 'fr_CA', '14': 'lt', '15': 'pl', '16': 'cs', '17': 'hr', '18': 'sq',
  '19': 'el', '20': 'en_GB', '21': 'pt_PT', '22': 'sl', '23': 'fi',
  '24': 'ro', '25': 'tr_TR', '26': 'th', '27': 'mk_MK', '28': 'zh_TW',
  '29': 'ru_RU', '30': 'ar', '31': 'fa', '32': 'lv_LV', '33': 'sr',
  '34': 'sk', '35': 'et', '36': 'bg', '37': 'he', '38': 'km_KH', '39': 'hu',
  '40': 'fr_CH', '41': 'lo_LA', '42': 'vi', '43': 'ca', '44': 'af_ZA',
  '45': 'id_ID',
};

final _languages = {
  for (final e in _serverLocales.entries)
    e.key: Language(id: e.key, name: e.value, locale: e.value),
};

CompanyFormatSettings _settingsFor(String languageId) =>
    CompanyFormatSettings.fromCompanyJson({
      'settings': {'language_id': languageId},
    }, languages: _languages);

Formatter _formatterFor(String languageId) => Formatter(
  settings: _settingsFor(languageId),
  currencies: const {},
  countries: const {},
  dateFormats: const {'5': DatetimeFormat(id: '5', format: 'MMM d, yyyy')},
);

void main() {
  setUpAll(() async {
    // The app's own date-symbol load: GlobalMaterialLocalizations fills intl's
    // tables for every Material locale the first time it loads.
    await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  });

  test('English (United Kingdom) is en_GB, not Romanian', () {
    expect(_settingsFor('20').locale, 'en_GB');
    expect(_formatterFor('20').dateShort('2026-11-22'), '22 Nov');
  });

  test('Romanian is still Romanian', () {
    expect(_settingsFor('24').locale, 'ro');
    expect(_formatterFor('24').dateShort('2026-11-22'), '22 nov.');
  });

  test('an id the catalog lacks follows the device', () {
    expect(_settingsFor('999').locale, '');
    expect(
      CompanyFormatSettings.fromCompanyJson({
        'settings': {'language_id': '20'},
      }).locale,
      '',
    );
  });

  test('a language Material does not ship follows the device', () {
    final settings = CompanyFormatSettings.fromCompanyJson(
      {
        'settings': {'language_id': '99'},
      },
      languages: const {
        '99': Language(id: '99', name: 'Klingon', locale: 'tlh_QO'),
      },
    );
    expect(settings.locale, '');
    expect(formattableLocale('lo_LA'), 'lo_LA');
    expect(formattableLocale(''), '');
  });

  test('every server language formats a month word', () {
    for (final id in _serverLocales.keys) {
      final f = _formatterFor(id);
      expect(
        f.settings.locale,
        _serverLocales[id],
        reason: 'language $id is formattable and kept',
      );
      expect(
        () => f.dateShort('2026-11-22'),
        returnsNormally,
        reason: 'language $id (${_serverLocales[id]})',
      );
      expect(
        () => DateFormat.yMMMd(f.settings.locale).format(DateTime(2026)),
        returnsNormally,
        reason: 'language $id (${_serverLocales[id]})',
      );
    }
  });
}
