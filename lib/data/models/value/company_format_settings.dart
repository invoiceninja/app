import 'package:material_ui/material_ui.dart' show kMaterialSupportedLanguages;

import 'package:admin/data/models/value/language.dart';

/// Subset of the company settings JSON that the number / date formatter
/// needs. Built once per company switch and held on `Services`.
///
/// Wire keys mirror the Invoice Ninja API. `use_comma_as_decimal_place` is
/// historically a top-level company property; admin-portal also reads
/// `settings.use_comma_as_decimal_place` so we accept either spelling.
class CompanyFormatSettings {
  const CompanyFormatSettings({
    required this.currencyId,
    required this.countryId,
    required this.dateFormatId,
    required this.useCommaAsDecimalPlace,
    required this.showCurrencyCode,
    required this.enableMilitaryTime,
    required this.locale,
    this.firstMonthOfYear = 1,
    int? firstDayOfWeek,
  }) : configuredFirstDayOfWeek = firstDayOfWeek;

  final String currencyId;
  final String countryId;
  final String dateFormatId;
  final bool useCommaAsDecimalPlace;
  final bool showCurrencyCode;
  final bool enableMilitaryTime;

  /// Resolved locale string for `intl`'s `DateFormat` (e.g. `en_US`). Defaults
  /// to `en` when we can't derive one from the company.
  final String locale;

  /// `first_month_of_year` (1=Jan..12=Dec) — a TOP-LEVEL company field, not
  /// inside the `settings` blob. Drives the fiscal-year start for the dashboard
  /// and report "this year" / "last year" ranges. Defaults to 1 (calendar
  /// year). Authoritatively sourced from the company row's own column in
  /// `Services._buildFormatter`; see `lib/utils/date_ranges.dart` for the math.
  final int firstMonthOfYear;

  /// `first_day_of_week` (0=Sun..6=Sat) exactly as the company configured it,
  /// or **null when it never has been** — the two must stay distinguishable.
  ///
  /// The server leaves this column blank until a user picks a value, so
  /// collapsing "unset" onto 0 makes "never configured" indistinguishable from
  /// "explicitly Sunday". A surface that wants to fall back to the device
  /// locale (the date-range calendar does, and Flutter's own `showDatePicker`
  /// always has) then can't: its `?? locale` is dead code and every unconfigured
  /// company gets a Sunday-first grid regardless of locale.
  final int? configuredFirstDayOfWeek;

  /// Effective start-of-week for date MATH — dashboard chart buckets and report
  /// week grouping — where a stable, locale-independent default is what keeps
  /// grouped data comparable. Unset falls back to 0 (Sunday), matching the
  /// server's own column default. UI that renders a calendar should prefer
  /// [configuredFirstDayOfWeek] and fall back to the locale instead.
  int get firstDayOfWeek => configuredFirstDayOfWeek ?? 0;

  /// Default fallback: USD, US, MM/DD/YYYY format id `5`. Matches
  /// `admin-portal/lib/constants.dart:kDefaultCurrencyId` /
  /// `kDefaultDateFormat`. Empty `locale` lets `DateFormat` use the system
  /// locale — which works without calling `initializeDateFormatting`.
  static const fallback = CompanyFormatSettings(
    currencyId: '1',
    countryId: '840',
    dateFormatId: '5',
    useCommaAsDecimalPlace: false,
    showCurrencyCode: false,
    enableMilitaryTime: false,
    locale: '',
    firstMonthOfYear: 1,
  );

  /// Parse from a company's stored settings JSON blob (the
  /// `settings: jsonEncode(uc.company.settings)` column in
  /// `auth_repository.dart`). Accepts either the settings map directly or a
  /// company envelope wrapping it under a `settings` key.
  ///
  /// [languages] is the statics catalog (`StaticsRepository.languages`): a
  /// `language_id` becomes that row's `locale`, as admin-portal's
  /// `localeSelector` does. Never a hand-kept id table: one was wrong from id
  /// 18 up, and English (United Kingdom), id 20, rendered every month word in
  /// Romanian. See [formattableLocale] for what becomes empty.
  factory CompanyFormatSettings.fromCompanyJson(
    Map<String, dynamic> json, {
    Map<String, Language> languages = const {},
  }) {
    final settings = json['settings'] is Map<String, dynamic>
        ? json['settings'] as Map<String, dynamic>
        : json;
    return CompanyFormatSettings(
      // Wire keys: currency_id, country_id, date_format_id, language_id,
      // show_currency_code, military_time.
      currencyId: _str(settings, 'currency_id', fallback.currencyId),
      countryId: _str(settings, 'country_id', fallback.countryId),
      dateFormatId: _str(settings, 'date_format_id', fallback.dateFormatId),
      showCurrencyCode: _bool(settings, 'show_currency_code'),
      enableMilitaryTime: _bool(settings, 'military_time'),
      locale: formattableLocale(
        languages[_str(settings, 'language_id', '')]?.locale ?? '',
      ),
      // first_month_of_year / first_day_of_week / use_comma_as_decimal_place are
      // TOP-LEVEL company fields (not inside `settings`), so read them off the
      // outer `json`. In the common path `Services._buildFormatter` overrides
      // these from the company row's dedicated columns via copyWith.
      firstMonthOfYear: _int(json, 'first_month_of_year', 1),
      // Null, not 0, when the key is absent/blank — see
      // [configuredFirstDayOfWeek]. (These three are overlaid from the
      // company row's own columns in `Services._buildFormatter` anyway; this
      // keeps the settings-blob path from manufacturing a fake "Sunday".)
      firstDayOfWeek: _intOrNull(json, 'first_day_of_week'),
      useCommaAsDecimalPlace: _bool(json, 'use_comma_as_decimal_place'),
    );
  }

