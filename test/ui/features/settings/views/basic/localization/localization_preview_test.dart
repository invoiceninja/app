import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/country.dart';
import 'package:admin/data/models/value/currency.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/ui/features/settings/views/basic/localization/localization_screen.dart';
import 'package:admin/utils/formatting.dart';

Currency _currency(String id, String code, String symbol) => Currency(
  id: id,
  name: code,
  code: code,
  symbol: symbol,
  precision: 2,
  thousandSeparator: ',',
  decimalSeparator: '.',
  swapCurrencySymbol: false,
  exchangeRate: Decimal.one,
);

Country _country(String id, String iso2) => Country(
  id: id,
  name: iso2,
  iso2: iso2,
  iso3: iso2,
  swapCurrencySymbol: false,
  thousandSeparator: '',
  decimalSeparator: '',
  swapPostalCode: false,
);

/// The saved company: USD, MMM d, yyyy, 12-hour — and the decimal comma on.
final _base = Formatter(
  settings: CompanyFormatSettings.fallback.withCompanyColumns(
    firstMonthOfYear: 4,
    firstDayOfWeek: 1,
    useCommaAsDecimalPlace: true,
  ),
  currencies: {
    '1': _currency('1', 'USD', r'$'),
    '2': _currency('2', 'GBP', '£'),
  },
  countries: {'840': _country('840', 'US')},
  dateFormats: const {
    '5': DatetimeFormat(id: '5', format: 'MMM d, yyyy'),
    '1': DatetimeFormat(id: '1', format: 'd/MMM/yyyy'),
  },
);

void main() {
  test('the preview follows the draft, not the saved company', () {
    const draft = CompanySettings(
      currencyId: '2',
      countryId: '840',
      dateFormatId: '1',
      militaryTime: true,
      showCurrencyCode: false,
    );
    final f = localizationPreviewFormatter(_base, draft);

    expect(f.money(kLocalizationPreviewAmount), '£1,234.56');
    expect(f.dateExample, '31/Jan/2000');
    expect(f.settings.enableMilitaryTime, isTrue);
  });

  test('currency code format shows the code', () {
    const draft = CompanySettings(
      currencyId: '1',
      countryId: '840',
      dateFormatId: '5',
      showCurrencyCode: true,
    );
    final f = localizationPreviewFormatter(_base, draft);
    expect(f.money(kLocalizationPreviewAmount), '1,234.56 USD');
  });

  test('the decimal comma and calendar columns stay the saved company\'s', () {
    // use_comma_as_decimal_place is how amounts are typed, not shown — the
    // preview must not flip separators on it.
    const draft = CompanySettings(currencyId: '1', dateFormatId: '5');
    final f = localizationPreviewFormatter(_base, draft);
    expect(f.settings.useCommaAsDecimalPlace, isTrue);
    expect(f.money(kLocalizationPreviewAmount), r'$1,234.56');
    expect(f.settings.firstMonthOfYear, 4);
    expect(f.settings.configuredFirstDayOfWeek, 1);
  });
}
