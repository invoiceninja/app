import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/value/company_format_settings.dart';
import 'package:admin/data/models/value/datetime_format.dart';
import 'package:admin/ui/core/widgets/in_date_field.dart';
import 'package:admin/utils/formatting.dart';

import '../../../_localization_helper.dart';

const _settings = CompanyFormatSettings(
  currencyId: '1',
  countryId: '840',
  dateFormatId: 'X',
  useCommaAsDecimalPlace: false,
  showCurrencyCode: false,
  enableMilitaryTime: false,
  locale: '',
);

final _formatter = Formatter(
  settings: _settings,
  currencies: const {},
  countries: const {},
  dateFormats: const {'X': DatetimeFormat(id: 'X', format: 'd/MMM/yyyy')},
);

/// Every `format_dart` the server seeds (`DateFormatsSeeder.php`), so the
/// placeholder is exercised against the real catalog rather than one sample.
/// Id 1 — the server's *default*, and the one invoiceninja/flutter#127 was
/// filed against — is `dd/MMM/yyyy`.
const _serverDateFormats = <String, String>{
  '1': 'dd/MMM/yyyy',
  '2': 'dd-MMM-yyyy',
  '3': 'dd/MMMM/yyyy',
  '4': 'dd-MMMM-yyyy',
  '5': 'MMM d, yyyy',
  '6': 'MMMM d, yyyy',
  '7': 'EEE MMM d, yyyy',
  '8': 'yyyy-MM-dd',
  '9': 'dd-MM-yyyy',
  '10': 'MM/dd/yyyy',
  '11': 'dd.MM.yyyy',
  '12': 'd. MMM. yyyy',
  '13': 'd. MMMM yyyy',
  '14': 'dd/MM/yyyy',
};

Formatter _formatterFor(String id, String pattern) => Formatter(
  settings: CompanyFormatSettings(
    currencyId: '1',
    countryId: '840',
    dateFormatId: id,
    useCommaAsDecimalPlace: false,
    showCurrencyCode: false,
    enableMilitaryTime: false,
    // Pinned: id 12 (`d. MMM. yyyy`) renders `31. janv.. 2000` in French,
    // which `Formatter.date`'s `'..'` fixup collapses to `31. janv. 2000` —
    // correct to read, but no longer strictly re-parsable by its own pattern.
    locale: '',
  ),
  currencies: const {},
  countries: const {},
  dateFormats: {id: DatetimeFormat(id: id, format: pattern)},
);