  CompanyFormatSettings copyWith({
    String? currencyId,
    String? countryId,
    String? dateFormatId,
    bool? useCommaAsDecimalPlace,
    bool? showCurrencyCode,
    bool? enableMilitaryTime,
    String? locale,
    int? firstMonthOfYear,
  }) => CompanyFormatSettings(
    currencyId: currencyId ?? this.currencyId,
    countryId: countryId ?? this.countryId,
    dateFormatId: dateFormatId ?? this.dateFormatId,
    useCommaAsDecimalPlace:
        useCommaAsDecimalPlace ?? this.useCommaAsDecimalPlace,
    showCurrencyCode: showCurrencyCode ?? this.showCurrencyCode,
    enableMilitaryTime: enableMilitaryTime ?? this.enableMilitaryTime,
    locale: locale ?? this.locale,
    firstMonthOfYear: firstMonthOfYear ?? this.firstMonthOfYear,
    firstDayOfWeek: configuredFirstDayOfWeek,
  );

  /// Overlay the three values that live in the company row's own COLUMNS rather
  /// than in its settings JSON blob — the one thing `Services._buildFormatter`
  /// does after parsing.
  ///
  /// Separate from [copyWith] because these have "absent" semantics that
  /// `copyWith`'s `?? this.x` can't express: a blank `first_day_of_week` column
  /// IS the unset state and must overwrite whatever the blob said, not be read
  /// as "leave it alone". Doing that through `copyWith` would mean widening its
  /// parameter to `Object?` behind a sentinel, trading a compile error for a
  /// runtime cast on every caller of a shared API.
  CompanyFormatSettings withCompanyColumns({
    required int firstMonthOfYear,
    required int? firstDayOfWeek,
    required bool useCommaAsDecimalPlace,
  }) => CompanyFormatSettings(
    currencyId: currencyId,
    countryId: countryId,
    dateFormatId: dateFormatId,
    useCommaAsDecimalPlace: useCommaAsDecimalPlace,
    showCurrencyCode: showCurrencyCode,
    enableMilitaryTime: enableMilitaryTime,
    locale: locale,
    firstMonthOfYear: firstMonthOfYear,
    firstDayOfWeek: firstDayOfWeek,
  );
}

String _str(Map<String, dynamic> m, String key, String fallback) {
  final v = m[key];
  if (v == null) return fallback;
  final s = v.toString();
  return s.isEmpty ? fallback : s;
}

bool _bool(Map<String, dynamic> m, String key) => m[key] == true;

/// Parse a wire value that may arrive as an int or a numeric string (the API
/// sends `first_month_of_year` as a string). Empty / unparseable → [fallback].
int _int(Map<String, dynamic> m, String key, int fallback) {
  final v = m[key];
  if (v is int) return v;
  if (v == null) return fallback;
  return int.tryParse(v.toString()) ?? fallback;
}

/// Like [_int] but keeps "absent / blank / unparseable" as null instead of
/// folding it onto a fallback that a real configured value could also produce.
int? _intOrNull(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is int) return v;
  if (v == null) return null;
  return int.tryParse(v.toString());
}

/// [locale] when `DateFormat` can format in it, else `''` (the device locale).
///
/// Every `Formatter` date method passes the company locale to `DateFormat`
/// unguarded, and an unknown one throws in every cell that shows a date. The
/// date symbols are the ones `GlobalMaterialLocalizations` loads at boot, for
/// each of its languages, and intl falls back from `lo_LA` to `lo`; so a
/// locale whose language Material ships is safe, and a language a server adds
/// later that Material does not ship follows the device instead. Albanian and
/// Macedonian are not forced to English as admin-portal does (flutter#32090,
/// since fixed): Material ships both.
String formattableLocale(String locale) {
  if (locale.isEmpty) return '';
  final language = locale.split(RegExp('[_-]')).first.toLowerCase();
  return kMaterialSupportedLanguages.contains(language) ? locale : '';
}
