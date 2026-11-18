import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/theme.dart';
import 'package:admin/data/models/domain/design.dart';
import 'package:admin/domain/run_template.dart';
import 'package:admin/ui/features/invoices/widgets/detail/run_template_dialog.dart';

import '../../../../../_localization_helper.dart';

Design _design(String id, String name) => Design(
  id: id,
  name: name,
  isCustom: true,
  isActive: true,
  isTemplate: true,
  isFree: false,
  entities: const ['invoice'],
  template: const DesignTemplate(),
  updatedAt: DateTime.utc(2026, 1, 1, 12),
  createdAt: DateTime.utc(2026, 1, 1, 12),
  archivedAt: null,
  isDeleted: false,
);

/// Pumps a button that opens [RunTemplateDialog] and records what it pops.
Future<List<RunTemplateChoice?>> _open(
  WidgetTester tester,
  List<Design> designs, {
  int count = 1,
  RunTemplatePdfBlock? pdfBlock,
}) async {
  final results = <RunTemplateChoice?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildInTheme(InTheme.light),
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: kTestSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              results.add(
                await showDialog<RunTemplateChoice>(
                  context: context,
                  builder: (_) => RunTemplateDialog(
                    designs: designs,
                    count: count,
                    pdfBlock: pdfBlock,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('no template for the record type says so instead of offering '
      'an empty picker', (tester) async {
    await _open(tester, const []);

    expect(
      find.textContaining('There are no templates for this record type'),
      findsOneWidget,
    );
    expect(find.text('Run'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('a single template is preselected and Run returns it, with '
      'Send Email off by default', (tester) async {
    final only = _design('t1', 'Statement');
    final results = await _open(tester, [only]);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single?.template, only);
    expect(results.single?.sendEmail, isFalse);
  });

  testWidgets('Send Email is carried in the choice', (tester) async {
    final results = await _open(tester, [_design('t1', 'Statement')]);

    await tester.tap(find.text('Send Email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(results.single?.sendEmail, isTrue);
  });

  testWidgets('a bulk run names how many records it covers', (tester) async {
    await _open(tester, [_design('t1', 'A'), _design('t2', 'B')], count: 3);

    expect(find.text('3 records selected'), findsOneWidget);
  });

  testWidgets('a user who cannot read the PDF back is locked to Send Email, '
      'and told why', (tester) async {
    final results = await _open(tester, [
      _design('t1', 'Statement'),
    ], pdfBlock: RunTemplatePdfBlock.permission);

    expect(
      find.textContaining('needs the View Reports permission'),
      findsOneWidget,
    );
    // Locked: tapping it changes nothing.
    await tester.tap(find.text('Send Email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(results.single?.sendEmail, isTrue);
  });
}