Future<void> _pump(
  WidgetTester tester, {
  Formatter? formatter,
  required DateTime? value,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: InDateField(
            value: value,
            formatter: formatter,
            onChanged: (_) {},
            labelText: 'Date',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _value = DateTime(2026, 5, 14);

/// Read the placeholder off the widget rather than with `find.text`:
/// `InputDecoration.maintainHintSize` defaults to true, so the hint `Text` is
/// mounted at opacity 0 even when the field holds a value — a finder would
/// pass whether or not the hint is the string under test.
String? _hintOf(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).decoration!.hintText;

void main() {
  testWidgets('renders the company-formatted date when a Formatter is passed', (
    tester,
  ) async {
    await _pump(tester, formatter: _formatter, value: _value);
    expect(find.text('14/May/2026'), findsOneWidget);
    expect(find.text('2026-05-14'), findsNothing);
  });

  testWidgets('falls back to ISO when no Formatter is passed', (tester) async {
    await _pump(tester, value: _value);
    expect(find.text('2026-05-14'), findsOneWidget);
  });

  // invoiceninja/app#200: a German company (`dd.MM.yyyy`) typed `14.11.26`
  // and the field committed 14.11.0026.
  group('typed input', () {
    Future<List<DateTime?>> typeAndBlur(
      WidgetTester tester,
      String pattern,
      String typed,
    ) async {
      final committed = <DateTime?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: InDateField(
                value: null,
                formatter: _formatterFor('X', pattern),
                onChanged: committed.add,
                labelText: 'Date',
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), typed);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      return committed;
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('a two-digit year commits this century', (tester) async {
      final committed = await typeAndBlur(tester, 'dd.MM.yyyy', '14.11.26');
      expect(committed, [DateTime(2026, 11, 14)]);
      expect(fieldText(tester), '14.11.2026');
    });

    testWidgets('a short dash date keeps its day and month', (tester) async {
      final committed = await typeAndBlur(tester, 'dd-MM-yyyy', '14-11-26');
      expect(committed, [DateTime(2026, 11, 14)]);
      expect(fieldText(tester), '14-11-2026');
    });

    testWidgets('a three-digit year reverts silently', (tester) async {
      final committed = await typeAndBlur(tester, 'dd.MM.yyyy', '14.11.202');
      expect(committed, isEmpty);
      expect(fieldText(tester), '');
    });
  });

  group('placeholder', () {
    testWidgets('is a worked example date, never the intl pattern', (
      tester,
    ) async {
      await _pump(tester, formatter: _formatter, value: null);
      // Worded as an example: a bare date in hint grey read as a value
      // already set (a blank due date looked like one in the year 2000).
      expect(_hintOf(tester), 'e.g. 31/Jan/2000');
      // The bug: `MMM` is an abbreviated month NAME, so showing the pattern
      // reads as a typo ("one too many M"). invoiceninja/flutter#127.
      expect(_hintOf(tester), isNot('d/MMM/yyyy'));
    });

    testWidgets('falls back to the ISO sample when no Formatter is passed', (
      tester,
    ) async {
      await _pump(tester, value: null);
      expect(_hintOf(tester), 'e.g. $kDateFormatSampleIso');
      expect(_hintOf(tester), isNot('YYYY-MM-DD'));
    });

    testWidgets('is the ISO sample when the format id resolves to nothing', (
      tester,
    ) async {
      // Statics not loaded yet: `dateFormats` is empty. Before the fix this
      // branch yielded a null hint — no placeholder at all.
      final cold = Formatter(
        settings: _settings,
        currencies: const {},
        countries: const {},
        dateFormats: const {},
      );
      await _pump(tester, formatter: cold, value: null);
      expect(_hintOf(tester), 'e.g. $kDateFormatSampleIso');
    });

    testWidgets('an explicit hintText still wins', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: InDateField(
              value: null,
              formatter: _formatter,
              hintText: 'Anytime',
              onChanged: (_) {},
              labelText: 'Date',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_hintOf(tester), 'Anytime');
    });

    // The invariant, not the string: whatever the placeholder shows must be a
    // date this very field would accept. That fails for a raw pattern AND for
    // a "humanized" one (`dd/mm/yyyy`), which an equality assertion against a
    // hardcoded example would not catch.
    for (final entry in _serverDateFormats.entries) {
      testWidgets('round-trips for server date format ${entry.key} '
          '(${entry.value})', (tester) async {
        await _pump(
          tester,
          formatter: _formatterFor(entry.key, entry.value),
          value: null,
        );
        final hint = _hintOf(tester);
        expect(hint, startsWith('e.g. '));
        final example = hint!.substring('e.g. '.length);
        expect(example, isNot(entry.value), reason: 'rendered the raw pattern');
        expect(
          parseDateInput(example, activePattern: entry.value),
          DateTime.parse(kDateFormatSampleIso),
        );
      });
    }
  });

  // A trailing action (the invoice due date's payment terms) goes where the
  // field has room for it: inside beside the calendar when the whole hint
  // fits with both icons; else on the label's line (Comfortable) or in the
  // calendar's place (Compact) — decided by measured width.
  group('trailing action', () {
    const actionKey = ValueKey('action');
    final slots = <InDateFieldActionSlot>[];

    Future<void> pumpAt(
      WidgetTester tester, {
      required double width,
      TextDirection direction = TextDirection.ltr,
      InTheme tokens = InTheme.light,
      double textScale = 1,
    }) async {
      slots.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(tokens),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Directionality(
            textDirection: direction,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(
                  body: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: SizedBox(
                      width: width,
                      child: InDateField(
                        value: null,
                        formatter: _formatter,
                        onChanged: (_) {},
                        labelText: 'Due Date',
                        clearable: true,
                        trailingAction: (context, slot) {
                          slots.add(slot);
                          return IconButton(
                            key: actionKey,
                            iconSize: 16,
                            icon: const Icon(Icons.event_repeat_outlined),
                            tooltip: 'Payment Terms',
                            onPressed: () {},
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder inBox(Finder f) =>
        find.descendant(of: find.byType(InputDecorator), matching: f);

    testWidgets('wide: inside the field, before the calendar', (tester) async {
      await pumpAt(tester, width: 360);
      expect(slots.last.placement, InDateFieldActionPlacement.inField);
      expect(inBox(find.byKey(actionKey)), findsOneWidget);
      expect(inBox(find.byIcon(Icons.date_range)), findsOneWidget);
    });

    for (final (name, direction, tokens, scale) in [
      ('', TextDirection.ltr, InTheme.light, 1.0),
      (', RTL', TextDirection.rtl, InTheme.light, 1.0),
      (', dark', TextDirection.ltr, InTheme.dark, 1.0),
      (', 2x text', TextDirection.ltr, InTheme.light, 2.0),
      (', RTL dark 2x text', TextDirection.rtl, InTheme.dark, 2.0),
    ]) {
      testWidgets('narrow$name: on the label line, one icon in the field', (
        tester,
      ) async {
        await pumpAt(
          tester,
          width: 165,
          direction: direction,
          tokens: tokens,
          textScale: scale,
        );
        expect(tester.takeException(), isNull, reason: 'no overflow');
        expect(slots.last.placement, InDateFieldActionPlacement.labelLine);
        expect(inBox(find.byType(IconButton)), findsOneWidget);
        expect(inBox(find.byIcon(Icons.date_range)), findsOneWidget);
        final box = tester.getRect(find.byType(InputDecorator));
        final action = tester.getRect(find.byKey(actionKey));
        final icon = tester.getRect(find.byIcon(Icons.event_repeat_outlined));
        final label = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.maxLines == 1 &&
                w.text.toPlainText() == 'Due Date',
          ),
        );
        // At the label line's end edge, its icon on the label's line, the
        // label kept clear of it.
        final rtl = direction == TextDirection.rtl;
        expect(rtl ? action.left : action.right, rtl ? box.left : box.right);
        expect(icon.bottom, lessThanOrEqualTo(box.top));
        expect(icon.center.dy, moreOrLessEquals(label.center.dy, epsilon: 4));
        expect(
          rtl ? label.left : label.right,
          rtl
              ? greaterThanOrEqualTo(action.right)
              : lessThanOrEqualTo(action.left),
        );
      });
    }

    // Compact (pinned through the real scope in
    // billing_doc_edit_mobile_details_test) and a label-less field share it:
    // no label line to move to.
    testWidgets('narrow with no label line: in the calendar\'s place, with '
        'the picker handed to it', (tester) async {
      slots.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildInTheme(InTheme.light),
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: kTestSupportedLocales,
          home: Scaffold(
            body: Align(
              alignment: AlignmentDirectional.topStart,
              child: SizedBox(
                width: 140,
                child: InDateField(
                  value: null,
                  formatter: _formatter,
                  onChanged: (_) {},
                  trailingAction: (context, slot) {
                    slots.add(slot);
                    return IconButton(
                      key: actionKey,
                      icon: const Icon(Icons.date_range),
                      onPressed: slot.openPicker,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(slots.last.placement, InDateFieldActionPlacement.replacesCalendar);
      expect(slots.last.openPicker, isNotNull);
      expect(inBox(find.byType(IconButton)), findsOneWidget);
      expect(inBox(find.byKey(actionKey)), findsOneWidget);
    });

    testWidgets('a field with no action is unchanged', (tester) async {
      await _pump(tester, formatter: _formatter, value: null);
      expect(
        find.descendant(
          of: find.byType(InDateField),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
      expect(inBox(find.byType(IconButton)), findsOneWidget);
    });
  });
}
