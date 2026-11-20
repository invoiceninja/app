import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/custom_field_types.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/ui/core/edit/custom_field_input.dart';
import 'package:admin/utils/formatting.dart';

import '../../../_localization_helper.dart';

void main() {
  group('customFieldDate', () {
    test('reads a bare date as that local calendar day', () {
      final d = customFieldDate('2026-05-14')!;
      expect([d.year, d.month, d.day, d.isUtc], [2026, 5, 14, false]);
    });

    test('a stored time and zone do not move the day', () {
      // Parsed whole, this is a UTC instant `InDateField` shows through
      // `toLocal()` — May 13 west of UTC, while the card and detail view
      // (`Formatter.date`) show the 14th.
      final d = customFieldDate('2026-05-14T00:00:00Z')!;
      expect([d.year, d.month, d.day, d.isUtc], [2026, 5, 14, false]);
    });

    test('no date → null', () {
      expect(customFieldDate(''), isNull);
      expect(customFieldDate('soon'), isNull);
      expect(customFieldDate('not a date at all'), isNull);
    });
  });

  // invoiceninja/app#200: the reporter's field — a date-typed custom field on
  // an invoice, company format `dd.MM.yyyy` — stored `0026-11-14`.
  testWidgets('a date field stores a typed two-digit year as this century', (
    tester,
  ) async {
    final stored = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: kTestSupportedLocales,
        home: Scaffold(
          body: CustomFieldInput(
            field: const ParsedCustomField(
              label: 'Leistungsdatum',
              type: kFieldTypeDate,
              options: [],
            ),
            value: '',
            onChanged: stored.add,
            formatter: Formatter(
              settings: const CompanyFormatSettings(
                currencyId: '3',
                countryId: '276',
                dateFormatId: '11',
                useCommaAsDecimalPlace: true,
                showCurrencyCode: false,
                enableMilitaryTime: true,
                locale: '',
              ),
              currencies: const {},
              countries: const {},
              dateFormats: const {
                '11': DatetimeFormat(id: '11', format: 'dd.MM.yyyy'),
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '14.11.26');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(stored, ['2026-11-14']);
    expect(find.text('14.11.2026'), findsOneWidget);
  });
}
