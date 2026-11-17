import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/company_settings.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/template_options.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/widgets/reminders_summary.dart';

import '../../../../../../_localization_helper.dart';

void main() {
  group('reminderSummaryFor', () {
    test('a scheduled reminder reads its own toggle, days and schedule', () {
      const s = CompanySettings(
        enableReminder2: true,
        numDaysReminder2: 7,
        scheduleReminder2: 'after_due_date',
        enableReminder1: false,
        numDaysReminder1: 3,
      );
      final r2 = reminderSummaryFor('reminder2', s);
      expect(r2.on, isTrue);
      expect(r2.days, 7);
      expect(r2.scheduleKey, 'after_due_date');
      expect(reminderSummaryFor('reminder1', s).on, isFalse);
    });

    test('the quote reminder reads the quote_ keys', () {
      const s = CompanySettings(
        enableQuoteReminder1: true,
        quoteNumDaysReminder1: 2,
        quoteScheduleReminder1: 'before_valid_until_date',
      );
      final r = reminderSummaryFor('quote_reminder1', s);
      expect(r.on, isTrue);
      expect(r.days, 2);
      expect(r.scheduleKey, 'before_valid_until_date');
    });

    test('the endless reminder names its frequency, never days', () {
      const s = CompanySettings(
        enableReminderEndless: true,
        endlessReminderFrequencyId: '2',
      );
      final r = reminderSummaryFor('reminder_endless', s);
      expect(r.on, isTrue);
      expect(r.frequencyKey, 'freq_weekly');
      expect(r.days, isNull);
    });

    test('unset is off, and an empty schedule is not said', () {
      const s = CompanySettings(scheduleReminder3: '');
      final r = reminderSummaryFor('reminder3', s);
      expect(r.on, isFalse);
      expect(r.scheduleKey, isNull);
    });
  });

  testWidgets('one row per reminder; tapping a row opens it', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildInTheme(InTheme.light),
        localizationsDelegates: kTestLocalizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemindersSummary(
              options: kTemplateOptions,
              settings: const CompanySettings(
                enableReminder1: true,
                numDaysReminder1: 7,
                scheduleReminder1: 'after_due_date',
              ),
              selectedKey: 'invoice',
              onOpen: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Five reminders (quotes on): three, endless, quote.
    expect(find.byType(ListTile), findsNWidgets(5));
    expect(find.text('7 Days · After the due date'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Off'), findsNWidgets(4));

    await tester.tap(find.text('Endless Reminder'));
    expect(opened, ['reminder_endless']);
  });
}
